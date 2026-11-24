import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../services/clock.dart';
import 'daos/accounts_dao.dart';
import 'daos/budgets_dao.dart';
import 'daos/categories_dao.dart';
import 'daos/loans_dao.dart';
import 'daos/reports_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/transactions_dao.dart';
import 'daos/workspaces_dao.dart';
import 'migrations/add_loans.dart';
import 'migrations/add_savings_account_type.dart';
import 'migrations/remove_family_workspace.dart';
import 'seed/database_seeder.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Workspaces,
    WorkspaceMembers,
    Accounts,
    Categories,
    Transactions,
    Budgets,
    RecurringRules,
    RecurringExecutions,
    AppSettingsTable,
    Persons,
    LoanEntries,
  ],
  daos: [
    WorkspacesDao,
    AccountsDao,
    CategoriesDao,
    SettingsDao,
    TransactionsDao,
    ReportsDao,
    BudgetsDao,
    LoansDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(
    super.executor, {
    this.clock = const SystemClock(),
    this.ids = const UuidV7Generator(),
  });

  /// Opens the on-device database file `hisab.sqlite`.
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'hisab'));

  final Clock clock;
  final IdGenerator ids;

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (to > 4) throw StateError('No migration path from schema $from to $to');
      // v2: Family workspace removed (D14). No table changes.
      if (from < 2) await removeFamilyWorkspace(this);
      // v3: loans (D16). Only adds tables, so existing data is untouched.
      if (from < 3) await addLoanTables(this, m);
      // v4: 'savings' account type (D17). Rebuilds `accounts` to widen its CHECK.
      if (from < 4) await addSavingsAccountType(this, m);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await DatabaseSeeder(this).seed();
    },
  );
}
