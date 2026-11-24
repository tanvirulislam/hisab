import 'package:drift/drift.dart';

import '../app_database.dart';

/// Schema v4 (D17): the `accounts.type` CHECK now allows 'savings'.
///
/// SQLite cannot change a CHECK constraint in place, so `accounts` is
/// rebuilt: drift creates the new table, copies every row (same columns, same
/// values), drops the old one, renames the new one and re-creates the table's
/// indexes. No row changes, so balances and every reference to an account
/// stay as they were. Skipped when the table already allows 'savings', which
/// also makes it safe to run again after an interrupted upgrade.
Future<void> addSavingsAccountType(AppDatabase db, Migrator m) async {
  final row = await db
      .customSelect("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'accounts'")
      .getSingleOrNull();
  final sql = row?.read<String?>('sql') ?? '';
  if (sql.contains("'savings'")) return;
  await m.alterTable(TableMigration(db.accounts));
}
