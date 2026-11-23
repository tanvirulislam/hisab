import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/errors/app_exception.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/accounts/data/drift_account_repository.dart';
import 'package:hisab/features/loans/data/drift_loan_repository.dart';
import 'package:hisab/features/loans/domain/loan.dart';
import 'package:hisab/features/loans/domain/loan_repository.dart';
import 'package:hisab/features/transactions/data/drift_transaction_repository.dart';
import 'package:hisab/features/transactions/domain/drafts.dart';
import 'package:hisab/features/transactions/domain/ledger_entry.dart';

import '../../helpers/test_db.dart';

Matcher throwsCode(String code) =>
    throwsA(isA<AppException>().having((e) => e.code, 'code', code));

void main() {
  late AppDatabase db;
  late DriftLoanRepository repo;
  late String ws, cash, bkash;
  final day = LocalDate(2026, 11, 21);

  setUp(() async {
    db = await openTestDb();
    repo = DriftLoanRepository(db);
    ws = (await workspaceOfType(db, 'personal')).id;
    cash = (await firstAccountOf(db, ws)).id;
    bkash = await addAccount(db, ws);
  });
  tearDown(() => db.close());

  Future<int> balance(String accountId) async {
    final rows = await db.accountsDao.watchWithBalances([ws]).first;
    return rows.singleWhere((r) => r.account.id == accountId).balancePaisa;
  }

  Future<List<PersonLoanSummary>> summaries() => repo.watchSummaries([ws]).first;

  LoanEntryDraft draft(
    LoanKind kind,
    int paisa, {
    String? name = 'Karim',
    String? personId,
    String? account,
    String? note,
  }) => LoanEntryDraft(
    workspaceId: ws,
    personId: personId,
    personName: personId == null ? name : null,
    kind: kind,
    amount: Money(paisa),
    date: day,
    accountId: account,
    note: note,
  );

  group('the owner\'s case: an old loan that was never entered, now repaid', () {
    test('old loan changes no balance; the repayment adds money; income stays untouched', () async {
      final before = await balance(cash);
      final oldLoan = await repo.addEntry(draft(LoanKind.lent, 500000));
      expect(await balance(cash), before, reason: 'old loan has no account, so no balance change');
      expect((await summaries()).single.owedToMe, const Money(500000));

      final person = (await summaries()).single.person.id;
      await repo.addEntry(draft(LoanKind.repaidToMe, 500000, personId: person, account: cash));
      expect(await balance(cash), before + 500000);

      final s = (await summaries()).single;
      expect(s.owedToMe, Money.zero);
      expect(s.isSettled, isTrue);
      expect(oldLoan, isNotEmpty);

      // Not income: reports see nothing.
      final income = await db.customSelect(
        "SELECT COUNT(*) AS n FROM transactions WHERE type = 'income'",
      ).getSingle();
      expect(income.read<int>('n'), 0);
    });
  });

  group('account balance (D16)', () {
    test('lent −, repaid to me +, borrowed +, repaid by me −; deleted entries ignored', () async {
      final base = await balance(cash);
      final p = await repo.addEntry(draft(LoanKind.lent, 100000, account: cash));
      expect(await balance(cash), base - 100000);
      final person = (await summaries()).single.person.id;
      await repo.addEntry(draft(LoanKind.repaidToMe, 30000, personId: person, account: cash));
      expect(await balance(cash), base - 70000);

      await repo.addEntry(draft(LoanKind.borrowed, 80000, name: 'Rahim', account: bkash));
      expect(await balance(bkash), 80000);
      final rahim = (await summaries()).firstWhere((s) => s.person.name == 'Rahim').person.id;
      await repo.addEntry(draft(LoanKind.repaidByMe, 20000, personId: rahim, account: bkash));
      expect(await balance(bkash), 60000);

      await repo.deleteEntry(p.isEmpty ? '' : (await db.select(db.loanEntries).get())
          .firstWhere((e) => e.kind == 'repaid_to_me').id);
      expect(await balance(cash), base - 100000);
    });

    test('loans mix with normal transactions without double counting', () async {
      final tx = DriftTransactionRepository(db);
      final food = await categoryByKey(db, 'food');
      final base = await balance(cash);
      await tx.createEntry(EntryDraft(
        type: EntryType.expense, workspaceId: ws, accountId: cash,
        amount: const Money(10000), categoryId: food.id, occurredAt: testNow));
      await repo.addEntry(draft(LoanKind.lent, 5000, account: cash));
      await repo.addEntry(draft(LoanKind.borrowed, 700, name: 'Rahim', account: cash));
      expect(await balance(cash), base - 10000 - 5000 + 700);
    });
  });

  group('per-person amounts (computed, D6)', () {
    test('owed to me and I owe are separate per person; totals add up', () async {
      await repo.addEntry(draft(LoanKind.lent, 100000));
      await repo.addEntry(draft(LoanKind.borrowed, 40000, name: 'Karim'));
      final karim = (await summaries()).single;
      expect(karim.owedToMe, const Money(100000));
      expect(karim.iOwe, const Money(40000));
      expect(karim.net, const Money(60000));
    });

    test('person is matched by name regardless of case and spaces', () async {
      await repo.addEntry(draft(LoanKind.lent, 100));
      await repo.addEntry(draft(LoanKind.lent, 200, name: '  karim '));
      final list = await summaries();
      expect(list, hasLength(1));
      expect(list.single.owedToMe, const Money(300));
    });
  });

  group('repayment rule', () {
    test('a repayment cannot exceed what is open; partial repayments are fine', () async {
      await repo.addEntry(draft(LoanKind.lent, 1000));
      final person = (await summaries()).single.person.id;
      await repo.addEntry(draft(LoanKind.repaidToMe, 400, personId: person, account: cash));
      await repo.addEntry(draft(LoanKind.repaidToMe, 600, personId: person, account: cash));
      expect(
        () => repo.addEntry(draft(LoanKind.repaidToMe, 1, personId: person, account: cash)),
        throwsCode(LoanError.exceedsOutstanding),
      );
      expect((await db.select(db.loanEntries).get()), hasLength(3), reason: 'rejected write rolled back');
    });

    test('a repayment to a stranger is rejected and does not leave a person behind', () async {
      await expectLater(
        repo.addEntry(draft(LoanKind.repaidToMe, 100, name: 'Nobody', account: cash)),
        throwsCode(LoanError.exceedsOutstanding),
      );
      expect(await db.select(db.persons).get(), isEmpty);
    });

    test('deleting the loan under a repayment is refused; deleting the repayment first works', () async {
      final lent = await repo.addEntry(draft(LoanKind.lent, 1000));
      final person = (await summaries()).single.person.id;
      final back = await repo.addEntry(draft(LoanKind.repaidToMe, 1000, personId: person, account: cash));
      await expectLater(repo.deleteEntry(lent), throwsCode(LoanError.exceedsOutstanding));
      await repo.deleteEntry(back);
      await repo.deleteEntry(lent);
      expect((await summaries()).single.owedToMe, Money.zero);
    });

    test('lowering a loan below what was repaid is refused', () async {
      final lent = await repo.addEntry(draft(LoanKind.lent, 1000));
      final person = (await summaries()).single.person.id;
      await repo.addEntry(draft(LoanKind.repaidToMe, 800, personId: person, account: cash));
      await expectLater(
        repo.updateEntry(lent, amount: const Money(500), date: day),
        throwsCode(LoanError.exceedsOutstanding),
      );
      await repo.updateEntry(lent, amount: const Money(900), date: day, note: 'ok');
      expect((await summaries()).single.owedToMe, const Money(100));
    });
  });

  group('validation', () {
    test('amount must be positive', () async {
      await expectLater(repo.addEntry(draft(LoanKind.lent, 0)), throwsCode(LoanError.amountInvalid));
      await expectLater(repo.addEntry(draft(LoanKind.lent, -5)), throwsCode(LoanError.amountInvalid));
    });

    test('a repayment needs an account; the account must exist and be active', () async {
      await repo.addEntry(draft(LoanKind.lent, 1000));
      final person = (await summaries()).single.person.id;
      await expectLater(
        repo.addEntry(draft(LoanKind.repaidToMe, 100, personId: person)),
        throwsCode(LoanError.accountRequired),
      );
      await expectLater(
        repo.addEntry(draft(LoanKind.repaidToMe, 100, personId: person, account: 'nope')),
        throwsCode(LoanError.accountNotFound),
      );
      await DriftAccountRepository(db).setActive(bkash, active: false);
      await expectLater(
        repo.addEntry(draft(LoanKind.repaidToMe, 100, personId: person, account: bkash)),
        throwsCode(LoanError.accountInactive),
      );
    });

    test('name is required for a new person; note length is limited', () async {
      await expectLater(repo.addEntry(draft(LoanKind.lent, 100, name: '  ')), throwsCode(LoanError.nameInvalid));
      await expectLater(repo.addEntry(draft(LoanKind.lent, 100, name: null)), throwsCode(LoanError.nameInvalid));
      await expectLater(
        repo.addEntry(draft(LoanKind.lent, 100, note: 'x' * 501)),
        throwsCode(LoanError.noteTooLong),
      );
    });
  });

  group('people', () {
    test('rename, duplicate name check, and delete only without entries', () async {
      await repo.addEntry(draft(LoanKind.lent, 100, name: 'Karim'));
      await repo.addEntry(draft(LoanKind.lent, 100, name: 'Rahim'));
      final list = await summaries();
      final karim = list.firstWhere((s) => s.person.name == 'Karim').person.id;
      await expectLater(repo.updatePerson(karim, name: 'rahim'), throwsCode(LoanError.nameDuplicate));
      await repo.updatePerson(karim, name: 'Karim Uddin', phone: '01700000000');
      expect((await repo.watchPerson(karim).first)!.phone, '01700000000');
      await expectLater(repo.deletePerson(karim), throwsCode(LoanError.personInUse));
    });

    test('an account used by a loan cannot be deleted', () async {
      await repo.addEntry(draft(LoanKind.lent, 100, account: bkash));
      expect(await DriftAccountRepository(db).usageCount(bkash), 1);
      await expectLater(
        DriftAccountRepository(db).deleteAccount(bkash),
        throwsA(isA<ConflictException>()),
      );
    });
  });

  test('entries stream newest first', () async {
    await repo.addEntry(draft(LoanKind.lent, 100));
    final person = (await summaries()).single.person.id;
    await repo.addEntry(LoanEntryDraft(
      workspaceId: ws, personId: person, kind: LoanKind.repaidToMe, amount: const Money(50),
      date: LocalDate(2026, 11, 22), accountId: cash));
    final entries = await repo.watchEntries(person).first;
    expect(entries.map((e) => e.kind), [LoanKind.repaidToMe, LoanKind.lent]);
  });
}
