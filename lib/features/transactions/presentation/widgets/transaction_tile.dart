import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/local_date.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/presentation/app_formats.dart';
import '../../domain/ledger_entry.dart';

/// Title for an item: category (› subcategory), "Transfer", or "Refund · …".
String itemTitle(AppLocalizations l, String lang, HistoryItem item) {
  final e = item.entry;
  if (e.kind.isTransfer) return l.transferLabel;
  final cat = item.category?.displayName(lang) ?? '';
  final name = item.subcategory == null ? cat : item.subcategory!.displayName(lang);
  return e.kind == EntryKind.refund ? l.refundOf(name) : name;
}

/// "Cash → bKash".
String transferRoute(AppLocalizations l, HistoryItem item) =>
    l.transferBetween(item.fromAccount.name, item.toAccount.name);

/// Signed amount text and color. Transfers are neutral.
(String, Color) amountStyle(BuildContext context, AppFormats f, HistoryItem item) {
  final colors = context.financeColors;
  final e = item.entry;
  return switch (e.kind) {
    EntryKind.expense => (f.money.format(-e.amount), colors.expense),
    EntryKind.income || EntryKind.refund => (f.money.format(e.amount, signed: true), colors.income),
    EntryKind.transferOut || EntryKind.transferIn => (f.money.format(e.amount), colors.transfer),
  };
}

class TransactionTile extends ConsumerWidget {
  const TransactionTile({
    super.key,
    required this.item,
    this.onTap,
  });

  final HistoryItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final f = ref.watch(appFormatsProvider);
    final e = item.entry;
    final theme = Theme.of(context);

    final Widget avatar = e.kind.isTransfer
        ? CategoryAvatar(iconKey: 'swap_horiz', color: context.financeColors.transfer)
        : CategoryAvatar(
            iconKey: item.subcategory?.iconKey ?? item.category?.iconKey ?? 'label',
            color: Color(item.category?.color ?? 0xFF546E7A),
          );

    final parts = <String>[
      if (e.kind.isTransfer) transferRoute(l, item) else item.account.name,
      if (e.description != null) e.description!,
    ];
    final (amountText, amountColor) = amountStyle(context, f, item);

    return ListTile(
      onTap: onTap,
      leading: avatar,
      title: Text(itemTitle(l, lang, item), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        amountText,
        style: theme.textTheme.titleMedium?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Header of a day in the history list: "Today · 21 November" + totals.
class DayHeader extends ConsumerWidget {
  const DayHeader({super.key, required this.date, required this.expense, required this.income});

  final LocalDate date;
  final Money expense;
  final Money income;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final theme = Theme.of(context);
    final relative = f.isToday(date) ? l.today : f.isYesterday(date) ? l.yesterday : null;
    final dateText = relative == null ? f.dateLong(date) : '$relative · ${f.date(date)}';
    final totals = [
      if (!expense.isZero) l.dayExpense(f.money.format(expense)),
      if (!income.isZero) l.dayIncome(f.money.format(income)),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(dateText,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(totals,
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
