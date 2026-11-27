import 'backup_file.dart';

/// What a backup holds, for the restore preview (D22). Counts are rows the
/// user can see (soft-deleted rows are in the file but not counted here).
class BackupSummary {
  const BackupSummary({
    required this.createdAt,
    required this.transactions,
    required this.accounts,
    required this.categories,
    required this.budgets,
    required this.persons,
    required this.loanEntries,
  });

  final DateTime createdAt;
  final int transactions;
  final int accounts;
  final int categories;
  final int budgets;
  final int persons;
  final int loanEntries;

  static BackupSummary of(BackupData data) {
    int live(String table) => (data.tables[table] ?? const []).where((r) => r['deleted_at'] == null).length;
    return BackupSummary(
      createdAt: data.header.createdAt,
      transactions: liveTransactionCount(data.tables),
      accounts: live('accounts'),
      categories: live('categories'),
      budgets: live('budgets'),
      persons: live('persons'),
      loanEntries: live('loan_entries'),
    );
  }

  /// Live transactions, a transfer counted once (its two legs are one entry).
  static int liveTransactionCount(BackupTables tables) => (tables['transactions'] ?? const [])
      .where((r) => r['deleted_at'] == null && r['type'] != 'transfer_in')
      .length;
}

/// A backup file on Drive, as the restore list shows it (no download needed).
class RemoteBackup {
  const RemoteBackup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.transactionCount,
    required this.schemaVersion,
    this.sizeBytes,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int? transactionCount;
  final int? schemaVersion;
  final int? sizeBytes;

  /// Drive `appProperties` written with every upload.
  static Map<String, String> appPropertiesFor(BackupHeader h, int txCount) => {
    'hisab_format': '${h.formatVersion}',
    'schema': '${h.schemaVersion}',
    'created_at': h.createdAt.toUtc().toIso8601String(),
    'tx_count': '$txCount',
  };
}
