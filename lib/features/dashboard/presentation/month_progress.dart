import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../reports/presentation/report_providers.dart';
import '../../settings/presentation/app_formats.dart';

/// "18 days left" at the end of the Home app bar, for the current month cycle
/// (D15).
class MonthDaysLeft extends ConsumerWidget {
  const MonthDaysLeft({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final f = ref.watch(appFormatsProvider);
    final left = ref.watch(currentMonthRangeProvider).daysLeftAfter(f.today);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 16),
      child: Text(
        context.l10n.monthDaysLeft(left, f.integer(left)),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A line under the Home app bar showing how far the month cycle has run:
/// its first day, today and its last day.
class MonthProgressBar extends ConsumerWidget {
  const MonthProgressBar({super.key});

  static const double _dot = 12;
  static const double _gap = 4;
  static const double _bottom = 8;

  /// The app bar needs the height up front, so it follows the system text size.
  static PreferredSizeWidget preferred(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall!;
    final line = MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return PreferredSize(
      preferredSize: Size.fromHeight(_dot + _gap + line.ceilToDouble() + _bottom),
      child: const MonthProgressBar(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final f = ref.watch(appFormatsProvider);
    final range = ref.watch(currentMonthRangeProvider);
    final progress = range.progressAt(f.today);
    final label = theme.textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant);

    Widget line(Color color) => Container(
      height: 6,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, _bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _dot,
            child: LayoutBuilder(
              builder: (context, box) {
                // The dot's centre runs from one end of the line to the other
                // without hanging outside it.
                final start = (box.maxWidth - _dot) * progress;
                return Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: [
                    line(scheme.outlineVariant.withValues(alpha: 0.5)),
                    SizedBox(width: start + _dot / 2, child: line(scheme.secondary)),
                    PositionedDirectional(
                      start: start,
                      child: Container(
                        width: _dot,
                        height: _dot,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primary,
                          border: Border.all(color: scheme.surface, width: 2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: _gap),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(f.dateShort(range.start), style: label, maxLines: 1),
              Text(
                context.l10n.monthTodayMarker(f.dateShort(f.today)),
                style: label.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
                maxLines: 1,
              ),
              Text(f.dateShort(range.end), style: label, maxLines: 1),
            ],
          ),
        ],
      ),
    );
  }
}
