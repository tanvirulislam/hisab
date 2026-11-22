import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/errors/app_exception.dart';
import 'package:hisab/core/services/clock.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/recurring/data/drift_recurring_repository.dart';
import 'package:hisab/features/recurring/domain/recurrence.dart';
import 'package:hisab/features/recurring/domain/recurring_rule.dart';
import 'package:hisab/features/transactions/data/drift_transaction_repository.dart';
import 'package:hisab/features/transactions/domain/transaction_rules.dart';

import '../../helpers/test_db.dart';

Matcher throwsCode(String code) =>
    throwsA(isA<ValidationException>().having((e) => e.code, 'code', code));

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late DriftRecurringRepository repo;
  late String personal, pCash, bkash, rent, salary, fish;
  final today = LocalDate(2026, 11, 21);

  Future<List<TransactionRow>> generated() =>
      (db.select(db.transactions)..where((t) => t.deletedAt.isNull())).get();

  Future<int> executions() async => (await db.select(db.recurringExecutions).get()).length;

  RecurringDraft rentDraft({
    Frequency frequency = Frequency.monthly,
    int interval = 1,
    LocalDate? start,
    LocalDate? end,
    int taka = 15000,
  }) => RecurringDraft(
    type: RecurringType.expense,
    workspaceId: personal,
    accountId: bkash,
    categoryId: rent,
    amount: Money.fromTaka(taka),
    description: 'House rent',
    frequency: frequency,
    interval: interval,
    startDate: start ?? today,
    endDate: end,
  );

  Future<RecurringRule> rule(String id) async => (await repo.watchRule(id).first)!;

  void moveTo(LocalDate d) => clock.value = DateTime(d.year, d.month, d.day, 10);

  setUp(() async {
    clock = FixedClock(testNow);
    db = await openTestDb(clock: clock);
    repo = DriftRecurringRepository(db, DriftTransactionRepository(db));
    personal = (await workspaceOfType(db, 'personal')).id;
    pCash = (await firstAccountOf(db, personal)).id;
    bkash = await addAccount(db, personal);
    rent = (await categoryByKey(db, 'rent_bills')).id;
    salary = (await categoryByKey(db, 'income.salary')).id;
    fish = (await categoryByKey(db, 'grocery.fish')).id;
  });

  tearDown(() => db.close());

  test('generates the due occurrence with source and rule link', () async {
    final id = await repo.create(rentDraft());
    final result = await repo.generateDue(today);
    expect(result.created, 1);
    final rows = await generated();
    expect(rows, hasLength(1));
    expect(rows.single.source, 'recurring');
    expect(rows.single.recurringRuleId, id);
    expect(rows.single.localDate, 20261121);
    expect(rows.single.amountPaisa, 1500000);
    expect(rows.single.workspaceId, personal);
    expect((await rule(id)).nextDueDate, LocalDate(2026, 12, 21));
  });

  test('running again — or twice at once — never duplicates (D11, §14)', () async {
    await repo.create(rentDraft());
    await repo.generateDue(today);
    expect((await repo.generateDue(today)).created, 0);
    await Future.wait([repo.generateDue(today), repo.generateDue(today)]);
    expect(await generated(), hasLength(1));
    expect(await executions(), 1);
  });

  test('the unique index rejects a second execution for the same date', () async {
    final id = await repo.create(rentDraft());
    await repo.generateDue(today);
    expect(
      () => db.recurringDao.insertExecution(RecurringExecutionsCompanion.insert(
          id: 'x', ruleId: id, occurrenceDate: 20261121, executedAt: 0)),
      throwsA(anything),
    );
  });

  test('catches up every missed occurrence after a long absence', () async {
    final id = await repo.create(rentDraft());
    final later = LocalDate(2027, 2, 25);
    moveTo(later);
    expect((await repo.generateDue(later)).created, 4); // Nov, Dec, Jan, Feb
    expect((await generated()).map((r) => r.localDate), [20261121, 20261221, 20270121, 20270221]);
    expect((await rule(id)).nextDueDate, LocalDate(2027, 3, 21));
  });

  test('a start date in the future waits until it is due', () async {
    await repo.create(rentDraft(start: today.addDays(5)));
    expect((await repo.generateDue(today)).created, 0);
    expect((await repo.generateDue(today.addDays(5))).created, 1);
  });

  test('a start date in the past is rejected (no silent back-fill)', () {
    expect(repo.create(rentDraft(start: today.addDays(-1))), throwsCode(RecurringError.startInPast));
  });

  test('template validation matches transactions', () async {
    // Income category on an expense.
    expect(repo.create(rentDraft().copyWith(categoryId: salary)), throwsCode(TxnError.categoryTypeMismatch));
    // Subcategory as the category.
    expect(repo.create(rentDraft().copyWith(categoryId: fish)), throwsCode(TxnError.categoryNotTopLevel));
    expect(repo.create(rentDraft(interval: 0)), throwsCode(RecurringError.intervalInvalid));
    expect(repo.create(rentDraft(start: today.addDays(3), end: today.addDays(2))),
        throwsCode(RecurringError.endBeforeStart));
    expect(await repo.watchRules([personal]).first, isEmpty);
  });

  test('paused rules skip occurrences; resuming does not back-fill', () async {
    final id = await repo.create(rentDraft(frequency: Frequency.daily));
    await repo.generateDue(today);
    await repo.setPaused(id, true);
    moveTo(today.addDays(3));
    expect((await repo.generateDue(today.addDays(3))).created, 0);
    await repo.setPaused(id, false);
    expect((await rule(id)).nextDueDate, today.addDays(3));
    await repo.generateDue(today.addDays(3));
    expect((await generated()).map((r) => r.localDate), [20261121, 20261124]);
  });

  test('a rule whose account was deactivated is paused, nothing is written', () async {
    final id = await repo.create(rentDraft());
    await (db.update(db.accounts)..where((a) => a.id.equals(bkash)))
        .write(const AccountsCompanion(isActive: Value(false)));
    final result = await repo.generateDue(today);
    expect(result.created, 0);
    expect(result.pausedRuleIds, [id]);
    expect((await rule(id)).isPaused, isTrue);
    expect(await generated(), isEmpty);
    expect(await executions(), 0);
    // Resuming re-validates and refuses while the account is inactive.
    expect(repo.setPaused(id, false), throwsCode(TxnError.accountInactive));
  });

  test('an end date stops generation and marks the rule ended', () async {
    final id = await repo.create(rentDraft(end: LocalDate(2026, 12, 31)));
    final later = LocalDate(2027, 3, 1);
    moveTo(later);
    expect((await repo.generateDue(later)).created, 2);
    expect((await rule(id)).hasEnded, isTrue);
    expect((await repo.generateDue(later)).created, 0);
  });

  test('editing changes future occurrences only', () async {
    final id = await repo.create(rentDraft());
    await repo.generateDue(today);
    await repo.update(id, rentDraft(taka: 16000));
    final r = await rule(id);
    expect(r.amount, Money.fromTaka(16000));
    expect(r.nextDueDate, LocalDate(2026, 12, 21));
    expect((await generated()).single.amountPaisa, 1500000);
    moveTo(LocalDate(2026, 12, 21));
    await repo.generateDue(LocalDate(2026, 12, 21));
    expect((await generated()).map((t) => t.amountPaisa), [1500000, 1600000]);
  });

  test('moving the schedule never re-creates an occurrence already recorded', () async {
    final id = await repo.create(rentDraft(frequency: Frequency.daily));
    await repo.generateDue(today);
    // Same start (today), now weekly: today is recorded, so next is +7.
    await repo.update(id, rentDraft(frequency: Frequency.weekly));
    expect((await rule(id)).nextDueDate, today.addDays(7));
  });

  test('a recurring transfer writes both legs and no income or expense', () async {
    await repo.create(RecurringDraft(
      type: RecurringType.transfer,
      workspaceId: personal,
      accountId: pCash,
      counterAccountId: bkash,
      amount: Money.fromTaka(5000),
      frequency: Frequency.monthly,
      startDate: today,
    ));
    await repo.generateDue(today);
    final rows = await generated();
    expect(rows.map((r) => r.type).toSet(), {'transfer_out', 'transfer_in'});
    expect(rows.every((r) => r.source == 'recurring'), isTrue);
    final totals = await db.reportsDao.watchTotals([personal], 20261101, 20261130).first;
    expect((totals.income, totals.expense), (0, 0));
    expect(await executions(), 1);
  });

  test('deleting a rule keeps the transactions it generated', () async {
    final id = await repo.create(rentDraft());
    await repo.generateDue(today);
    await repo.delete(id);
    expect(await repo.watchRules([personal]).first, isEmpty);
    expect(await generated(), hasLength(1));
    moveTo(LocalDate(2026, 12, 21));
    expect((await repo.generateDue(LocalDate(2026, 12, 21))).created, 0);
  });

  test('rules are listed with their category and account', () async {
    await repo.create(rentDraft());
    final items = await repo.watchRules([personal]).first;
    expect(items.single.category!.systemKey, 'rent_bills');
    expect(items.single.account.id, bkash);
  });
}
