import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/errors/app_exception.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/transactions/data/drift_transaction_repository.dart';
import 'package:hisab/features/transactions/domain/drafts.dart';
import 'package:hisab/features/transactions/domain/history_filter.dart';
import 'package:hisab/features/transactions/domain/history_grouping.dart';
import 'package:hisab/features/transactions/domain/ledger_entry.dart';
import 'package:hisab/features/transactions/domain/transaction_repository.dart';
import 'package:hisab/features/transactions/domain/transaction_rules.dart';

import '../../helpers/test_db.dart';

Matcher throwsCode(String code) =>
    throwsA(isA<ValidationException>().having((e) => e.code, 'code', code));

void main() {
  late AppDatabase db;
  late DriftTransactionRepository repo;
  late String personal, family, pCash, fCash, food, lunch, fish, grocery, salary;
  late List<String> both;

  Future<int> balance(String accountId) async {
    final ws = (await db.accountsDao.findById(accountId))!.workspaceId;
    final rows = await db.accountsDao.watchWithBalances([ws]).first;
    return rows.singleWhere((r) => r.account.id == accountId).balancePaisa;
  }

  Future<HistoryPage> history(List<String> ids, [HistoryFilter f = const HistoryFilter(), int limit = 50]) =>
      repo.watchHistory(HistoryQuery(workspaceIds: ids, filter: f, limit: limit)).first;

  EntryDraft expense(int paisa, {String? ws, String? acc, String? cat, String? sub, String? desc, DateTime? at}) =>
      EntryDraft(
        type: EntryType.expense,
        workspaceId: ws ?? personal,
        accountId: acc ?? pCash,
        amount: Money(paisa),
        categoryId: cat ?? food,
        subcategoryId: sub,
        description: desc,
        occurredAt: at ?? testNow,
      );

  setUp(() async {
    db = await openTestDb();
    repo = DriftTransactionRepository(db);
    personal = (await workspaceOfType(db, 'personal')).id;
    family = (await workspaceOfType(db, 'family')).id;
    pCash = (await firstAccountOf(db, personal)).id;
    fCash = (await firstAccountOf(db, family)).id;
    food = (await categoryByKey(db, 'food')).id;
    lunch = (await categoryByKey(db, 'food.lunch')).id;
    fish = (await categoryByKey(db, 'grocery.fish')).id;
    grocery = (await categoryByKey(db, 'grocery')).id;
    salary = (await categoryByKey(db, 'income.salary')).id;
    both = [personal, family];
  });
  tearDown(() => db.close());

  group('income and expense', () {
    test('expense lowers and income raises the balance (rules 1–2)', () async {
      await repo.createEntry(expense(8000, desc: 'Office bus'));
      await repo.createEntry(EntryDraft(
        type: EntryType.income, workspaceId: personal, accountId: pCash,
        amount: Money.fromTaka(50000), categoryId: salary, occurredAt: testNow));
      expect(await balance(pCash), 5000000 - 8000);
    });

    test('stores the calendar date from occurredAt (D3) and trims description', () async {
      final id = await repo.createEntry(
          expense(100, desc: '  tea  ', at: DateTime(2026, 11, 20, 23, 59)));
      final row = (await db.transactionsDao.findById(id))!;
      expect(row.localDate, 20261120);
      expect(row.description, 'tea');
      final blank = await repo.createEntry(expense(100, desc: '   '));
      expect((await db.transactionsDao.findById(blank))!.description, isNull);
    });

    test('validation rejects bad input and persists nothing (§6.6)', () async {
      await expectLater(repo.createEntry(expense(0)), throwsCode(TxnError.amountInvalid));
      await expectLater(repo.createEntry(expense(-5)), throwsCode(TxnError.amountInvalid));
      await expectLater(repo.createEntry(expense(100, acc: 'nope')), throwsCode(TxnError.accountNotFound));
      await expectLater(repo.createEntry(expense(100, ws: 'nope')), throwsCode(TxnError.workspaceNotFound));
      await expectLater(repo.createEntry(expense(100, cat: salary)), throwsCode(TxnError.categoryTypeMismatch));
      await expectLater(repo.createEntry(expense(100, cat: lunch)), throwsCode(TxnError.categoryNotTopLevel));
      await expectLater(repo.createEntry(expense(100, sub: fish)), throwsCode(TxnError.subcategoryMismatch));
      await expectLater(repo.createEntry(expense(100, desc: 'x' * 501)), throwsCode(TxnError.descriptionTooLong));
      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test('rejects an account or category from another workspace (rule 11)', () async {
      await expectLater(repo.createEntry(expense(100, acc: fCash)),
          throwsCode(TxnError.accountWorkspaceMismatch));
      final now = testNow.millisecondsSinceEpoch;
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'fam-only', workspaceId: Value(family), type: 'expense', name: 'Kids',
          icon: 'label', color: 0, createdAt: now, updatedAt: now));
      await expectLater(repo.createEntry(expense(100, cat: 'fam-only')),
          throwsCode(TxnError.categoryWorkspaceMismatch));
      await repo.createEntry(expense(100, ws: family, acc: fCash, cat: 'fam-only'));
    });

    test('rejects inactive accounts for new entries but allows editing old ones', () async {
      final id = await repo.createEntry(expense(100));
      await (db.update(db.accounts)..where((a) => a.id.equals(pCash)))
          .write(const AccountsCompanion(isActive: Value(false)));
      await expectLater(repo.createEntry(expense(100)), throwsCode(TxnError.accountInactive));
      await repo.updateEntry(id, expense(250));
      expect(await balance(pCash), -250);
    });

    test('editing updates the balance and moves the entry (rule 8)', () async {
      final id = await repo.createEntry(expense(1000));
      await repo.updateEntry(id, expense(3000, ws: family, acc: fCash));
      expect(await balance(pCash), 0);
      expect(await balance(fCash), -3000);
      expect((await history([personal])).items, isEmpty);
      expect((await history([family])).items.single.entry.amount, const Money(3000));
    });

    test('subcategory must belong to the category', () async {
      await repo.createEntry(expense(35000, cat: grocery, sub: fish, desc: 'মাছ'));
      final item = (await history([personal])).items.single;
      expect(item.category!.systemKey, 'grocery');
      expect(item.subcategory!.systemKey, 'grocery.fish');
    });
  });

  group('transfers (rules 3–4, D4)', () {
    test('moves money between accounts without counting as income or expense', () async {
      final bkash = 'bkash-acc';
      final now = testNow.millisecondsSinceEpoch;
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: bkash, workspaceId: personal, name: 'bKash', type: 'bkash',
          createdAt: now, updatedAt: now));
      await repo.createTransfer(TransferDraft(
          fromAccountId: pCash, toAccountId: bkash, amount: const Money(50000), occurredAt: testNow));
      expect(await balance(pCash), -50000);
      expect(await balance(bkash), 50000);

      final page = await history([personal]);
      expect(page.items, hasLength(1), reason: 'both rows in scope are shown once');
      expect(page.items.single.fromAccount.id, pCash);
      expect(page.items.single.toAccount.id, bkash);
      expect(EntryTotals.of(page.items.map((i) => i.entry)), EntryTotals.zero);
    });

    test('cross-workspace transfer: each row in its own workspace, Combined nets to zero', () async {
      final group = await repo.createTransfer(TransferDraft(
          fromAccountId: pCash, toAccountId: fCash, amount: const Money(200000), occurredAt: testNow));
      final legs = await repo.transferLegs(group);
      expect(legs.map((l) => (l.kind, l.workspaceId)).toSet(),
          {(EntryKind.transferOut, personal), (EntryKind.transferIn, family)});

      expect((await history([personal])).items.single.entry.kind, EntryKind.transferOut);
      expect((await history([family])).items.single.entry.kind, EntryKind.transferIn);
      expect((await history(both)).items, hasLength(1));

      final combined = (await db.accountsDao.watchWithBalances(both).first)
          .fold<int>(0, (s, r) => s + r.balancePaisa);
      expect(combined, 0);
    });

    test('rejects transfers to the same account and missing accounts', () async {
      await expectLater(
          repo.createTransfer(TransferDraft(fromAccountId: pCash, toAccountId: pCash,
              amount: const Money(100), occurredAt: testNow)),
          throwsCode(TxnError.sameAccountTransfer));
      await expectLater(
          repo.createTransfer(TransferDraft(fromAccountId: pCash, toAccountId: 'x',
              amount: const Money(100), occurredAt: testNow)),
          throwsCode(TxnError.accountNotFound));
      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test('edit updates both rows; delete and undo act on both', () async {
      final group = await repo.createTransfer(TransferDraft(
          fromAccountId: pCash, toAccountId: fCash, amount: const Money(1000), occurredAt: testNow));
      await repo.updateTransfer(group, TransferDraft(
          fromAccountId: fCash, toAccountId: pCash, amount: const Money(700), occurredAt: testNow));
      expect(await balance(pCash), 700);
      expect(await balance(fCash), -700);

      final legId = (await repo.transferLegs(group)).first.id;
      final receipt = await repo.delete(legId);
      expect(receipt.ids, hasLength(2));
      expect(await balance(pCash), 0);
      expect(await balance(fCash), 0);
      await repo.restore(receipt);
      expect(await balance(pCash), 700);
    });

    test('account filter finds a transfer from either side', () async {
      await repo.createTransfer(TransferDraft(
          fromAccountId: pCash, toAccountId: fCash, amount: const Money(1000), occurredAt: testNow));
      for (final acc in [pCash, fCash]) {
        final page = await history(both, HistoryFilter(accountId: acc));
        expect(page.items, hasLength(1), reason: acc);
      }
    });
  });

  group('refunds (rule 7, D5)', () {
    test('refund raises the balance and lowers net expense, never income', () async {
      final id = await repo.createEntry(expense(50000, cat: grocery, sub: fish));
      await repo.createRefund(RefundDraft(
          originalId: id, accountId: pCash, amount: const Money(10000), occurredAt: testNow));
      expect(await balance(pCash), -40000);

      final items = (await history([personal])).items;
      final totals = EntryTotals.of(items.map((i) => i.entry));
      expect(totals.expense, const Money(40000));
      expect(totals.income, Money.zero);
      final refund = items.firstWhere((i) => i.entry.kind == EntryKind.refund);
      expect(refund.subcategory!.systemKey, 'grocery.fish', reason: 'copies the category');
    });

    test('total refunds cannot exceed the expense', () async {
      final id = await repo.createEntry(expense(1000));
      final r1 = await repo.createRefund(RefundDraft(
          originalId: id, accountId: pCash, amount: const Money(600), occurredAt: testNow));
      await expectLater(
          repo.createRefund(RefundDraft(originalId: id, accountId: pCash,
              amount: const Money(401), occurredAt: testNow)),
          throwsCode(TxnError.refundExceedsOriginal));
      await repo.createRefund(RefundDraft(
          originalId: id, accountId: pCash, amount: const Money(400), occurredAt: testNow));
      // Editing a refund excludes itself from the limit.
      await repo.updateRefund(r1, RefundDraft(
          originalId: id, accountId: pCash, amount: const Money(500), occurredAt: testNow));
      expect(await repo.refundedTotal(id), const Money(900));
    });

    test('only expenses can be refunded, into the same workspace', () async {
      final inc = await repo.createEntry(EntryDraft(type: EntryType.income, workspaceId: personal,
          accountId: pCash, amount: const Money(1000), categoryId: salary, occurredAt: testNow));
      await expectLater(
          repo.createRefund(RefundDraft(originalId: inc, accountId: pCash,
              amount: const Money(100), occurredAt: testNow)),
          throwsCode(TxnError.refundOriginalInvalid));
      final exp = await repo.createEntry(expense(1000));
      await expectLater(
          repo.createRefund(RefundDraft(originalId: exp, accountId: fCash,
              amount: const Money(100), occurredAt: testNow)),
          throwsCode(TxnError.accountWorkspaceMismatch));
    });

    test('expense with refunds: amount ≥ refunded, type fixed, category follows', () async {
      final id = await repo.createEntry(expense(1000));
      await repo.createRefund(RefundDraft(
          originalId: id, accountId: pCash, amount: const Money(600), occurredAt: testNow));
      await expectLater(repo.updateEntry(id, expense(500)), throwsCode(TxnError.amountBelowRefunded));
      await expectLater(
          repo.updateEntry(id, EntryDraft(type: EntryType.income, workspaceId: personal,
              accountId: pCash, amount: const Money(1000), categoryId: salary, occurredAt: testNow)),
          throwsCode(TxnError.typeChangeWithRefunds));
      await repo.updateEntry(id, expense(1000, cat: grocery));
      final refund = (await db.transactionsDao.refundsOf(id)).single;
      expect(refund.categoryId, grocery);
    });

    test('deleting an expense deletes its refunds; undo restores both', () async {
      final id = await repo.createEntry(expense(1000));
      await repo.createRefund(RefundDraft(
          originalId: id, accountId: pCash, amount: const Money(300), occurredAt: testNow));
      final receipt = await repo.delete(id);
      expect(receipt.ids, hasLength(2));
      expect(await balance(pCash), 0);
      await repo.restore(receipt);
      expect(await balance(pCash), -700);
    });

    test('undoing a refund deletion re-checks the refund limit', () async {
      final id = await repo.createEntry(expense(1000));
      final r1 = await repo.createRefund(RefundDraft(
          originalId: id, accountId: pCash, amount: const Money(800), occurredAt: testNow));
      final receipt = await repo.delete(r1);
      await repo.createRefund(RefundDraft(
          originalId: id, accountId: pCash, amount: const Money(500), occurredAt: testNow));
      await expectLater(repo.restore(receipt), throwsCode(TxnError.refundExceedsOriginal));
    });
  });

  group('delete (rule 9, D7)', () {
    test('soft delete keeps the row, updates balances; undo restores', () async {
      final id = await repo.createEntry(expense(1000));
      final receipt = await repo.delete(id);
      expect(await balance(pCash), 0);
      expect((await db.transactionsDao.findById(id))!.deletedAt, isNotNull);
      expect((await history([personal])).items, isEmpty);
      await expectLater(repo.delete(id), throwsCode(TxnError.entryNotFound));
      await repo.restore(receipt);
      expect(await balance(pCash), -1000);
    });
  });

  group('history', () {
    test('newest first, grouped by day, with exact day totals', () async {
      await repo.createEntry(expense(35000, at: DateTime(2026, 11, 21, 9)));
      await repo.createEntry(expense(8000, at: DateTime(2026, 11, 21, 18)));
      await repo.createEntry(expense(50000, at: DateTime(2026, 11, 20, 12)));
      final sections = groupByDay((await history([personal])).items);
      expect(sections.map((s) => s.date), [LocalDate(2026, 11, 21), LocalDate(2026, 11, 20)]);
      expect(sections.first.items.first.entry.amount, const Money(8000));
      expect(sections.first.totals.expense, const Money(43000));
      expect(sections.last.totals.expense, const Money(50000));
    });

    test('pagination loads complete days only', () async {
      for (var i = 0; i < 3; i++) {
        await repo.createEntry(expense(100, at: DateTime(2026, 11, 21, 8 + i)));
      }
      for (var i = 0; i < 3; i++) {
        await repo.createEntry(expense(100, at: DateTime(2026, 11, 20, 8 + i)));
      }
      final page1 = await history([personal], const HistoryFilter(), 2);
      expect(page1.items, hasLength(3), reason: 'limit 2, but the day has 3 rows');
      expect(page1.hasMore, isTrue);
      final page2 = await history([personal], const HistoryFilter(), 4);
      expect(page2.items, hasLength(6));
      expect(page2.hasMore, isFalse);
    });

    test('Personal and Family histories never mix (rule 5)', () async {
      await repo.createEntry(expense(100));
      await repo.createEntry(expense(200, ws: family, acc: fCash));
      expect((await history([personal])).items.single.entry.amount, const Money(100));
      expect((await history([family])).items.single.entry.amount, const Money(200));
      expect((await history(both)).items, hasLength(2));
      expect((await history(const [])).items, isEmpty);
    });

    test('filters: type, category, subcategory, date range', () async {
      await repo.createEntry(expense(100, cat: grocery, sub: fish, at: DateTime(2026, 11, 1)));
      await repo.createEntry(expense(200, at: DateTime(2026, 11, 15)));
      await repo.createEntry(EntryDraft(type: EntryType.income, workspaceId: personal,
          accountId: pCash, amount: const Money(300), categoryId: salary, occurredAt: testNow));

      Future<List<int>> amounts(HistoryFilter f) async =>
          (await history([personal], f)).items.map((i) => i.entry.amount.paisa).toList();

      expect(await amounts(const HistoryFilter(types: {HistoryTypeFilter.income})), [300]);
      expect(await amounts(const HistoryFilter(types: {HistoryTypeFilter.expense})), [200, 100]);
      expect(await amounts(HistoryFilter(categoryId: grocery)), [100]);
      expect(await amounts(HistoryFilter(subcategoryId: fish)), [100]);
      expect(await amounts(HistoryFilter(range: DateRange(LocalDate(2026, 11, 10), LocalDate(2026, 11, 20)))), [200]);
    });

    test('search matches description and Bangla/English category names', () async {
      await repo.createEntry(expense(100, cat: grocery, sub: fish));
      await repo.createEntry(expense(200, desc: 'Office bus 100% fare'));
      Future<List<int>> amounts(String q) async =>
          (await history([personal], HistoryFilter(search: q))).items.map((i) => i.entry.amount.paisa).toList();
      expect(await amounts('মাছ'), [100]);
      expect(await amounts('fish'), [100]);
      expect(await amounts('OFFICE'), [200]);
      expect(await amounts('100%'), [200]);
      expect(await amounts('_'), isEmpty, reason: 'LIKE wildcards are escaped');
    });

    test('history stream updates live after writes', () async {
      final stream = repo.watchHistory(HistoryQuery(workspaceIds: [personal]))
          .map((p) => p.items.length);
      final expectation = expectLater(stream, emitsInOrder([0, 1]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await repo.createEntry(expense(100));
      await expectation;
    });
  });

  group('recent templates (§8.2)', () {
    test('distinct combinations, newest first, archived references skipped', () async {
      await repo.createEntry(expense(4000, desc: 'Office bus', at: DateTime(2026, 11, 19)));
      await repo.createEntry(expense(4500, desc: 'Office bus', at: DateTime(2026, 11, 20)));
      await repo.createEntry(expense(35000, cat: grocery, sub: fish, at: DateTime(2026, 11, 21)));
      var recent = await repo.watchRecentTemplates([personal]).first;
      expect(recent.map((r) => r.amount.paisa), [35000, 4500]);
      expect(recent.last.description, 'Office bus');

      await (db.update(db.categories)..where((c) => c.id.equals(fish)))
          .write(const CategoriesCompanion(isActive: Value(false)));
      recent = await repo.watchRecentTemplates([personal]).first;
      expect(recent.map((r) => r.amount.paisa), [4500]);
    });
  });
}
