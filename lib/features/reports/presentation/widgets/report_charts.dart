import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/bn_digits.dart';
import '../../../../core/utils/local_date.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/presentation/app_formats.dart';
import '../../domain/report_models.dart';

// Charts convert paisa to double ONLY to size bars and slices. Every
// number shown as text is formatted from the integer Money value.
double _h(Money m) => m.isPositive ? m.paisa / 100 : 0;

/// Titled card that wraps a chart or report section (§18.3 Chart Container).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.subtitle});

  final String title;

  /// Optional one-line explanation under the title.
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null)
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

/// Bar per day of net expense. Today is highlighted.
class DailyBarChart extends ConsumerWidget {
  const DailyBarChart({super.key, required this.days, this.weekdayLabels = false});

  final List<DailyAmount> days;

  /// Label bars with weekday names (weekly report) instead of day numbers.
  final bool weekdayLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(appFormatsProvider);
    final scheme = Theme.of(context).colorScheme;
    final expenseColor = context.financeColors.expense;
    final maxY = days.fold<double>(0, (m, d) => _h(d.expense) > m ? _h(d.expense) : m);
    final digits = f.banglaDigits ? BnDigits.toBangla : BnDigits.toLatin;
    final labelEvery = days.length > 10 ? 5 : 1;
    // Label the first bar, the 1st and every fifth day, but keep labels at
    // least three bars apart: a month cycle (D15) puts the 30th right next
    // to the 1st.
    final labelled = <int>{};
    for (var i = 0, last = -labelEvery; i < days.length; i++) {
      final day = days[i].date.day;
      final wanted = weekdayLabels || i == 0 || day == 1 || day % labelEvery == 0;
      if (wanted && (labelEvery == 1 || i - last >= 3)) {
        labelled.add(i);
        last = i;
      }
    }

    String label(LocalDate d) => weekdayLabels
        ? digits(DateFormat.E(f.languageCode).format(d.toDateTime()))
        : digits('${d.day}');

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY == 0 ? 1 : maxY * 1.15,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                  final d = days[i].date;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(labelled.contains(i) ? label(d) : '', style: Theme.of(context).textTheme.labelSmall),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItem: (group, _, _, _) {
                final d = days[group.x];
                return BarTooltipItem(
                  '${f.date(d.date)}\n${f.money.format(d.expense)}',
                  TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: _h(days[i].expense),
                  width: days.length > 10 ? 6 : 18,
                  borderRadius: BorderRadius.circular(3),
                  color: f.isToday(days[i].date) ? scheme.tertiary : expenseColor.withValues(alpha: 0.8),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Income vs expense per month.
class MonthlyTrendChart extends ConsumerWidget {
  const MonthlyTrendChart({super.key, required this.months});

  final List<MonthAmount> months;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(appFormatsProvider);
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final colors = context.financeColors;
    final maxY = months.fold<double>(0, (m, x) {
      final v = _h(x.income) > _h(x.expense) ? _h(x.income) : _h(x.expense);
      return v > m ? v : m;
    });
    final digits = f.banglaDigits ? BnDigits.toBangla : BnDigits.toLatin;

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: maxY == 0 ? 1 : maxY * 1.15,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= months.length) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          digits(DateFormat.MMM(f.languageCode).format(months[i].firstDay.toDateTime())),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => scheme.inverseSurface,
                  getTooltipItem: (group, _, _, rodIndex) {
                    final m = months[group.x];
                    final v = rodIndex == 0 ? m.income : m.expense;
                    return BarTooltipItem(
                      '${rodIndex == 0 ? l.legendIncome : l.legendExpense}\n${f.money.format(v)}',
                      TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < months.length; i++)
                  BarChartGroupData(x: i, barsSpace: 3, barRods: [
                    BarChartRodData(
                        toY: _h(months[i].income), width: 10, color: colors.income,
                        borderRadius: BorderRadius.circular(3)),
                    BarChartRodData(
                        toY: _h(months[i].expense), width: 10, color: colors.expense,
                        borderRadius: BorderRadius.circular(3)),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend(color: colors.income, label: l.legendIncome),
            const SizedBox(width: 16),
            _Legend(color: colors.expense, label: l.legendExpense),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

/// Donut of category shares with the total in the centre.
class CategoryDonut extends ConsumerWidget {
  const CategoryDonut({super.key, required this.slices, required this.total});

  final List<CategoryAmount> slices;
  final Money total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positive = slices.where((s) => s.amount.isPositive).toList();
    return SizedBox(
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // D20: the ring is drawn clockwise from the top when it first appears.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Motion.of(context, const Duration(milliseconds: 1100)),
            curve: Curves.easeInOutCubic,
            builder: (context, t, chart) => ClipPath(clipper: _SweepClipper(t), child: chart),
            child: PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 2,
                centerSpaceRadius: 56,
                sections: [
                  for (final s in positive)
                    PieChartSectionData(
                      value: _h(s.amount),
                      color: Color(s.category?.color ?? 0xFF9E9E9E),
                      radius: 26,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          CountUpMoney(value: total, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Shows the part of a circle swept clockwise from the top, [t] of the way round.
class _SweepClipper extends CustomClipper<Path> {
  _SweepClipper(this.t);

  final double t;

  @override
  Path getClip(Size size) {
    if (t >= 1) return Path()..addRect(Offset.zero & size);
    final c = size.center(Offset.zero);
    return Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: size.longestSide), -math.pi / 2, 2 * math.pi * t, false)
      ..close();
  }

  @override
  bool shouldReclip(_SweepClipper old) => old.t != t;
}
