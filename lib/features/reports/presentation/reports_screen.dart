import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../core/utils/bn_digits.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../categories/domain/category.dart';
import '../../settings/presentation/app_formats.dart';
import '../../transactions/presentation/widgets/transaction_tile.dart';
import '../../workspaces/presentation/widgets/scoped_page.dart';
import '../domain/report_math.dart';
import '../domain/report_models.dart';
import 'report_providers.dart';
import 'widgets/report_charts.dart';
import 'widgets/report_sections.dart';

/// Daily, weekly, monthly and category reports (§11) for the active scope.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  CategoryType _breakdownType = CategoryType.expense;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final sel = ref.watch(reportFilterProvider);
    final range = ref.watch(reportRangeProvider);
    final totals = ref.watch(periodTotalsProvider(range));

    return ScopedPage(
      title: l.navReports,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<ReportPeriod>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: ReportPeriod.day, label: Text(l.periodDay)),
              ButtonSegment(value: ReportPeriod.week, label: Text(l.periodWeek)),
              ButtonSegment(value: ReportPeriod.month, label: Text(l.periodMonth)),
            ],
            selected: {sel.period},
            onSelectionChanged: (s) => ref.read(reportFilterProvider.notifier).setPeriod(s.first),
          ),
          const SizedBox(height: 8),
          _PeriodNavigator(selection: sel, range: range),
          const SizedBox(height: 8),
          AsyncValueView(
            value: totals,
            onRetry: () => ref.invalidate(periodTotalsProvider(range)),
            data: (t) => t.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: EmptyState(icon: Icons.bar_chart, title: l.periodEmpty, message: l.reportsEmptyMessage),
                  )
                : _ReportBody(
                    selection: sel,
                    range: range,
                    totals: t,
                    breakdownType: _breakdownType,
                    onBreakdownType: (v) => setState(() => _breakdownType = v),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PeriodNavigator extends ConsumerWidget {
  const _PeriodNavigator({required this.selection, required this.range});

  final ReportSelection selection;
  final DateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final digits = f.banglaDigits ? BnDigits.toBangla : BnDigits.toLatin;
    final label = switch (selection.period) {
      ReportPeriod.day => f.isToday(range.start)
          ? '${l.today} · ${f.date(range.start)}'
          : f.dateLong(range.start),
      ReportPeriod.week => l.weekRange(f.date(range.start), f.date(range.end)),
      ReportPeriod.month =>
        digits(DateFormat.yMMMM(f.languageCode).format(range.start.toDateTime())),
    };
    // Reports cover past and current periods, never future ones.
    final nextRange = ReportMath.rangeFor(
        selection.period, ReportMath.shift(selection.period, selection.anchor, 1), ref.watch(weekStartProvider));
    final canGoNext = !nextRange.start.isAfter(f.today);
    final notifier = ref.read(reportFilterProvider.notifier);
    return Row(
      children: [
        IconButton(
          tooltip: l.previousPeriod,
          icon: const Icon(Icons.chevron_left),
          onPressed: () => notifier.shift(-1),
        ),
        Expanded(
          child: TextButton(
            onPressed: range.contains(f.today) ? null : () => notifier.goTo(f.today),
            child: Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
        IconButton(
          tooltip: l.nextPeriod,
          icon: const Icon(Icons.chevron_right),
          onPressed: canGoNext ? () => notifier.shift(1) : null,
        ),
      ],
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({
    required this.selection,
    required this.range,
    required this.totals,
    required this.breakdownType,
    required this.onBreakdownType,
  });

  final ReportSelection selection;
  final DateRange range;
  final PeriodTotals totals;
  final CategoryType breakdownType;
  final ValueChanged<CategoryType> onBreakdownType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final period = selection.period;
    const gap = SizedBox(height: 12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SummaryTiles(totals: totals, netLabel: period == ReportPeriod.day ? l.summaryNetShort : null),
        if (totals.hasTransfers)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.transfersInOut(f.money.format(totals.transferIn), f.money.format(totals.transferOut)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (period != ReportPeriod.day) ...[gap, _DailySection(range: range, period: period)],
        if (period == ReportPeriod.month) ...[
          gap,
          _ComparisonSection(range: range, totals: totals),
          gap,
          _TrendSection(month: range.start),
        ],
        gap,
        SectionCard(
          title: l.byCategory,
          trailing: SegmentedButton<CategoryType>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -3, vertical: -3)),
            segments: [
              ButtonSegment(value: CategoryType.expense, label: Text(l.summaryExpense)),
              ButtonSegment(value: CategoryType.income, label: Text(l.summaryIncome)),
            ],
            selected: {breakdownType},
            onSelectionChanged: (s) => onBreakdownType(s.first),
          ),
          child: CategoryBreakdown(range: range, type: breakdownType),
        ),
        if (period == ReportPeriod.day) ...[gap, _DayTransactions(date: range.start)],
      ],
    );
  }
}

class _DailySection extends ConsumerWidget {
  const _DailySection({required this.range, required this.period});

  final DateRange range;
  final ReportPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final days = ref.watch(dailySeriesProvider(range)).value;
    if (days == null) return const SizedBox(height: 200, child: LoadingState());
    final total = Money.sum(days.map((d) => d.expense));
    final avg = ReportMath.average(total, ReportMath.elapsedDays(range, f.today));
    final top = ReportMath.highestSpendingDay(days);
    return SectionCard(
      title: l.dailySpending,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DailyBarChart(days: days, weekdayLabels: period == ReportPeriod.week),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: StatTile(label: l.dailyAverage, value: f.money.format(avg))),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: l.highestDay,
                  value: top == null ? '—' : '${f.date(top.date)} · ${f.money.format(top.expense)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComparisonSection extends ConsumerWidget {
  const _ComparisonSection({required this.range, required this.totals});

  final DateRange range;
  final PeriodTotals totals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prevStart = range.start.addMonths(-1);
    final prev = ref.watch(periodTotalsProvider(DateRange.month(prevStart.year, prevStart.month))).value;
    if (prev == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ComparisonText(previous: prev.expense, current: totals.expense),
      ),
    );
  }
}

class _TrendSection extends ConsumerWidget {
  const _TrendSection({required this.month});

  final LocalDate month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final months = ref.watch(monthlyTrendProvider(month)).value;
    return SectionCard(
      title: context.l10n.trendTitle,
      child: months == null
          ? const SizedBox(height: 200, child: LoadingState())
          : MonthlyTrendChart(months: months),
    );
  }
}

class _DayTransactions extends ConsumerWidget {
  const _DayTransactions({required this.date});

  final LocalDate date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final items = ref.watch(dayTransactionsProvider(date)).value;
    return SectionCard(
      title: l.dayTransactionsTitle,
      child: items == null
          ? const SizedBox(height: 80, child: LoadingState())
          : Column(
              children: [
                for (final item in items)
                  TransactionTile(
                    item: item,
                    onTap: () => context.push(Routes.transaction(item.entry.id)),
                  ),
              ],
            ),
    );
  }
}
