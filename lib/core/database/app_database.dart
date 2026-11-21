import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../services/clock.dart';
import 'daos/accounts_dao.dart';
import 'daos/categories_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/transactions_dao.dart';
import 'daos/workspaces_dao.dart';
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
  ],
  daos: [WorkspacesDao, AccountsDao, CategoriesDao, SettingsDao, TransactionsDao],
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Step-by-step migrations are added here when schemaVersion is bumped
      // (generate with `dart run drift_dev make-migrations`). Refusing to open
      // is safer than running on a schema we do not understand.
      throw StateError('No migration path from schema $from to $to');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await DatabaseSeeder(this).seed();
    },
  );
}
