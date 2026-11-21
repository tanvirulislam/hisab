import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../accounts/presentation/account_providers.dart';
import '../../settings/presentation/app_formats.dart';
import '../domain/drafts.dart';
import '../domain/ledger_entry.dart';
import 'transaction_providers.dart';
import 'widgets/entry_pickers.dart';

/// Create or edit a refund of [originalId] (D5).
Future<void> showRefundSheet(
  BuildContext context, {
  required String originalId,
  HistoryItem? refund,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _RefundSheet(originalId: originalId, refund: refund),
);

class _RefundSheet extends ConsumerStatefulWidget {
  const _RefundSheet({required this.originalId, this.refund});

  final String originalId;
  final HistoryItem? refund;

  @override
  ConsumerState<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends ConsumerState<_RefundSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _accountId;
  late LocalDate _date;
  late TimeOfDay _time;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    final r = widget.refund?.entry;
    final now = ref.read(clockProvider).now();
    _date = r?.date ?? LocalDate.fromDateTime(now);
    _time = TimeOfDay.fromDateTime(r?.occurredAt ?? now);
    if (r != null) {
      _accountId = r.accountId;
      _note.text = r.description ?? '';
      _amount.text = r.amount.paisaPart == 0
          ? '${r.amount.taka}'
          : '${r.amount.taka}.${r.amount.paisaPart.toString().padLeft(2, '0')}';
      _initialised = true;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(Money max) async {
    final l = context.l10n;
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive || _accountId == null) {
      showSnack(context, l.errAmountInvalid);
      return;
    }
    final ok = await ref.read(addTransactionProvider.notifier).saveRefund(
          RefundDraft(
            originalId: widget.originalId,
            accountId: _accountId!,
            amount: amount,
            description: _note.text,
            occurredAt: DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute),
          ),
          editId: widget.refund?.entry.id,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSnack(context, l.savedMessage);
    } else {
      final err = ref.read(addTransactionProvider).error;
      if (err != null) showSnack(context, errorMessage(l, err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final original = ref.watch(transactionItemProvider(widget.originalId)).value;
    final refunds = ref.watch(refundsOfProvider(widget.originalId)).value;
    if (original == null || refunds == null) {
      return const SizedBox(height: 200, child: LoadingState());
    }
    final others = refunds.where((r) => r.entry.id != widget.refund?.entry.id);
    final max = original.entry.amount - Money.sum(others.map((r) => r.entry.amount));
    final accounts = ref.watch(workspaceAccountsProvider(original.entry.workspaceId)).value;

    if (!_initialised && accounts != null) {
      _initialised = true;
      _amount.text = max.paisaPart == 0
          ? '${max.taka}'
          : '${max.taka}.${max.paisaPart.toString().padLeft(2, '0')}';
      final match = accounts.where((a) => a.account.id == original.entry.accountId);
      _accountId = match.isNotEmpty
          ? match.first.account.id
          : accounts.isEmpty
              ? null
              : accounts.first.account.id;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.refundAction, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            AmountField(
              controller: _amount,
              large: false,
              label: '${l.fieldAmount} · ${l.refundMax(f.money.format(max))}',
            ),
            FormSectionLabel(l.fieldAccount),
            if (accounts == null)
              const LoadingState()
            else if (accounts.isEmpty)
              Text(l.noActiveAccounts)
            else
              AccountChips(
                accounts: [for (final a in accounts) a.account],
                selectedId: _accountId,
                onSelected: (id) => setState(() => _accountId = id),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: l.fieldNote,
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            DateTimeChips(
              date: _date,
              time: _time,
              onDate: (d) => setState(() => _date = d),
              onTime: (t) => setState(() => _time = t),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: ref.watch(addTransactionProvider).isLoading ? null : () => _save(max),
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }
}
