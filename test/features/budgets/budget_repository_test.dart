import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/errors/app_exception.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/core/utils/month_cycle.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/budgets/data/drift_budget_repository.dart';
import 'package:hisab/features/budgets/domain/budget.dart';
import 'package:hisab/features/budgets/domain/budget_repository.dart';
import 'package:hisab/features/categories/data/drift_category_repository.dart';
import 'package:hisab/features/categories/domain/category.dart';
import 'package:hisab/features/categories/domain/category_repository.dart';

import '../../helpers/test_db.dart';

Matcher throwsCode(String code) =>
    throwsA(isA<ValidationException>().having((e) => e.code, 'code', code));

void main() {
  late AppDatabase db;
  late DriftBudgetRepository repo;
  late String personal, pCash, grocery, fish, transport, salary;

  BudgetDraft draft({String? ws, String? cat, int taka = 3000, int year = 2026, int month = 11, int threshold = 80}) =>
      BudgetDraft(
        workspaceId: ws ?? personal,
        categoryId: cat ?? grocery,
        amount: Money.fromTaka(taka),
        year: year,
        month: month,
        warningThreshold: threshold,
      );

  Future<List<BudgetStatus>> statuses(List<String> ids, [int year = 2026, int month = 11]) =>
      repo.watchStatuses(ids, year, month).first;

  setUp(() async {
    db = await openTestDb();
    repo = DriftBudgetRepository(db);
    personal = (await workspaceOfType(db, 'personal')).id;
    pCash = (await firstAccountOf(db, personal)).id;
    grocery = (await categoryByKey(db, 'grocery')).id;
    fish = (await categoryByKey(db, 'grocery.fish')).id;
    transport = (await categoryByKey(db, 'transport')).id;
    salary = (await categoryByKey(db, 'income.salary')).id;
  });

  tearDown(() => db.close());

  test('spent = expense − refunds of the category, workspace and month (§12.2, rule 10)', () async {
    await repo.create(draft());
    // Counted: Personal grocery in November, including a subcategory row.
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'expense', amountPaisa: 100000, categoryId: grocery, id: 'e1');
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'expense', amountPaisa: 50000, categoryId: grocery, localDate: 20261101);
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'refund', amountPaisa: 20000, categoryId: grocery, refundOfId: 'e1');
    // Not counted: other month, other category, deleted, transfer.
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'expense', amountPaisa: 999900, categoryId: grocery, localDate: 20261031);
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'expense', amountPaisa: 999900, categoryId: transport);
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'expense', amountPaisa: 999900, categoryId: grocery, deletedAt: 1);
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'transfer_out', amountPaisa: 999900,
        transferGroupId: 'g', counterAccountId: await addAccount(db, personal));

    final s = (await statuses([personal])).single;
    expect(s.spent, Money.fromTaka(1300));
    expect(s.remaining, Money.fromTaka(1700));
    expect(s.percent, 43);
    expect(s.level, BudgetLevel.normal);
    expect(s.workspaceType.name, 'personal');
  });

  test('status updates live as transactions change (§5.4)', () async {
    await repo.create(draft(taka: 1000));
    final stream = repo.watchStatuses([personal], 2026, 11);
    final levels = <BudgetLevel>[];
    final sub = stream.listen((l) => levels.add(l.single.level));
    await pumpEventQueue();
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'expense', amountPaisa: 80000, categoryId: grocery);
    await pumpEventQueue();
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'expense', amountPaisa: 20000, categoryId: grocery);
    await pumpEventQueue();
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'expense', amountPaisa: 1, categoryId: grocery);
    await pumpEventQueue();
    await sub.cancel();
    expect(levels, [BudgetLevel.normal, BudgetLevel.warning, BudgetLevel.reached, BudgetLevel.over]);
  });

  test('totals add up every budget of the month', () async {
    await repo.create(draft(taka: 3000));
    await repo.create(draft(cat: transport, taka: 6000));
    final all = await statuses([personal]);
    expect(BudgetTotals(all).allocated, Money.fromTaka(9000));
    expect(await statuses(const []), isEmpty);
  });

  test('one budget per category, workspace and month; deleting frees the slot', () async {
    final id = await repo.create(draft());
    expect(repo.create(draft(taka: 10)), throwsCode(BudgetError.duplicate));
    await repo.create(draft(month: 12)); // another month is fine
    await repo.delete(id);
    await repo.create(draft(taka: 2500));
    expect((await statuses([personal])).single.budget.amount, Money.fromTaka(2500));
  });

  test('validation', () async {
    expect(repo.create(draft(taka: 0)), throwsCode(BudgetError.amountInvalid));
    expect(repo.create(draft(threshold: 0)), throwsCode(BudgetError.thresholdInvalid));
    expect(repo.create(draft(threshold: 101)), throwsCode(BudgetError.thresholdInvalid));
    expect(repo.create(draft(cat: fish)), throwsCode(BudgetError.categoryInvalid)); // subcategory
    expect(repo.create(draft(cat: salary)), throwsCode(BudgetError.categoryInvalid)); // income
    // A workspace-owned category can be budgeted in its own workspace.
    final own = await DriftCategoryRepository(db).createCategory(CategoryDraft(
        type: CategoryType.expense, workspaceId: personal, name: 'Maid', iconKey: 'home', color: 0xFF000000));
    await repo.create(draft(cat: own));
  });

  test('update changes amount and threshold', () async {
    final id = await repo.create(draft());
    await insertTxn(db, workspaceId: personal, accountId: pCash, type: 'expense', amountPaisa: 150000, categoryId: grocery);
    await repo.update(id, amount: Money.fromTaka(2000), warningThreshold: 70);
    final s = (await statuses([personal])).single;
    expect(s.budget.warningThreshold, 70);
    expect(s.level, BudgetLevel.warning); // 75% ≥ 70%
    expect(repo.update(id, amount: Money.zero, warningThreshold: 70), throwsCode(BudgetError.amountInvalid));
  });

  test('copy from previous month skips existing and archived categories', () async {
    await repo.create(draft(month: 10, taka: 3000));
    await repo.create(draft(month: 10, cat: transport, taka: 2000, threshold: 90));
    await repo.create(draft(month: 11, cat: transport, taka: 2500));
    expect(await repo.copyFromPreviousMonth(personal, 2026, 11), 1);
    final nov = await statuses([personal]);
    expect(nov.map((s) => s.budget.amount).toSet(), {Money.fromTaka(3000), Money.fromTaka(2500)});

    await DriftCategoryRepository(db).setArchived(grocery, archived: true);
    expect(await repo.copyFromPreviousMonth(personal, 2026, 12), 1); // transport only
  });

  test('rollover carries budgets into a new month only once', () async {
    await repo.create(draft(month: 11));
    await repo.rolloverIfNeeded([personal], LocalDate(2026, 12, 1));
    expect(await statuses([personal], 2026, 12), hasLength(1));
    // The user deletes December's budget: rollover must not bring it back.
    await repo.delete((await statuses([personal], 2026, 12)).single.budget.id);
    await repo.rolloverIfNeeded([personal], LocalDate(2026, 12, 5));
    expect(await statuses([personal], 2026, 12), isEmpty);
  });

  test('with a month start day, spent and rollover follow the cycle (D15)', () async {
    const c = MonthCycle(20);
    await repo.create(draft(month: 10)); // October cycle: 20 Oct – 19 Nov
    Future<void> grocer(int paisa, int date) => insertTxn(db,
        workspaceId: personal, accountId: pCash, type: 'expense', amountPaisa: paisa, categoryId: grocery, localDate: date);
    await grocer(10000, 20261020);
    await grocer(20000, 20261119);
    await grocer(999900, 20261019); // September cycle
    await grocer(999900, 20261120); // November cycle
    final s = (await repo.watchStatuses([personal], 2026, 10, cycle: c).first).single;
    expect(s.spent, Money.fromTaka(300));

    // On 15 Nov the October cycle is still running: nothing to roll over yet.
    await repo.rolloverIfNeeded([personal], LocalDate(2026, 11, 15), cycle: c);
    expect(await repo.watchStatuses([personal], 2026, 11, cycle: c).first, isEmpty);
    await repo.rolloverIfNeeded([personal], LocalDate(2026, 11, 20), cycle: c);
    expect((await repo.watchStatuses([personal], 2026, 11, cycle: c).first).single.spent, Money.fromTaka(9999));
  });

  test('a category with a budget cannot be deleted, only archived (§7.2)', () async {
    await repo.create(draft(cat: transport));
    expect(await DriftCategoryRepository(db).usageCount(transport), greaterThan(0));
  });
}
