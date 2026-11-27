import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/backup_file.dart';
import '../domain/backup_validator.dart';

/// Turns the database into a backup and a backup back into the database
/// (D13, D22). Tables are read and written generically, so a new table is
/// included without code changes (the check against tables.dart catches a
/// table that drift does not know).
class BackupRepository {
  BackupRepository(this._db, {@visibleForTesting this.faultAfterTable});

  final AppDatabase _db;

  /// Tests: throw after this table's rows were inserted during a restore.
  final String? faultAfterTable;

  int get schemaVersion => _db.schemaVersion;

  // ------------------------------------------------------------------ schema

  BackupSchema? _schema;

  /// Every app table with its columns and foreign keys, parents first.
  Future<BackupSchema> schema() async => _schema ??= await _readSchema();

  Future<BackupSchema> _readSchema() async {
    final names = (await _db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'drift_%' AND name NOT LIKE 'android_%'",
            )
            .get())
        .map((r) => r.read<String>('name'))
        .toSet();
    final known = {for (final t in _db.allTables) t.actualTableName};
    if (!setEquals(names, known)) {
      throw StorageException('backup.schema', 'db tables $names differ from tables.dart $known');
    }

    final byName = <String, TableSchema>{};
    for (final name in names) {
      final cols = await _db.customSelect('PRAGMA table_info("$name")').get();
      final fks = await _db.customSelect('PRAGMA foreign_key_list("$name")').get();
      final pk = [
        for (final c in cols.where((c) => c.read<int>('pk') > 0).toList()
          ..sort((a, b) => a.read<int>('pk').compareTo(b.read<int>('pk'))))
          c.read<String>('name'),
      ];
      byName[name] = TableSchema(
        name: name,
        columns: {for (final c in cols) c.read<String>('name')},
        required: {
          for (final c in cols)
            if (c.read<int>('notnull') == 1) c.read<String>('name'),
        },
        primaryKey: pk,
        foreignKeys: [
          for (final f in fks)
            ForeignKeyRef(f.read<String>('from'), f.read<String>('table'), f.readNullable<String>('to') ?? 'id'),
        ],
      );
    }

    // Parents before children; self references (category parents, refunds)
    // are handled by deferring foreign keys during the restore.
    final ordered = <TableSchema>[];
    final placed = <String>{};
    while (ordered.length < byName.length) {
      final next = byName.values
          .where((t) => !placed.contains(t.name))
          .where((t) => t.foreignKeys.every((f) => f.toTable == t.name || placed.contains(f.toTable)))
          .map((t) => t.name)
          .toList()
        ..sort();
      if (next.isEmpty) throw const StorageException('backup.schema', 'foreign key cycle');
      for (final n in next) {
        ordered.add(byName[n]!);
        placed.add(n);
      }
    }
    return BackupSchema(ordered);
  }

  // ------------------------------------------------------------------ export

  /// Every row of every app table, soft-deleted rows included.
  Future<BackupTables> dumpTables() async {
    final s = await schema();
    final tables = <String, List<BackupRow>>{};
    for (final t in s.tables) {
      final order = t.primaryKey.map((c) => '"$c"').join(', ');
      final rows = await _db.customSelect('SELECT * FROM "${t.name}" ORDER BY $order').get();
      tables[t.name] = [for (final r in rows) Map<String, Object?>.of(r.data)];
    }
    return tables;
  }

  Future<EncodedBackup> export({required String appVersion, required DateTime now}) async =>
      BackupCodec.encode(
        await dumpTables(),
        schemaVersion: schemaVersion,
        appVersion: appVersion,
        createdAt: now,
      );

  /// Cheap change detector: rows and newest `updated_at` per table.
  Future<String> fingerprint() async {
    final s = await schema();
    final parts = <String>[];
    for (final t in s.tables) {
      final stamp = t.columns.contains('updated_at') ? 'MAX(updated_at)' : 'NULL';
      final r = await _db.customSelect('SELECT COUNT(*) AS n, $stamp AS u FROM "${t.name}"').getSingle();
      parts.add('${t.name}:${r.read<int>('n')}:${r.readNullable<int>('u') ?? 0}');
    }
    return parts.join('|');
  }

  /// Anything the user made: transactions, people or budgets. Seeded
  /// categories and accounts do not count.
  Stream<bool> watchHasUserData() => _db
      .customSelect(
        'SELECT (SELECT COUNT(*) FROM transactions) + (SELECT COUNT(*) FROM persons) '
        '+ (SELECT COUNT(*) FROM budgets) + (SELECT COUNT(*) FROM loan_entries) AS n',
        readsFrom: {_db.transactions, _db.persons, _db.budgets, _db.loanEntries},
      )
      .watchSingle()
      .map((r) => r.read<int>('n') > 0);

  Future<bool> hasUserData() => watchHasUserData().first;

  // ----------------------------------------------------------------- restore

  /// Decodes and fully validates [bytes] in memory. Nothing is written.
  Future<BackupData> prepare(List<int> bytes) async {
    final decoded = BackupCodec.decode(bytes);
    final data = BackupUpgrader.upgrade(decoded, targetSchema: schemaVersion);
    BackupValidator.validate(data, await schema());
    return data;
  }

  /// Replaces all data with [data] in one transaction. Any failure rolls
  /// everything back, so the data is never half-restored.
  Future<void> restore(BackupData data) async {
    final s = await schema();
    BackupValidator.validate(data, s);
    await _db.transaction(() async {
      // Checked at commit, so self references and order do not matter.
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final t in s.tables.reversed) {
        await _db.customStatement('DELETE FROM "${t.name}"');
      }
      for (final t in s.tables) {
        await _insertAll(t, data.tables[t.name]!);
        if (faultAfterTable == t.name) throw StateError('injected fault after ${t.name}');
      }
      final broken = await _db.customSelect('PRAGMA foreign_key_check').get();
      if (broken.isNotEmpty) {
        throw BackupException(BackupError.invalidData, 'foreign_key_check: ${broken.first.data}');
      }
      // Read back what was written and check it again.
      final written = await dumpTables();
      for (final t in s.tables) {
        if (written[t.name]!.length != data.tables[t.name]!.length) {
          throw BackupException(BackupError.invalidData, 'row count differs in ${t.name}');
        }
      }
      BackupValidator.checkDomainRules(written);
    });
    // Raw statements do not notify drift's streams: tell every query to reload.
    _db.notifyUpdates({for (final t in _db.allTables) TableUpdate.onTable(t)});
  }

  Future<void> _insertAll(TableSchema t, List<BackupRow> rows) async {
    if (rows.isEmpty) return;
    final cols = t.columns.toList()..sort();
    final colList = cols.map((c) => '"$c"').join(', ');
    final rowMarks = '(${List.filled(cols.length, '?').join(', ')})';
    // Stay well under SQLite's bound-variable limit.
    final perChunk = (900 ~/ cols.length).clamp(1, 200);
    for (var i = 0; i < rows.length; i += perChunk) {
      final chunk = rows.sublist(i, (i + perChunk).clamp(0, rows.length));
      final args = [
        for (final r in chunk)
          for (final c in cols) r[c],
      ];
      // A missing nullable column is inserted as NULL; NOT NULL columns were
      // checked by the validator.
      await _db.customStatement(
        'INSERT INTO "${t.name}" ($colList) VALUES ${List.filled(chunk.length, rowMarks).join(', ')}',
        args,
      );
    }
  }
}
