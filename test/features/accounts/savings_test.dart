import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart' show Row, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/accounts/data/drift_account_repository.dart';
import 'package:hisab/features/accounts/domain/account.dart';
import 'package:hisab/features/accounts/domain/account_repository.dart';
import 'package:hisab/features/accounts/domain/savings.dart';
import 'package:hisab/features/reports/data/drift_report_repository.dart';
import 'package:hisab/features/transactions/data/drift_transaction_repository.dart';
import 'package:hisab/features/transactions/domain/drafts.dart';
import 'package:hisab/features/transactions/domain/ledger_entry.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/test_db.dart';

AccountBalance acc(String id, AccountType type, int taka, {bool active = true}) => AccountBalance(
      account: Account(
          id: id, workspaceId: 'w', name: id, type: type,
          openingBalance: Money.zero, isActive: active, sortOrder: 0),
      balance: Money.fromTaka(taka),
    );

void main() {
  group('Savings rules (D17)', () {
    final list = [
      acc('cash', AccountType.cash, 3000),
      acc('bkash', AccountType.bkash, 8000),
      acc('old', AccountType.bank, 99999, active: false),
      acc('jomano', AccountType.savings, 5000),
    ];

    test('target is the first active savings account', () {
      expect(Savings.target(list)?.id, 'jomano');
      expect(Savings.target([acc('x', AccountType.savings, 1, active: false)]), isNull);
    });
  });

  group('left this month', () {
    Money left(int net, int moved) =>
        Savings.leftThisMonth(net: Money.fromTaka(net), moved: Money.fromTaka(moved));
    test('income − expense, less what was moved to savings', () {
      expect(left(49070, 0), Money.fromTaka(49070));
      expect(left(49070, 5000), Money.fromTaka(44070));
      expect(left(1000, 5000), Money.zero, reason: 'savings from older money do not go below zero');
    });
    test('an overspent month shows its deficit and moving money does not deepen it', () {
      expect(left(-500, 0), Money.fromTaka(-500));
      expect(left(-500, 1000), Money.fromTaka(-500));
      expect(left(0, 300), Money.zero);
    });
  });

  group('moved to savings', () {
    late AppDatabase db;
    late DriftTransactionRepository txns;
    late String ws, cash, jomano;

    setUp(() async {
      db = await openTestDb();
      txns = DriftTransactionRepository(db);
      ws = (await workspaceOfType(db, 'personal')).id;
      cash = (await firstAccountOf(db, ws)).id;
      jomano = await DriftAccountRepository(db)
          .createAccount(AccountDraft(workspaceId: ws, name: 'জমানো', type: AccountType.savings));
    });
    tearDown(() => db.close());

    final nov = DateRange(LocalDate(2026, 11, 1), LocalDate(2026, 11, 30));
    Future<Money> moved() => DriftAccountRepository(db).watchSavingsMoved([ws], nov).first;
    Future<void> move(String from, String to, int taka, DateTime at) => txns.createTransfer(TransferDraft(
        fromAccountId: from, toAccountId: to, amount: Money.fromTaka(taka), occurredAt: at));

    test('counts transfers in minus out on savings accounts, in the range only', () async {
      expect(await moved(), Money.zero);
      await move(cash, jomano, 3000, DateTime(2026, 11, 5));
      await move(cash, jomano, 500, DateTime(2026, 11, 20));
      await move(jomano, cash, 200, DateTime(2026, 11, 21));
      await move(cash, jomano, 9000, DateTime(2026, 10, 30)); // another month
      expect(await moved(), Money.fromTaka(3300));
    });

    test('a deleted transfer no longer counts', () async {
      await move(cash, jomano, 3000, DateTime(2026, 11, 5));
      final group = (await db.select(db.transactions).get()).first.transferGroupId!;
      final leg = (await txns.transferLegs(group)).first;
      await txns.delete(leg.id);
      expect(await moved(), Money.zero);
    });

    test('transfers are not income or expense: reports stay unchanged, the balance only moves', () async {
      await db.accountsDao.updateRow(cash, const AccountsCompanion(openingBalancePaisa: Value(1000000)));
      await move(cash, jomano, 3000, DateTime(2026, 11, 5));
      final totals = await DriftReportRepository(db).watchTotals([ws], nov).first;
      expect(totals.income, Money.zero);
      expect(totals.expense, Money.zero);
      expect(totals.net, Money.zero);
      final balances = await DriftAccountRepository(db).watchAccountBalances([ws]).first;
      expect(balances.singleWhere((b) => b.account.id == jomano).balance, Money.fromTaka(3000));
      expect(Money.sum(balances.map((b) => b.balance)), Money.fromTaka(10000));
    });

    test('a transfer between two savings accounts cancels out', () async {
      final second = await DriftAccountRepository(db)
          .createAccount(AccountDraft(workspaceId: ws, name: 'আরেক', type: AccountType.savings));
      await move(cash, jomano, 1000, DateTime(2026, 11, 5));
      await move(jomano, second, 400, DateTime(2026, 11, 6));
      expect(await moved(), Money.fromTaka(1000));
    });
  });

  group('Home', () {
    Future<void> seed(AppDatabase db) async {
      final ws = (await workspaceOfType(db, 'personal')).id;
      final cash = (await firstAccountOf(db, ws)).id;
      final repo = DriftTransactionRepository(db);
      await repo.createEntry(EntryDraft(
          type: EntryType.income, workspaceId: ws, accountId: cash, amount: Money.fromTaka(50000),
          categoryId: (await categoryByKey(db, 'income.salary')).id, occurredAt: DateTime(2026, 11, 1)));
      await repo.createEntry(EntryDraft(
          type: EntryType.expense, workspaceId: ws, accountId: cash, amount: Money.fromTaka(930),
          categoryId: (await categoryByKey(db, 'grocery')).id, occurredAt: testNow));
    }

    testWidgets('without a savings account Home only suggests creating one', (tester) async {
      await pumpHisab(tester, logicalSize: const Size(432, 1400), seed: seed);
      expect(find.text('টাকা জমানোর জন্য একটা সঞ্চয় অ্যাকাউন্ট বানান, অথবা আগের কোনো অ্যাকাউন্টের ধরন "সঞ্চয়" করুন।'), findsOneWidget);
      expect(find.textContaining('এর মধ্যে সঞ্চয়'), findsNothing);
    });

    testWidgets('with a savings account Home shows what was moved, with no send button',
        (tester) async {
      await pumpHisab(tester, logicalSize: const Size(432, 1400), seed: (db) async {
        await seed(db);
        final ws = (await workspaceOfType(db, 'personal')).id;
        final cash = (await firstAccountOf(db, ws)).id;
        final jomano = await DriftAccountRepository(db)
            .createAccount(AccountDraft(workspaceId: ws, name: 'জমানো', type: AccountType.savings));
        await DriftTransactionRepository(db).createTransfer(TransferDraft(
            fromAccountId: cash, toAccountId: jomano, amount: Money.fromTaka(5000), occurredAt: testNow));
      });
      expect(find.text('এই মাসে সঞ্চয়ে সরানো'), findsOneWidget);
      final movedRow =
          find.ancestor(of: find.text('এই মাসে সঞ্চয়ে সরানো'), matching: find.byType(Row)).first;
      expect(find.descendant(of: movedRow, matching: find.text('৳৫,০০০')), findsOneWidget);
      expect(find.textContaining('সঞ্চয়ে পাঠান'), findsNothing);
      // 50,000 − 930 = 49,070, less the 5,000 already moved, on the "left this month" card (D19).
      expect(find.text('এই মাসে বাকি'), findsOneWidget);
      expect(find.text('৳৪৪,০৭০'), findsOneWidget);
      expect(find.text('টাকা জমানোর জন্য একটা সঞ্চয় অ্যাকাউন্ট বানান, অথবা আগের কোনো অ্যাকাউন্টের ধরন "সঞ্চয়" করুন।'), findsNothing);
    });
  });
}
