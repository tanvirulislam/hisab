import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../settings/presentation/app_formats.dart';
import '../domain/recurrence.dart';
import '../domain/recurring_rule.dart';
import 'recurring_providers.dart';

/// "Every month", "Every 2 weeks".
String scheduleLabel(AppLocalizations l, AppFormats f, Frequency freq, int interval) {
  final n = f.integer(interval);
  return switch (freq) {
    Frequency.daily => interval == 1 ? l.everyDay : l.everyNDays(n),
    Frequency.weekly => interval == 1 ? l.everyWeek : l.everyNWeeks(n),
    Frequency.monthly => interval == 1 ? l.everyMonth : l.everyNMonths(n),
    Frequency.yearly => interval == 1 ? l.everyYear : l.everyNYears(n),
  };
}

/// Display name of a rule: its note, else its (sub)category, else "Transfer".
String ruleTitle(AppLocalizations l, String lang, RecurringRuleItem item) =>
    item.rule.description ?? (item.subcategory ?? item.category)?.displayName(lang) ?? l.entryTransfer;

/// Recurring transactions (§14): schedule, next date, pause/resume.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.moreRecurring),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.recurringEdit()),
        icon: const Icon(Icons.add),
        label: Text(l.recurringAdd),
      ),
      body: AsyncValueView(
        value: ref.watch(recurringRulesProvider),
        onRetry: () => ref.invalidate(recurringRulesProvider),
        data: (items) => items.isEmpty
            ? EmptyState(icon: Icons.event_repeat, title: l.recurringEmptyTitle, message: l.recurringEmptyMessage)
            : ListView.separated(
                padding: const EdgeInsets.only(top: 8, bottom: 96),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) => _RuleTile(item: items[i]),
              ),
      ),
    );
  }
}

enum _RuleAction { pause, resume, delete }

class _RuleTile extends ConsumerWidget {
  const _RuleTile({required this.item});

  final RecurringRuleItem item;

  Future<void> _act(BuildContext context, WidgetRef ref, _RuleAction a) async {
    final l = context.l10n;
    final c = ref.read(recurringControllerProvider.notifier);
    final bool ok;
    switch (a) {
      case _RuleAction.pause:
        ok = await c.setPaused(item.rule.id, true);
      case _RuleAction.resume:
        ok = await c.setPaused(item.rule.id, false);
      case _RuleAction.delete:
        if (!await confirmDestructive(context, title: l.recurringDeleteConfirm, message: l.recurringDeleteNote)) {
          return;
        }
        ok = await c.delete(item.rule.id);
    }
    if (!context.mounted) return;
    if (!ok) {
      final err = ref.read(recurringControllerProvider).error;
      showSnack(context, err == null ? l.errorMessage : errorMessage(l, err),
          kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final colors = context.financeColors;
    final lang = Localizations.localeOf(context).languageCode;
    final r = item.rule;
    final cat = item.subcategory ?? item.category;
    final (color, sign) = switch (r.type) {
      RecurringType.expense => (colors.expense, -r.amount),
      RecurringType.income => (colors.income, r.amount),
      RecurringType.transfer => (colors.transfer, r.amount),
    };
    final state = r.hasEnded
        ? l.recurringEnded
        : r.isPaused
            ? l.recurringPaused
            : l.recurringNext(f.date(r.nextDueDate));
    final parts = [
      scheduleLabel(l, f, r.frequency, r.interval),
      state,
    ];
    return ListTile(
      onTap: () => context.push(Routes.recurringEdit(id: r.id)),
      leading: Opacity(
        opacity: r.isPaused || r.hasEnded ? 0.5 : 1,
        child: CategoryAvatar(
          iconKey: cat?.iconKey ?? 'swap_horiz',
          color: cat == null ? colors.transfer : Color(item.category!.color),
        ),
      ),
      title: Text(ruleTitle(l, lang, item), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        r.type == RecurringType.transfer
            ? '${item.account.name} → ${item.counterAccount?.name ?? ''}\n${parts.join(' · ')}'
            : parts.join(' · '),
      ),
      isThreeLine: r.type == RecurringType.transfer,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(f.money.format(sign, signed: r.type == RecurringType.income),
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          PopupMenuButton<_RuleAction>(
            onSelected: (a) => _act(context, ref, a),
            itemBuilder: (_) => [
              if (!r.hasEnded)
                r.isPaused
                    ? PopupMenuItem(value: _RuleAction.resume, child: Text(l.recurringResume))
                    : PopupMenuItem(value: _RuleAction.pause, child: Text(l.recurringPause)),
              PopupMenuItem(value: _RuleAction.delete, child: Text(l.delete)),
            ],
          ),
        ],
      ),
    );
  }
}
