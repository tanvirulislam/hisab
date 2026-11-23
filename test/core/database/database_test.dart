import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/constants/default_categories.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/database/migrations/add_loans.dart';
import 'package:hisab/core/database/migrations/remove_family_workspace.dart';
import 'package:hisab/core/database/seed/database_seeder.dart';
import 'package:hisab/core/services/clock.dart';

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
    test('creates the single Personal workspace with an owner and a Cash account (D14)', () async {
      final ws = await db.select(db.workspaces).get();
      expect(ws.map((w) => w.type), ['personal']);

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
      expect(await db.select(db.workspaces).get(), hasLength(1));
      expect(await db.select(db.accounts).get(), hasLength(1));
      expect(await db.select(db.workspaceMembers).get(), hasLength(1));
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
      final otherId = await addAccount(db, ws.id);

      expect(
        () => insertTxn(db, workspaceId: ws.id, accountId: acc.id,
            type: 'expense', amountPaisa: 100),
        throwsA(isA<Exception>()),
      );
      expect(
        () => insertTxn(db, workspaceId: ws.id, accountId: acc.id,
            type: 'transfer_out', amountPaisa: 100, categoryId: cat.id,
            transferGroupId: 'g', counterAccountId: otherId),
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
      final ws = await workspaceOfType(db, 'personal');
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
      final pCash = await firstAccountOf(db, personal.id);
      final bkash = await addAccount(db, personal.id);
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
      // Transfer of ৳2,000: Cash → bKash.
      await insertTxn(db, workspaceId: personal.id, accountId: pCash.id,
          type: 'transfer_out', amountPaisa: 200000, transferGroupId: 'g1',
          counterAccountId: bkash);
      await insertTxn(db, workspaceId: personal.id, accountId: bkash,
          type: 'transfer_in', amountPaisa: 200000, transferGroupId: 'g1',
          counterAccountId: pCash.id);

      final rows = await db.accountsDao.watchWithBalances([personal.id]).first;
      int balanceOf(String id) => rows.singleWhere((r) => r.account.id == id).balancePaisa;

      // 1,000 + 50,000 − 150 + 50 − 2,000 = 48,900 taka
      expect(balanceOf(pCash.id), 4890000);
      expect(balanceOf(bkash), 200000);
      // Total = opening + income − net expense; the transfer cancels out.
      final total = rows.fold<int>(0, (s, r) => s + r.balancePaisa);
      expect(total, 100000 + 5000000 - 15000 + 5000);
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

  group('schema v2: Family workspace removal (D14)', () {
    test('deletes Family data and cross transfers, keeps Personal data', () async {
      final personal = await workspaceOfType(db, 'personal');
      final pCash = await firstAccountOf(db, personal.id);
      final food = await categoryByKey(db, 'food');
      final now = testNow.millisecondsSinceEpoch;

      // A Family workspace as an older build seeded it, with data.
      await db.into(db.workspaces).insert(WorkspacesCompanion.insert(
          id: 'fam', name: 'Family', type: 'family', createdAt: now, updatedAt: now));
      await db.into(db.workspaceMembers).insert(WorkspaceMembersCompanion.insert(
          id: 'm', workspaceId: 'fam', memberRef: 'local-owner', role: 'owner', createdAt: now, updatedAt: now));
      await addAccount(db, 'fam', id: 'fCash', name: 'Cash', type: 'cash');
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'kids', workspaceId: const Value('fam'), type: 'expense', name: 'Kids',
          icon: 'label', color: 0xFF000000, createdAt: now, updatedAt: now));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'kids.school', workspaceId: const Value('fam'), parentId: const Value('kids'), type: 'expense',
          name: 'School', icon: 'label', color: 0xFF000000, createdAt: now, updatedAt: now));
      await insertTxn(db, id: 'f1', workspaceId: 'fam', accountId: 'fCash',
          type: 'expense', amountPaisa: 50000, categoryId: 'kids');
      await insertTxn(db, id: 'f1r', workspaceId: 'fam', accountId: 'fCash',
          type: 'refund', amountPaisa: 1000, categoryId: 'kids', refundOfId: 'f1');
      // Personal → Family transfer.
      await insertTxn(db, id: 'x1', workspaceId: personal.id, accountId: pCash.id,
          type: 'transfer_out', amountPaisa: 20000, transferGroupId: 'gx', counterAccountId: 'fCash');
      await insertTxn(db, id: 'x2', workspaceId: 'fam', accountId: 'fCash',
          type: 'transfer_in', amountPaisa: 20000, transferGroupId: 'gx', counterAccountId: pCash.id);
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
          id: 'fb', workspaceId: 'fam', categoryId: 'kids', amountPaisa: 100000,
          year: 2026, month: 11, createdAt: now, updatedAt: now));
      await db.into(db.recurringRules).insert(RecurringRulesCompanion.insert(
          id: 'fr', workspaceId: 'fam', type: 'expense', accountId: 'fCash',
          categoryId: const Value('kids'), amountPaisa: 5000, frequency: 'monthly',
          startDate: 20261101, nextDueDate: 20261201, createdAt: now, updatedAt: now));
      await db.into(db.recurringExecutions).insert(RecurringExecutionsCompanion.insert(
          id: 'fe', ruleId: 'fr', occurrenceDate: 20261101, executedAt: now, transactionId: const Value('f1')));
      // Personal data that must survive.
      await insertTxn(db, id: 'p1', workspaceId: personal.id, accountId: pCash.id,
          type: 'expense', amountPaisa: 35000, categoryId: food.id);

      await removeFamilyWorkspace(db);

      expect((await db.select(db.workspaces).get()).map((w) => w.type), ['personal']);
      expect((await db.select(db.transactions).get()).map((t) => t.id), ['p1'],
          reason: 'Family rows and both legs of the cross transfer are gone');
      expect(await db.select(db.accounts).get(), hasLength(1));
      expect(await db.select(db.budgets).get(), isEmpty);
      expect(await db.select(db.recurringRules).get(), isEmpty);
      expect(await db.select(db.recurringExecutions).get(), isEmpty);
      expect(await db.select(db.workspaceMembers).get(), hasLength(1));
      final cats = await db.select(db.categories).get();
      expect(cats.where((c) => c.id.startsWith('kids')), isEmpty);
      expect(cats.where((c) => c.systemKey == 'food'), hasLength(1), reason: 'global categories stay');
      // Foreign keys still hold.
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test('opening a v1 database file runs the migration', () async {
      final dir = await Directory.systemTemp.createTemp('hisab_mig');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/hisab.sqlite');
      final now = testNow.millisecondsSinceEpoch;

      // A v1 file with a Family workspace, as an older build left it.
      final old = AppDatabase(NativeDatabase(file), clock: FixedClock(testNow));
      await old.into(old.workspaces).insert(WorkspacesCompanion.insert(
          id: 'fam', name: 'Family', type: 'family', createdAt: now, updatedAt: now));
      await addAccount(old, 'fam', id: 'fCash', name: 'Cash', type: 'cash');
      await old.customStatement('PRAGMA user_version = 1');
      await old.close();

      final upgraded = AppDatabase(NativeDatabase(file), clock: FixedClock(testNow));
      addTearDown(upgraded.close);
      expect((await upgraded.select(upgraded.workspaces).get()).map((w) => w.type), ['personal']);
      expect(await upgraded.select(upgraded.accounts).get(), hasLength(1));
      expect((await upgraded.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), 3);
    });

    test('is a no-op without a Family workspace', () async {
      final before = await db.select(db.categories).get();
      await removeFamilyWorkspace(db);
      expect(await db.select(db.categories).get(), hasLength(before.length));
      expect(await db.select(db.workspaces).get(), hasLength(1));
    });
  });
  group('schema v3: loans (D16)', () {
    test('upgrading a v2 file adds the loan tables and keeps every existing row', () async {
      final dir = await Directory.systemTemp.createTemp('hisab_mig3');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/hisab.sqlite');

      // A v2 file as the previous build left it: no loan tables, real data.
      final old = AppDatabase(NativeDatabase(file), clock: FixedClock(testNow));
      await old.customSelect('SELECT 1').get(); // open + seed
      final ws = await workspaceOfType(old, 'personal');
      final cash = await firstAccountOf(old, ws.id);
      final food = await categoryByKey(old, 'food');
      await old.accountsDao.updateRow(cash.id, const AccountsCompanion(openingBalancePaisa: Value(100000)));
      await insertTxn(old, id: 'e1', workspaceId: ws.id, accountId: cash.id,
          type: 'expense', amountPaisa: 25000, categoryId: food.id);
      await insertTxn(old, id: 'e2', workspaceId: ws.id, accountId: cash.id,
          type: 'income', amountPaisa: 70000, categoryId: (await categoryByKey(old, 'income.salary')).id);
      await old.customStatement('DROP INDEX loan_person');
      await old.customStatement('DROP INDEX loan_account');
      await old.customStatement('DROP INDEX persons_workspace');
      await old.customStatement('DROP TABLE loan_entries');
      await old.customStatement('DROP TABLE persons');
      await old.customStatement('PRAGMA user_version = 2');
      final txnsBefore = await old.select(old.transactions).get();
      final catsBefore = await old.select(old.categories).get();
      await old.close();

      final upgraded = AppDatabase(NativeDatabase(file), clock: FixedClock(testNow));
      addTearDown(upgraded.close);
      expect((await upgraded.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), 3);

      // Nothing that existed before was lost or changed.
      expect((await upgraded.select(upgraded.transactions).get()).map((t) => (t.id, t.amountPaisa, t.type)),
          txnsBefore.map((t) => (t.id, t.amountPaisa, t.type)));
      expect(await upgraded.select(upgraded.categories).get(), hasLength(catsBefore.length));
      final balances = await upgraded.accountsDao.watchWithBalances([ws.id]).first;
      expect(balances.single.balancePaisa, 100000 - 25000 + 70000);

      // The new tables and their indexes exist and work.
      final names = (await upgraded.customSelect(
              'SELECT name FROM sqlite_master WHERE name IN '
              "('persons', 'loan_entries', 'persons_workspace', 'loan_person', 'loan_account')")
          .get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(names, {'persons', 'loan_entries', 'persons_workspace', 'loan_person', 'loan_account'});
      expect(await upgraded.select(upgraded.persons).get(), isEmpty);
      expect(await upgraded.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test('the migration can run twice without failing (interrupted upgrade)', () async {
      await db.transaction(() => addLoanTables(db, db.createMigrator()));
      expect(await db.select(db.persons).get(), isEmpty);
    });

    test('loan rows are constrained: positive amount, known kind, repayment needs an account', () async {
      final ws = await workspaceOfType(db, 'personal');
      final cash = await firstAccountOf(db, ws.id);
      final now = testNow.millisecondsSinceEpoch;
      await db.into(db.persons).insert(PersonsCompanion.insert(
          id: 'p', workspaceId: ws.id, name: 'Karim', createdAt: now, updatedAt: now));
      LoanEntriesCompanion entry(String id, {String kind = 'lent', int amount = 100, String? account}) =>
          LoanEntriesCompanion.insert(id: id, workspaceId: ws.id, personId: 'p', kind: kind,
              amountPaisa: amount, localDate: 20261121, accountId: Value(account),
              createdAt: now, updatedAt: now);

      await db.into(db.loanEntries).insert(entry('ok', account: cash.id));
      await db.into(db.loanEntries).insert(entry('old-loan')); // no account: allowed for lent
      expect(() => db.into(db.loanEntries).insert(entry('zero', amount: 0)), throwsA(isA<Exception>()));
      expect(() => db.into(db.loanEntries).insert(entry('bad', kind: 'gift')), throwsA(isA<Exception>()));
      expect(() => db.into(db.loanEntries).insert(entry('r', kind: 'repaid_to_me')), throwsA(isA<Exception>()),
          reason: 'a repayment moves money, so it needs an account');
    });
  });
}
