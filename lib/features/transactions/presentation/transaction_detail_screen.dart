import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../accounts/presentation/accounts_screen.dart';
import '../../settings/presentation/app_formats.dart';
import '../domain/ledger_entry.dart';
import 'refund_sheet.dart';
import 'transaction_providers.dart';
import 'widgets/transaction_tile.dart';

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final itemAsync = ref.watch(transactionItemProvider(id));
    final item = itemAsync.value;
    final e = item?.entry;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.detailTitle),
        actions: item == null
            ? null
            : [
                if (e!.kind == EntryKind.income || e.kind == EntryKind.expense)
                  IconButton(
                    tooltip: l.repeat,
                    icon: const Icon(Icons.replay),
                    onPressed: () => context.push(Routes.addRepeat(id)),
                  ),
                if (e.kind != EntryKind.refund)
                  IconButton(
                    tooltip: l.makeRecurring,
                    icon: const Icon(Icons.event_repeat),
                    onPressed: () => context.push(Routes.recurringEdit(fromTransaction: id)),
                  ),
                IconButton(
                  tooltip: l.edit,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => e.kind == EntryKind.refund
                      ? showRefundSheet(context, originalId: e.refundOfId!, refund: item)
                      : context.push(Routes.addEdit(id)),
                ),
                IconButton(
                  tooltip: l.delete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(context, ref, item),
                ),
              ],
      ),
      body: AsyncValueView(
        value: itemAsync,
        onRetry: () => ref.invalidate(transactionItemProvider(id)),
        data: (item) => item == null
            ? EmptyState(icon: Icons.search_off, title: l.entryMissing)
            : _DetailBody(item: item),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, HistoryItem item) async {
    final l = context.l10n;
    final e = item.entry;
    final note = e.kind.isTransfer
        ? '\n\n${l.deleteTransferNote}'
        : e.kind == EntryKind.expense &&
                (ref.read(refundsOfProvider(e.id)).value?.isNotEmpty ?? false)
            ? '\n\n${l.deleteRefundsNote}'
            : '';
    final ok = await confirmDestructive(context,
        title: l.deleteConfirmTitle, message: '${l.deleteConfirmMessage}$note');
    if (!ok || !context.mounted) return;
    final repo = ref.read(transactionRepositoryProvider);
    final toast = AppToast.of(context);
    try {
      final receipt = await repo.delete(e.id);
      if (context.mounted) Navigator.of(context).pop();
      toast.show(
        l.deletedMessage,
        kind: ToastKind.success,
        actionLabel: l.undo,
        onAction: () async {
          try {
            await repo.restore(receipt);
          } on Object catch (err) {
            toast.show(errorMessage(l, err), kind: ToastKind.error);
          }
        },
      );
    } on Object catch (err) {
      if (context.mounted) showSnack(context, errorMessage(l, err), kind: ToastKind.error);
    }
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.item});

  final HistoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final f = ref.watch(appFormatsProvider);
    final theme = Theme.of(context);
    final e = item.entry;
    final (amountText, color) = amountStyle(context, f, item);

    final kindLabel = switch (e.kind) {
      EntryKind.income => l.entryIncome,
      EntryKind.expense => l.entryExpense,
      EntryKind.refund => l.entryRefund,
      EntryKind.transferOut || EntryKind.transferIn => l.entryTransfer,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(kindLabel, style: theme.textTheme.labelLarge?.copyWith(color: color)),
        const SizedBox(height: 4),
        Text(amountText,
            style: theme.textTheme.displaySmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              if (!e.kind.isTransfer)
                _Row(icon: Icons.category_outlined, label: l.fieldCategory, value: [
                  item.category?.displayName(lang) ?? '',
                  if (item.subcategory != null) item.subcategory!.displayName(lang),
                ].join(' › ')),
              if (e.kind.isTransfer)
                _Row(icon: Icons.swap_horiz, label: l.entryTransfer, value: transferRoute(l, item))
              else
                _Row(
                  icon: Icons.account_balance_wallet_outlined,
                  label: l.fieldAccount,
                  value: '${item.account.name} (${accountTypeLabel(l, item.account.type)})',
                ),
              _Row(
                icon: Icons.event,
                label: l.fieldDate,
                value: '${f.dateLong(e.date)} · ${f.time(e.occurredAt)}',
              ),
              if (e.description != null)
                _Row(icon: Icons.notes, label: l.fieldNote, value: e.description!),
            ],
          ),
        ),
        if (e.kind == EntryKind.expense) _RefundsSection(expense: item),
        if (e.kind == EntryKind.refund) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: Text(l.refundOfTitle),
            onPressed: () => context.push(Routes.transaction(e.refundOfId!)),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label, style: Theme.of(context).textTheme.labelMedium),
    subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
  );
}

class _RefundsSection extends ConsumerWidget {
  const _RefundsSection({required this.expense});

  final HistoryItem expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final refunds = ref.watch(refundsOfProvider(expense.entry.id)).value ?? const [];
    final refunded = Money.sum(refunds.map((r) => r.entry.amount));
    final remaining = expense.entry.amount - refunded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (refunds.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
            child: Text('${l.refundsTitle} · ${l.refundedTotal(f.money.format(refunded))}',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final r in refunds)
            TransactionTile(
              item: r,
              onTap: () => showRefundSheet(context, originalId: expense.entry.id, refund: r),
            ),
        ],
        if (remaining.isPositive) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.undo),
            label: Text(l.refundAction),
            onPressed: () => showRefundSheet(context, originalId: expense.entry.id),
          ),
        ],
      ],
    );
  }
}
