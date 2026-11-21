import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/errors/app_exception.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/accounts/data/drift_account_repository.dart';
import 'package:hisab/features/accounts/domain/account.dart';
import 'package:hisab/features/accounts/domain/account_repository.dart';
import 'package:hisab/features/transactions/data/drift_transaction_repository.dart';
import 'package:hisab/features/transactions/domain/drafts.dart';
import 'package:hisab/features/transactions/domain/ledger_entry.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late DriftAccountRepository repo;
  late String personal, family;

  setUp(() async {
    db = await openTestDb();
    repo = DriftAccountRepository(db);
    personal = (await workspaceOfType(db, 'personal')).id;
    family = (await workspaceOfType(db, 'family')).id;
  });
  tearDown(() => db.close());

  test('creates an account whose balance starts at the opening balance', () async {
    final id = await repo.createAccount(AccountDraft(
        workspaceId: personal, name: ' bKash ', type: AccountType.bkash,
        openingBalance: Money.fromTaka(2500)));
    final list = await repo.watchAccountBalances([personal]).first;
    final acc = list.singleWhere((a) => a.account.id == id);
    expect(acc.account.name, 'bKash');
    expect(acc.balance, Money.fromTaka(2500));
  });

  test('changing the opening balance changes the derived balance (D6)', () async {
    final cash = await firstAccountOf(db, personal);
    final food = await categoryByKey(db, 'food');
    await DriftTransactionRepository(db).createEntry(EntryDraft(
        type: EntryType.expense, workspaceId: personal, accountId: cash.id,
        amount: const Money(15000), categoryId: food.id, occurredAt: testNow));
    await repo.updateAccount(cash.id, name: 'Cash', type: AccountType.cash,
        openingBalance: Money.fromTaka(1000));
    final acc = (await repo.watchAccountBalances([personal]).first).single;
    expect(acc.balance, const Money(100000 - 15000));
  });

  test('names are unique per workspace, not globally', () async {
    await expectLater(
        repo.createAccount(AccountDraft(workspaceId: personal, name: 'cash', type: AccountType.cash)),
        throwsA(isA<ValidationException>().having((e) => e.code, 'code', AccountError.nameDuplicate)));
    await repo.createAccount(AccountDraft(workspaceId: family, name: 'bKash', type: AccountType.bkash));
    await repo.createAccount(AccountDraft(workspaceId: personal, name: 'bKash', type: AccountType.bkash));
  });

  test('used accounts cannot be deleted, only deactivated', () async {
    final cash = await firstAccountOf(db, personal);
    final food = await categoryByKey(db, 'food');
    await DriftTransactionRepository(db).createEntry(EntryDraft(
        type: EntryType.expense, workspaceId: personal, accountId: cash.id,
        amount: const Money(100), categoryId: food.id, occurredAt: testNow));
    await expectLater(repo.deleteAccount(cash.id),
        throwsA(isA<ConflictException>().having((e) => e.code, 'code', AccountError.inUse)));
    await repo.setActive(cash.id, active: false);
    expect(await repo.watchAccountBalances([personal], activeOnly: true).first, isEmpty);
    expect((await repo.watchAccountBalances([personal]).first).single.balance, const Money(-100));
  });

  test('unused accounts can be deleted', () async {
    final id = await repo.createAccount(
        AccountDraft(workspaceId: personal, name: 'Nagad', type: AccountType.nagad));
    await repo.deleteAccount(id);
    expect((await repo.watchAccountBalances([personal]).first).map((a) => a.account.id),
        isNot(contains(id)));
  });
}
