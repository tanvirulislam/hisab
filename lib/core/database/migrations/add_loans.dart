import 'package:drift/drift.dart';

import '../app_database.dart';

/// Schema v3 (D16): adds the loan tables.
///
/// Purely additive: it creates new tables and indexes and never touches
/// existing ones, so a user's data cannot be lost by this migration.
/// `IF NOT EXISTS` makes it safe to run again after an interrupted upgrade.
Future<void> addLoanTables(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    for (final TableInfo<Table, dynamic> table in [db.persons, db.loanEntries]) {
      final exists = await db
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            variables: [Variable.withString(table.actualTableName)],
          )
          .get();
      if (exists.isEmpty) await m.createTable(table);
    }
    for (final index in [db.personsWorkspace, db.loanPerson, db.loanAccount]) {
      final exists = await db
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?",
            variables: [Variable.withString(index.entityName)],
          )
          .get();
      if (exists.isEmpty) await m.create(index);
    }
  });
}
