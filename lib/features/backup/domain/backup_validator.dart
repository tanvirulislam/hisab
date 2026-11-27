import '../../../core/errors/app_exception.dart';
import 'backup_file.dart';

/// A foreign key: `column` points at `toTable.toColumn`.
class ForeignKeyRef {
  const ForeignKeyRef(this.column, this.toTable, this.toColumn);

  final String column;
  final String toTable;
  final String toColumn;
}

/// What the database expects of one table.
class TableSchema {
  const TableSchema({
    required this.name,
    required this.columns,
    required this.required,
    required this.primaryKey,
    this.foreignKeys = const [],
  });

  final String name;
  final Set<String> columns;

  /// NOT NULL columns: every row must carry a value.
  final Set<String> required;
  final List<String> primaryKey;
  final List<ForeignKeyRef> foreignKeys;
}

/// Every app table, parents before children (insert order).
class BackupSchema {
  const BackupSchema(this.tables);

  final List<TableSchema> tables;

  TableSchema? operator [](String name) => tables.where((t) => t.name == name).firstOrNull;
}

/// Checks a decoded backup against the schema and the app's rules, all in
/// memory, before anything touches the database (D22). Throws
/// [BackupException] with [BackupError.invalidData] on the first problem.
abstract final class BackupValidator {
  static void validate(BackupData data, BackupSchema schema) {
    final tables = data.tables;
    Never fail(String why) => throw BackupException(BackupError.invalidData, why);

    final expected = {for (final t in schema.tables) t.name};
    final missing = expected.difference(tables.keys.toSet());
    final extra = tables.keys.toSet().difference(expected);
    if (missing.isNotEmpty) fail('missing tables $missing');
    if (extra.isNotEmpty) fail('unknown tables $extra');

    final counts = data.header.counts;
    for (final t in schema.tables) {
      if (counts[t.name] != tables[t.name]!.length) fail('count mismatch in ${t.name}');
    }

    // Columns and primary keys.
    final keys = <String, Map<String, Set<Object?>>>{};
    for (final t in schema.tables) {
      final seen = <String>{};
      for (final row in tables[t.name]!) {
        final unknown = row.keys.toSet().difference(t.columns);
        if (unknown.isNotEmpty) fail('${t.name}: unknown columns $unknown');
        for (final c in t.required) {
          if (row[c] == null) fail('${t.name}: $c is missing');
        }
        for (final v in row.values) {
          if (v != null && v is! String && v is! int && v is! double) fail('${t.name}: bad value $v');
        }
        if (!seen.add(t.primaryKey.map((c) => row[c]).join('\u0000'))) {
          fail('${t.name}: duplicate key');
        }
      }
    }

    // Foreign keys.
    Set<Object?> valuesOf(String table, String column) =>
        keys.putIfAbsent(table, () => {}).putIfAbsent(
          column,
          () => {for (final r in tables[table] ?? const <BackupRow>[]) r[column]},
        );
    for (final t in schema.tables) {
      for (final fk in t.foreignKeys) {
        for (final row in tables[t.name]!) {
          final v = row[fk.column];
          if (v != null && !valuesOf(fk.toTable, fk.toColumn).contains(v)) {
            fail('${t.name}.${fk.column} points at a missing ${fk.toTable}');
          }
        }
      }
    }

    checkDomainRules(tables);
  }

  /// The app rules a row-by-row check cannot see: exactly one workspace
  /// (D14), transfers in linked pairs (D4), repayments never larger than what
  /// is open (D16). Also run on the database after a restore.
  static void checkDomainRules(BackupTables tables) {
    Never fail(String why) => throw BackupException(BackupError.invalidData, why);

    if ((tables['workspaces'] ?? const []).length != 1) fail('expected exactly one workspace');

    final groups = <Object, List<BackupRow>>{};
    for (final r in tables['transactions'] ?? const <BackupRow>[]) {
      final g = r['transfer_group_id'];
      if (g != null) groups.putIfAbsent(g, () => []).add(r);
    }
    for (final legs in groups.values) {
      if (legs.length != 2) fail('transfer with ${legs.length} legs');
      final out = legs.where((r) => r['type'] == 'transfer_out').firstOrNull;
      final inn = legs.where((r) => r['type'] == 'transfer_in').firstOrNull;
      if (out == null || inn == null) fail('transfer without both legs');
      if (out['account_id'] != inn['counter_account_id'] ||
          inn['account_id'] != out['counter_account_id'] ||
          out['amount_paisa'] != inn['amount_paisa'] ||
          (out['deleted_at'] == null) != (inn['deleted_at'] == null)) {
        fail('transfer legs do not match');
      }
    }

    final sums = <Object?, Map<Object?, int>>{};
    for (final r in tables['loan_entries'] ?? const <BackupRow>[]) {
      if (r['deleted_at'] != null) continue;
      final byKind = sums.putIfAbsent(r['person_id'], () => {});
      byKind[r['kind']] = (byKind[r['kind']] ?? 0) + ((r['amount_paisa'] as num?)?.toInt() ?? 0);
    }
    for (final s in sums.values) {
      if ((s['repaid_to_me'] ?? 0) > (s['lent'] ?? 0) || (s['repaid_by_me'] ?? 0) > (s['borrowed'] ?? 0)) {
        fail('loan repaid more than lent/borrowed');
      }
    }
  }
}
