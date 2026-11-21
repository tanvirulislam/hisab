import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/constants/default_categories.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/database/seed/database_seeder.dart';

import '../../helpers/test_db.dart';

int _countDefaults() {
  var n = 0;
  for (final c in [...defaultExpenseCategories, ...defaultIncomeCategories]) {
    n += 1 + c.children.length;
  }
  return n;
}

void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDb());
  tearDown(() => db.close());

  group('seeding', () {
    test('creates Personal and Family workspaces with an owner and a Cash account each', () async {
      final ws = await db.select(db.workspaces).get();
      expect(ws.map((w) => w.type).toSet(), {'personal', 'family'});
      expect(ws, hasLength(2));

      for (final w in ws) {
        final members = await (db.select(db.workspaceMembers)
              ..where((m) => m.workspaceId.equals(w.id)))
            .get();
        expect(members.single.role, 'owner');
        final accounts = await (db.select(db.accounts)
              ..where((a) => a.workspaceId.equals(w.id)))
            .get();
        expect(accounts.single.type, 'cash');
        expect(accounts.single.openingBalancePaisa, 0);
      }
    });

    test('creates the full default category tree with correct parents and types', () async {
      final cats = await db.select(db.categories).get();
      expect(cats, hasLength(_countDefaults()));
      expect(cats, hasLength(69));

      final byId = {for (final c in cats) c.id: c};
      final fish = cats.singleWhere((c) => c.systemKey == 'grocery.fish');
      expect(byId[fish.parentId]!.systemKey, 'grocery');
      expect(fish.type, 'expense');
      expect(fish.color, byId[fish.parentId]!.color, reason: 'inherits parent color');

      final salary = cats.singleWhere((c) => c.systemKey == 'income.salary');
      expect(salary.type, 'income');
      expect(salary.parentId, isNull);

      // Defaults are global (shared by both workspaces).
      expect(cats.every((c) => c.workspaceId == null), isTrue);
      // Fallback categories exist.
      for (final key in SystemCategoryKeys.protectedKeys) {
        expect(cats.where((c) => c.systemKey == key), hasLength(1));
      }
    });

    test('is idempotent: running again inserts nothing', () async {
      await DatabaseSeeder(db).seed();
      await DatabaseSeeder(db).seed();
      expect(await db.select(db.workspaces).get(), hasLength(2));
      expect(await db.select(db.accounts).get(), hasLength(2));
      expect(await db.select(db.workspaceMembers).get(), hasLength(2));
      expect(await db.select(db.categories).get(), hasLength(69));
    });

    test('does not resurrect a seeded category the user archived', () async {
      final fish = await categoryByKey(db, 'grocery.fish');
      await (db.update(db.categories)..where((c) => c.id.equals(fish.id)))
          .write(const CategoriesCompanion(isActive: Value(false)));
      await DatabaseSeeder(db).seed();
      final again = await categoryByKey(db, 'grocery.fish');
      expect(again.isActive, isFalse);
    });

    test('restores only missing categories (e.g. a key added in a future version)', () async {
      final eggs = await categoryByKey(db, 'grocery.eggs');
      await (db.delete(db.categories)..where((c) => c.id.equals(eggs.id))).go();
      await DatabaseSeeder(db).seed();
      final restored = await categoryByKey(db, 'grocery.eggs');
      final grocery = await categoryByKey(db, 'grocery');
      expect(restored.parentId, grocery.id);
      expect(await db.select(db.categories).get(), hasLength(69));
    });
  });

  group('integrity constraints', () {
    test('foreign keys are enforced', () async {
      final now = testNow.millisecondsSinceEpoch;
      expect(
        () => db.into(db.accounts).insert(AccountsCompanion.insert(
              id: 'a1', workspaceId: 'missing', name: 'X', type: 'cash',
              createdAt: now, updatedAt: now)),
        throwsA(isA<Exception>()),
      );
    });

    test('amount must be positive (rule: amount > 0)', () async {
      final ws = await workspaceOfType(db, 'personal');
      final acc = await firstAccountOf(db, ws.id);
      final cat = await categoryByKey(db, 'food');
      for (final amount in [0, -100]) {
        expect(
          () => insertTxn(db, workspaceId: ws.id, accountId: acc.id,
              type: 'expense', amountPaisa: amount, categoryId: cat.id),
          throwsA(isA<Exception>()),
          reason: 'amount $amount',
        );
      }
    });

    test('expense requires a category; transfer legs forbid one', () async {
      final ws = await workspaceOfType(db, 'personal');
      final acc = await firstAccountOf(db, ws.id);
      final cat = await categoryByKey(db, 'food');
      final family = await workspaceOfType(db, 'family');
      final other = await firstAccountOf(db, family.id);

      expect(
        () => insertTxn(db, workspaceId: ws.id, accountId: acc.id,
            type: 'expense', amountPaisa: 100),
        throwsA(isA<Exception>()),
      );
      expect(
        () => insertTxn(db, workspaceId: ws.id, accountId: acc.id,
            type: 'transfer_out', amountPaisa: 100, categoryId: cat.id,
            transferGroupId: 'g', counterAccountId: other.id),
        throwsA(isA<Exception>()),
      );
      expect(
        () => insertTxn(db, workspaceId: ws.id, accountId: acc.id,
            type: 'transfer_out', amountPaisa: 100, transferGroupId: 'g'),
        throwsA(isA<Exception>()),
        reason: 'missing counter account',
      );
      expect(
        () => insertTxn(db, workspaceId: ws.id, accountId: acc.id,
            type: 'transfer_out', amountPaisa: 100, transferGroupId: 'g',
            counterAccountId: acc.id),
        throwsA(isA<Exception>()),
        reason: 'transfer to the same account',
      );
    });

    test('refund requires refund_of_id and only refunds may have one', () async {
      final ws = await workspaceOfType(db, 'personal');
      final acc = await firstAccountOf(db, ws.id);
      final cat = await categoryByKey(db, 'food');
      await insertTxn(db, id: 'e1', workspaceId: ws.id, accountId: acc.id,
          type: 'expense', amountPaisa: 500, categoryId: cat.id);
      expect(
        () => insertTxn(db, workspaceId: ws.id, accountId: acc.id,
            type: 'refund', amountPaisa: 100, categoryId: cat.id),
        throwsA(isA<Exception>()),
      );
      expect(
        () => insertTxn(db, workspaceId: ws.id, accountId: acc.id,
            type: 'expense', amountPaisa: 100, categoryId: cat.id, refundOfId: 'e1'),
        throwsA(isA<Exception>()),
      );
      await insertTxn(db, workspaceId: ws.id, accountId: acc.id,
          type: 'refund', amountPaisa: 100, categoryId: cat.id, refundOfId: 'e1');
    });

    test('unknown enum values are rejected', () async {
      final now = testNow.millisecondsSinceEpoch;
      expect(
        () => db.into(db.workspaces).insert(WorkspacesCompanion.insert(
            id: 'w', name: 'W', type: 'business', createdAt: now, updatedAt: now)),
        throwsA(isA<Exception>()),
      );
      final ws = await workspaceOfType(db, 'personal');
      expect(
        () => db.into(db.accounts).insert(AccountsCompanion.insert(
            id: 'a', workspaceId: ws.id, name: 'A', type: 'crypto',
            createdAt: now, updatedAt: now)),
        throwsA(isA<Exception>()),
      );
    });

    test('one active budget per workspace, category and month', () async {
      final ws = await workspaceOfType(db, 'family');
      final cat = await categoryByKey(db, 'grocery');
      final now = testNow.millisecondsSinceEpoch;
      BudgetsCompanion budget(String id) => BudgetsCompanion.insert(
          id: id, workspaceId: ws.id, categoryId: cat.id, amountPaisa: 600000,
          year: 2026, month: 11, createdAt: now, updatedAt: now);

      await db.into(db.budgets).insert(budget('b1'));
      expect(() => db.into(db.budgets).insert(budget('b2')), throwsA(isA<Exception>()));

      // After soft-deleting the first, a new one is allowed (partial index).
      await (db.update(db.budgets)..where((b) => b.id.equals('b1')))
          .write(BudgetsCompanion(deletedAt: Value(now)));
      await db.into(db.budgets).insert(budget('b3'));
    });

    test('a recurring occurrence can only be executed once', () async {
      final ws = await workspaceOfType(db, 'personal');
      final acc = await firstAccountOf(db, ws.id);
      final cat = await categoryByKey(db, 'rent_bills');
      final now = testNow.millisecondsSinceEpoch;
      await db.into(db.recurringRules).insert(RecurringRulesCompanion.insert(
          id: 'r1', workspaceId: ws.id, type: 'expense', accountId: acc.id,
          categoryId: Value(cat.id), amountPaisa: 1500000, frequency: 'monthly',
          startDate: 20261101, nextDueDate: 20261201, createdAt: now, updatedAt: now));
      RecurringExecutionsCompanion exec(String id) => RecurringExecutionsCompanion.insert(
          id: id, ruleId: 'r1', occurrenceDate: 20261101, executedAt: now);
      await db.into(db.recurringExecutions).insert(exec('x1'));
      expect(() => db.into(db.recurringExecutions).insert(exec('x2')),
          throwsA(isA<Exception>()));
    });
  });

  group('derived account balance (rules 1–3, D6)', () {
    test('opening + income + refund + transfer_in − expense − transfer_out; deleted rows ignored', () async {
      final personal = await workspaceOfType(db, 'personal');
      final family = await workspaceOfType(db, 'family');
      final pCash = await firstAccountOf(db, personal.id);
      final fCash = await firstAccountOf(db, family.id);
      final food = await categoryByKey(db, 'food');
      final salary = await categoryByKey(db, 'income.salary');

      await (db.update(db.accounts)..where((a) => a.id.equals(pCash.id)))
          .write(const AccountsCompanion(openingBalancePaisa: Value(100000)));

      await insertTxn(db, workspaceId: personal.id, accountId: pCash.id,
          type: 'income', amountPaisa: 5000000, categoryId: salary.id);
      await insertTxn(db, id: 'lunch', workspaceId: personal.id, accountId: pCash.id,
          type: 'expense', amountPaisa: 15000, categoryId: food.id);
      await insertTxn(db, workspaceId: personal.id, accountId: pCash.id,
          type: 'refund', amountPaisa: 5000, categoryId: food.id, refundOfId: 'lunch');
      await insertTxn(db, workspaceId: personal.id, accountId: pCash.id,
          type: 'expense', amountPaisa: 99999, categoryId: food.id,
          deletedAt: testNow.millisecondsSinceEpoch);
      // Cross-workspace transfer of ৳2,000: Personal → Family.
      await insertTxn(db, workspaceId: personal.id, accountId: pCash.id,
          type: 'transfer_out', amountPaisa: 200000, transferGroupId: 'g1',
          counterAccountId: fCash.id);
      await insertTxn(db, workspaceId: family.id, accountId: fCash.id,
          type: 'transfer_in', amountPaisa: 200000, transferGroupId: 'g1',
          counterAccountId: pCash.id);

      final personalRows = await db.accountsDao.watchWithBalances([personal.id]).first;
      final familyRows = await db.accountsDao.watchWithBalances([family.id]).first;
      final bothRows = await db.accountsDao.watchWithBalances([personal.id, family.id]).first;

      // 1,000 + 50,000 − 150 + 50 − 2,000 = 48,900 taka
      expect(personalRows.single.balancePaisa, 4890000);
      expect(familyRows.single.balancePaisa, 200000);
      // Combined total = opening + income − net expense; the transfer cancels out.
      final combined = bothRows.fold<int>(0, (s, r) => s + r.balancePaisa);
      expect(combined, 100000 + 5000000 - 15000 + 5000);
    });

    test('balance stream updates live after a write (rules 8–9)', () async {
      final personal = await workspaceOfType(db, 'personal');
      final cash = await firstAccountOf(db, personal.id);
      final food = await categoryByKey(db, 'food');
      final stream = db.accountsDao.watchWithBalances([personal.id]);

      final expectation = expectLater(
        stream.map((rows) => rows.single.balancePaisa),
        emitsInOrder([0, -8000]),
      );
      await Future<void>.delayed(Duration.zero);
      await insertTxn(db, workspaceId: personal.id, accountId: cash.id,
          type: 'expense', amountPaisa: 8000, categoryId: food.id);
      await expectation;
    });

    test('empty workspace list never runs an unscoped query', () async {
      expect(await db.accountsDao.watchWithBalances(const []).first, isEmpty);
    });
  });
}
