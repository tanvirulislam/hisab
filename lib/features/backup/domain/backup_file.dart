import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/errors/app_exception.dart';

/// Error codes of [BackupException] (D22). The UI maps each to l10n text.
abstract final class BackupError {
  static const notConfigured = 'backup.not_configured';
  static const notSignedIn = 'backup.not_signed_in';
  static const signInCancelled = 'backup.sign_in_cancelled';
  static const signInFailed = 'backup.sign_in_failed';
  static const network = 'backup.network';
  static const driveQuota = 'backup.drive_quota';
  static const driveError = 'backup.drive_error';
  static const corruptFile = 'backup.corrupt_file';
  static const checksumMismatch = 'backup.checksum_mismatch';
  static const unknownFormat = 'backup.unknown_format';
  static const tooNew = 'backup.too_new';
  static const tooOld = 'backup.too_old';
  static const invalidData = 'backup.invalid_data';
  static const busy = 'backup.busy';
  static const noSafetyBackup = 'backup.no_safety_backup';
}

/// One table's rows: column name → raw SQLite value (int, String or null).
typedef BackupRow = Map<String, Object?>;
typedef BackupTables = Map<String, List<BackupRow>>;

/// The header of a `.hisab` file (D13, D22).
class BackupHeader {
  const BackupHeader({
    required this.formatVersion,
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required this.counts,
    required this.sha256,
  });

  final int formatVersion;
  final int schemaVersion;
  final String appVersion;

  /// When the backup was taken (UTC in the file, local here).
  final DateTime createdAt;

  /// Rows per table, soft-deleted rows included.
  final Map<String, int> counts;
  final String sha256;

  Map<String, Object?> toJson() => {
    'format_version': formatVersion,
    'schema_version': schemaVersion,
    'app_version': appVersion,
    'created_at': createdAt.toUtc().toIso8601String(),
    'counts': counts,
    'sha256': sha256,
  };

  static BackupHeader fromJson(Object? json) {
    if (json is! Map) throw const BackupException(BackupError.corruptFile, 'header missing');
    try {
      return BackupHeader(
        formatVersion: json['format_version'] as int,
        schemaVersion: json['schema_version'] as int,
        appVersion: json['app_version'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        counts: (json['counts'] as Map).map((k, v) => MapEntry(k as String, v as int)),
        sha256: json['sha256'] as String,
      );
    } on BackupException {
      rethrow;
    } on Object catch (e) {
      throw BackupException(BackupError.corruptFile, 'bad header: $e');
    }
  }
}

/// A decoded backup: header plus every table's rows.
class BackupData {
  const BackupData({required this.header, required this.tables});

  final BackupHeader header;
  final BackupTables tables;
}

/// The bytes of a backup and the header written into them.
class EncodedBackup {
  const EncodedBackup({required this.bytes, required this.header});

  final Uint8List bytes;
  final BackupHeader header;
}

/// Encodes and decodes the `.hisab` file: gzip of UTF-8 JSON
/// `{"header": {...}, "tables": {...}}` (D13).
abstract final class BackupCodec {
  static const int formatVersion = 1;

  /// Canonical JSON of [tables]: table names and column names sorted, so
  /// the checksum does not depend on map order.
  static String canonicalJson(BackupTables tables) {
    final names = tables.keys.toList()..sort();
    return jsonEncode({
      for (final t in names)
        t: [
          for (final row in tables[t]!) {for (final c in (row.keys.toList()..sort())) c: row[c]},
        ],
    });
  }

  static String checksumOf(BackupTables tables) =>
      sha256.convert(utf8.encode(canonicalJson(tables))).toString();

  static EncodedBackup encode(
    BackupTables tables, {
    required int schemaVersion,
    required String appVersion,
    required DateTime createdAt,
  }) {
    final header = BackupHeader(
      formatVersion: formatVersion,
      schemaVersion: schemaVersion,
      appVersion: appVersion,
      createdAt: createdAt,
      counts: {for (final e in tables.entries) e.key: e.value.length},
      sha256: checksumOf(tables),
    );
    final json = jsonEncode({'header': header.toJson(), 'tables': tables});
    final bytes = GZipCodec().encode(utf8.encode(json));
    return EncodedBackup(bytes: Uint8List.fromList(bytes), header: header);
  }

  /// Decodes and checks the file itself: gzip, JSON, format version and
  /// checksum. Schema and data rules are checked by `BackupValidator`.
  static BackupData decode(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(GZipCodec().decode(bytes)));
    } on Object catch (e) {
      throw BackupException(BackupError.corruptFile, '$e');
    }
    if (json is! Map) throw const BackupException(BackupError.corruptFile, 'not an object');
    final header = BackupHeader.fromJson(json['header']);
    if (header.formatVersion != formatVersion) {
      throw BackupException(BackupError.unknownFormat, 'format ${header.formatVersion}');
    }
    final rawTables = json['tables'];
    if (rawTables is! Map) throw const BackupException(BackupError.corruptFile, 'tables missing');
    final BackupTables tables;
    try {
      tables = {
        for (final e in rawTables.entries)
          e.key as String: [for (final r in e.value as List) (r as Map).cast<String, Object?>()],
      };
    } on Object catch (e) {
      throw BackupException(BackupError.corruptFile, 'bad tables: $e');
    }
    if (checksumOf(tables) != header.sha256) {
      throw const BackupException(BackupError.checksumMismatch);
    }
    return BackupData(header: header, tables: tables);
  }

  /// `hisab-backup-20261127-093005.hisab`
  static String fileName(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'hisab-backup-${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}.hisab';
  }
}

/// Brings an older backup up to [targetSchema] before it is validated.
///
/// No upgrade exists yet: schema 4 is the first schema that backups are
/// written with, so every older file is refused. When the schema changes,
/// add a step here that rewrites `tables` the same way the DB migration does.
abstract final class BackupUpgrader {
  static BackupData upgrade(BackupData data, {required int targetSchema}) {
    final from = data.header.schemaVersion;
    if (from > targetSchema) throw BackupException(BackupError.tooNew, 'schema $from');
    if (from < targetSchema) throw BackupException(BackupError.tooOld, 'schema $from');
    return data;
  }
}
