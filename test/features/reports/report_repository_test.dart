import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/core/utils/month_cycle.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/categories/domain/category.dart';
import 'package:hisab/features/reports/data/drift_report_repository.dart';
import 'package:hisab/features/transactions/data/drift_transaction_repository.dart';
import 'package:hisab/features/transactions/domain/drafts.dart';
import 'package:hisab/features/transactions/domain/ledger_entry.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late DriftReportRepository reports;
  late DriftTransactionRepository txns;
  late String personal, pCash, bkash, grocery, fish, veg, food, transport, salary;
  final nov = DateRange.month(2026, 11);

  Future<String> spend(int taka, {String? ws, String? acc, String? cat, String? sub, DateTime? at}) =>
      txns.createEntry(EntryDraft(
        type: EntryType.expense,
        workspaceId: ws ?? personal,
        accountId: acc ?? pCash,
        amount: Money.fromTaka(taka),
        categoryId: cat ?? food,
        subcategoryId: sub,
        occurredAt: at ?? testNow,
      ));

  Future<void> earn(int taka, {String? ws, String? acc, DateTime? at}) => txns.createEntry(EntryDraft(
        type: EntryType.income,
        workspaceId: ws ?? personal,
        accountId: acc ?? pCash,
        amount: Money.fromTaka(taka),
        categoryId: salary,
        occurredAt: at ?? testNow,
      ));

  setUp(() async {
    db = await openTestDb();
    reports = DriftReportRepository(db);
    txns = DriftTransactionRepository(db);
    personal = (await workspaceOfType(db, 'personal')).id;
    pCash = (await firstAccountOf(db, personal)).id;
    bkash = await addAccount(db, personal);
    grocery = (await categoryByKey(db, 'grocery')).id;
    fish = (await categoryByKey(db, 'grocery.fish')).id;
    veg = (await categoryByKey(db, 'grocery.vegetables')).id;
    food = (await categoryByKey(db, 'food')).id;
    transport = (await categoryByKey(db, 'transport')).id;
    salary = (await categoryByKey(db, 'income.salary')).id;
  });
  tearDown(() => db.close());

  test('monthly totals: income, net expense, savings; transfers excluded (rules 4, 7)', () async {
    await earn(50000);
    final id = await spend(1000);
    await txns.createRefund(RefundDraft(
        originalId: id, accountId: pCash, amount: Money.fromTaka(200), occurredAt: testNow));
    await txns.createTransfer(TransferDraft(
        fromAccountId: pCash, toAccountId: bkash, amount: Money.fromTaka(5000), occurredAt: testNow));

    final p = await reports.watchTotals([personal], nov).first;
    expect(p.income, Money.fromTaka(50000));
    expect(p.expense, Money.fromTaka(800));
    expect(p.net, Money.fromTaka(49200));
    expect(p.transferOut, Money.fromTaka(5000));
    expect(p.transferIn, Money.fromTaka(5000), reason: 'a transfer in is not income');
  });

  test('uses the transaction date and local month boundaries (rules 12–13)', () async {
    await spend(100, at: DateTime(2026, 10, 31, 23, 59));
    await spend(200, at: DateTime(2026, 11, 1, 0, 0));
    await spend(300, at: DateTime(2026, 11, 30, 23, 59));
    await spend(400, at: DateTime(2026, 12, 1, 0, 0));
    final t = await reports.watchTotals([personal], nov).first;
    expect(t.expense, Money.fromTaka(500));
  });

  test('deleted transactions are ignored and totals update live (rules 8–9)', () async {
    final stream = reports.watchTotals([personal], nov).map((t) => t.expense.paisa);
    final expectation = expectLater(stream, emitsInOrder([0, 50000, 0]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final id = await spend(500);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await txns.delete(id);
    await expectation;
  });

  test('daily series is zero-filled and nets refunds', () async {
    await spend(350, at: DateTime(2026, 11, 2, 9));
    final id = await spend(80, at: DateTime(2026, 11, 2, 18));
    await txns.createRefund(RefundDraft(
        originalId: id, accountId: pCash, amount: Money.fromTaka(30), occurredAt: DateTime(2026, 11, 3)));
    await earn(1000, at: DateTime(2026, 11, 3));
    final days = await reports.watchDaily([personal], nov).first;
    expect(days, hasLength(30));
    expect(days[1].expense, Money.fromTaka(430));
    expect(days[2].expense, Money.fromTaka(-30), reason: 'refund dated on a day with no expense');
    expect(days[2].income, Money.fromTaka(1000));
    expect(days[0].expense, Money.zero);
  });

  test('monthly trend is zero-filled across months', () async {
    await spend(100, at: DateTime(2026, 9, 10));
    await earn(500, at: DateTime(2026, 11, 1));
    final months = await reports.watchMonthly([personal], LocalDate(2026, 6, 15), LocalDate(2026, 11, 21)).first;
    expect(months.map((m) => m.month), [6, 7, 8, 9, 10, 11]);
    expect(months[3].expense, Money.fromTaka(100));
    expect(months[5].income, Money.fromTaka(500));
  });

  test('monthly trend groups by month cycle across the year end (D15)', () async {
    const c = MonthCycle(20);
    await spend(999, at: DateTime(2025, 11, 19)); // October cycle: outside the range
    await spend(100, at: DateTime(2025, 12, 25)); // December cycle
    await spend(200, at: DateTime(2026, 1, 5)); // still December cycle
    await spend(400, at: DateTime(2026, 1, 20)); // January cycle
    final months = await reports
        .watchMonthly([personal], LocalDate(2025, 11, 25), LocalDate(2026, 1, 25), cycle: c)
        .first;
    expect(months.map((m) => (m.year, m.month)), [(2025, 11), (2025, 12), (2026, 1)]);
    expect(months.map((m) => m.expense), [Money.zero, Money.fromTaka(300), Money.fromTaka(400)]);
  });

  test('category breakdown: net of refunds, largest first, shares sum to 100 (§11.4)', () async {
    await spend(6000, cat: grocery, sub: fish);
    await spend(2500, cat: transport);
    final f = await spend(3500, cat: food);
    await txns.createRefund(RefundDraft(
        originalId: f, accountId: pCash, amount: Money.fromTaka(500), occurredAt: testNow));
    await earn(9999);

    final rows = await reports.watchCategoryBreakdown([personal], nov, CategoryType.expense).first;
    expect(rows.map((r) => r.category!.systemKey), ['grocery', 'food', 'transport']);
    expect(rows.map((r) => r.amount.paisa), [600000, 300000, 250000]);
    expect(rows.fold<int>(0, (s, r) => s + r.percent), 100);

    final income = await reports.watchCategoryBreakdown([personal], nov, CategoryType.income).first;
    expect(income.single.category!.systemKey, 'income.salary');
    expect(income.single.percent, 100);
  });

  test('subcategory breakdown includes spending without a subcategory', () async {
    await spend(350, cat: grocery, sub: fish);
    await spend(150, cat: grocery, sub: veg);
    await spend(100, cat: grocery);
    final rows = await reports.watchSubcategoryBreakdown([personal], nov, grocery).first;
    expect(rows.map((r) => r.amount.paisa), [35000, 15000, 10000]);
    final none = rows.last;
    expect(none.withoutSubcategory, isTrue);
    expect(none.category!.systemKey, 'grocery');
  });

  test('an empty workspace list reports nothing', () async {
    await spend(100, cat: transport);
    expect((await reports.watchTotals(const [], nov).first).isEmpty, isTrue);
  });
}
