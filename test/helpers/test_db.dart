import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/services/clock.dart';

/// Fixed "now" used by tests: 21 Nov 2026, 10:00 local time.
final DateTime testNow = DateTime(2026, 11, 21, 10);

/// Fresh in-memory database, already opened and seeded.
Future<AppDatabase> openTestDb({Clock? clock}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(
    // Closes stream queries synchronously, so widget tests (fake async)
    // are not left with pending zero-duration timers.
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    clock: clock ?? FixedClock(testNow),
  );
  // Force open so beforeOpen (foreign keys + seeding) runs.
  await db.customSelect('SELECT 1').get();
  return db;
}

Future<WorkspaceRow> workspaceOfType(AppDatabase db, String type) =>
    (db.select(db.workspaces)..where((w) => w.type.equals(type))).getSingle();

Future<AccountRow> firstAccountOf(AppDatabase db, String workspaceId) =>
    (db.select(db.accounts)..where((a) => a.workspaceId.equals(workspaceId)))
        .get()
        .then((rows) => rows.first);

/// Adds a second account (e.g. bKash) to [workspaceId] and returns its id.
Future<String> addAccount(AppDatabase db, String workspaceId,
    {String id = 'bkash', String name = 'bKash', String type = 'bkash'}) async {
  final now = testNow.millisecondsSinceEpoch;
  await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: id, workspaceId: workspaceId, name: name, type: type, createdAt: now, updatedAt: now));
  return id;
}

Future<CategoryRow> categoryByKey(AppDatabase db, String key) =>
    (db.select(db.categories)..where((c) => c.systemKey.equals(key))).getSingle();

/// Inserts a raw ledger row (repositories with validation arrive in Phase 2).
Future<void> insertTxn(
  AppDatabase db, {
  required String workspaceId,
  required String accountId,
  required String type,
  required int amountPaisa,
  String? categoryId,
  String? transferGroupId,
  String? counterAccountId,
  String? refundOfId,
  int localDate = 20261121,
  int? deletedAt,
  String? id,
}) {
  final now = testNow.millisecondsSinceEpoch;
  return db.into(db.transactions).insert(
    TransactionsCompanion.insert(
      id: id ?? db.ids.newId(),
      workspaceId: workspaceId,
      accountId: accountId,
      type: type,
      amountPaisa: amountPaisa,
      categoryId: Value(categoryId),
      transferGroupId: Value(transferGroupId),
      counterAccountId: Value(counterAccountId),
      refundOfId: Value(refundOfId),
      localDate: localDate,
      occurredAt: now,
      createdAt: now,
      updatedAt: now,
      deletedAt: Value(deletedAt),
    ),
  );
}
