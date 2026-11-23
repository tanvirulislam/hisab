import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../../accounts/presentation/account_providers.dart';
import '../../settings/presentation/app_formats.dart';
import '../domain/loan.dart';
import '../domain/loan_repository.dart';
import 'loan_labels.dart';
import 'loan_providers.dart';

/// Add a loan step, or edit [existing].
///
/// With [person] the entry is for that person; without it the name is typed
/// (an existing person with the same name is reused, otherwise a new one is
/// created). [kind] pre-selects the step.
Future<void> showLoanEntrySheet(
  BuildContext context, {
  required String workspaceId,
  Person? person,
  LoanKind? kind,
  LoanEntry? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _LoanEntrySheet(
    workspaceId: workspaceId,
    person: person,
    kind: kind,
    existing: existing,
  ),
);

class _LoanEntrySheet extends ConsumerStatefulWidget {
  const _LoanEntrySheet({
    required this.workspaceId,
    this.person,
    this.kind,
    this.existing,
  });

  final String workspaceId;
  final Person? person;
  final LoanKind? kind;
  final LoanEntry? existing;

  @override
  ConsumerState<_LoanEntrySheet> createState() => _LoanEntrySheetState();
}

class _LoanEntrySheetState extends ConsumerState<_LoanEntrySheet> {
  late LoanKind _kind = widget.existing?.kind ?? widget.kind ?? LoanKind.lent;
  late final _name = TextEditingController(text: widget.person?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : amountFieldText(widget.existing!.amount),
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late LocalDate _date = widget.existing?.date ?? ref.read(appFormatsProvider).today;
  late String? _accountId = widget.existing?.accountId;

  /// An old loan: no account, so no balance changes.
  late bool _old = widget.existing != null && widget.existing!.accountId == null;
  bool _saving = false;
  bool _showErrors = false;

  bool get _editing => widget.existing != null;
  bool get _hasFixedPerson => widget.person != null || _editing;
  bool get _usesAccount => !(_kind.isOrigin && _old);

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// What is still open for the fixed person, for the kind being repaid.
  Money? _openAmount() {
    final id = widget.person?.id ?? widget.existing?.personId;
    final settles = _kind.settles;
    if (id == null || settles == null) return null;
    final s = ref.watch(loanSummariesProvider).value?.where((x) => x.person.id == id).firstOrNull;
    if (s == null) return null;
    var open = settles == LoanKind.lent ? s.owedToMe : s.iOwe;
    // When editing a repayment, its own amount is part of what is open.
    final e = widget.existing;
    if (e != null && e.kind == _kind) open = open + e.amount;
    return open;
  }

  Future<void> _pickDate() async {
    final today = ref.read(appFormatsProvider).today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: today.toDateTime(),
    );
    if (picked != null) setState(() => _date = LocalDate.fromDateTime(picked));
  }

  Future<void> _save() async {
    final l = context.l10n;
    setState(() => _showErrors = true);
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive) return;
    if (!_hasFixedPerson && _name.text.trim().isEmpty) return;
    if (_usesAccount && _accountId == null) return;
    setState(() => _saving = true);
    final repo = ref.read(loanRepositoryProvider);
    final account = _usesAccount ? _accountId : null;
    final note = _note.text;
    try {
      final existing = widget.existing;
      if (existing == null) {
        await repo.addEntry(LoanEntryDraft(
          workspaceId: widget.workspaceId,
          personId: widget.person?.id,
          personName: widget.person == null ? _name.text : null,
          kind: _kind,
          amount: amount,
          date: _date,
          accountId: account,
          note: note,
        ));
      } else {
        await repo.updateEntry(existing.id, amount: amount, date: _date, accountId: account, note: note);
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showSnack(context, errorMessage(l, e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l = context.l10n;
    if (!await confirmDestructive(context, title: l.loanDeleteEntryConfirm)) return;
    try {
      await ref.read(loanRepositoryProvider).deleteEntry(widget.existing!.id);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showSnack(context, errorMessage(l, e), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final f = ref.watch(appFormatsProvider);
    final accounts = ref.watch(workspaceAccountsProvider(widget.workspaceId)).value ?? const [];
    // Keep the saved account selectable even if it was made inactive later.
    final knownIds = {for (final a in accounts) a.account.id};
    if (_usesAccount && _accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.account.id;
    }
    final accountValue = knownIds.contains(_accountId) ? _accountId : null;
    final open = _openAmount();
    final suggestions = _hasFixedPerson
        ? const <PersonLoanSummary>[]
        : [
            for (final s in ref.watch(loanSummariesProvider).value ?? const <PersonLoanSummary>[])
              if (_name.text.trim().isEmpty ||
                  s.person.name.toLowerCase().contains(_name.text.trim().toLowerCase()))
                s,
          ];
    final amountMissing = _showErrors && (Money.tryParse(_amount.text)?.isPositive != true);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_editing ? l.loanEditEntry : l.loansAdd, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_editing)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Chip(
                  avatar: Icon(loanKindIcon(_kind), size: 18),
                  label: Text(loanKindLabel(l, _kind)),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final k in LoanKind.values)
                    ChoiceChip(
                      label: Text(loanKindLabel(l, k)),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            if (_hasFixedPerson)
              Text(
                widget.person?.name ?? '',
                style: theme.textTheme.titleMedium,
              )
            else ...[
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.loanPersonName,
                  border: const OutlineInputBorder(),
                  errorText: _showErrors && _name.text.trim().isEmpty ? l.errNameInvalid : null,
                ),
              ),
              if (suggestions.isNotEmpty) ...[
                Text(l.loanPickPerson, style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in suggestions.take(8))
                      ActionChip(
                        label: Text(s.person.name),
                        onPressed: () => setState(() => _name.text = s.person.name),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
            AmountField(
              controller: _amount,
              large: false,
              label: l.fieldAmount,
              errorText: amountMissing ? l.errAmountInvalid : null,
            ),
            if (open != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: open.isPositive
                      ? () => setState(() => _amount.text = amountFieldText(open))
                      : null,
                  child: Text('${l.loanOpenAmount(f.money.format(open))} · ${l.loanFullAmount}'),
                ),
              ),
            if (_kind.isOrigin)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _old,
                onChanged: (v) => setState(() => _old = v),
                title: Text(l.loanOldToggle),
                subtitle: Text(l.loanOldToggleHint),
              ),
            if (_usesAccount) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: accountValue,
                decoration: InputDecoration(
                  labelText: l.fieldAccount,
                  border: const OutlineInputBorder(),
                  helperText: _kind.isOutflow ? l.loanEffectOut : l.loanEffectIn,
                  errorText: _showErrors && accountValue == null ? l.errLoanAccountRequired : null,
                ),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.account.id, child: Text(a.account.name)),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionChip(
                avatar: const Icon(Icons.calendar_today, size: 18),
                label: Text(f.isToday(_date) ? l.today : f.dateLong(_date)),
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 500,
              decoration: InputDecoration(labelText: l.fieldNote, border: const OutlineInputBorder()),
            ),
            Text(l.loanNotIncome, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _saving ? null : _save,
              child: Text(l.save),
            ),
            if (_editing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: Text(l.delete),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
