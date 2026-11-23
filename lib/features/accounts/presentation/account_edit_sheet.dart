import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/bn_digits.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../domain/account.dart';
import '../domain/account_repository.dart';
import 'account_providers.dart';
import 'accounts_screen.dart';

/// Create an account in [workspaceId], or edit [existing].
Future<void> showAccountEditSheet(
  BuildContext context, {
  String? workspaceId,
  Account? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _AccountEditSheet(workspaceId: workspaceId, existing: existing),
);

class _AccountEditSheet extends ConsumerStatefulWidget {
  const _AccountEditSheet({this.workspaceId, this.existing});

  final String? workspaceId;
  final Account? existing;

  @override
  ConsumerState<_AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends ConsumerState<_AccountEditSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _opening = TextEditingController(text: _initialOpening());
  late AccountType _type = widget.existing?.type ?? AccountType.bkash;
  late bool _active = widget.existing?.isActive ?? true;
  bool _saving = false;

  String _initialOpening() {
    final m = widget.existing?.openingBalance;
    if (m == null || m.isZero) return '';
    final abs = m.abs();
    final text = abs.paisaPart == 0 ? '${abs.taka}' : '${abs.taka}.${abs.paisaPart.toString().padLeft(2, '0')}';
    return m.isNegative ? '-$text' : text;
  }

  /// Opening balance may be negative (an overdrawn account).
  Money? _parseOpening() {
    final raw = BnDigits.toLatin(_opening.text.trim());
    if (raw.isEmpty) return Money.zero;
    final negative = raw.startsWith('-');
    final m = Money.tryParse(negative ? raw.substring(1) : raw);
    if (m == null) return null;
    return negative ? -m : m;
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final opening = _parseOpening();
    if (opening == null) {
      showSnack(context, l.errAmountInvalid, kind: ToastKind.error);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(accountRepositoryProvider);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await repo.createAccount(AccountDraft(
          workspaceId: widget.workspaceId!,
          name: _name.text,
          type: _type,
          openingBalance: opening,
        ));
      } else {
        await repo.updateAccount(existing.id, name: _name.text, type: _type, openingBalance: opening);
        if (_active != existing.isActive) await repo.setActive(existing.id, active: _active);
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
    final repo = ref.read(accountRepositoryProvider);
    final id = widget.existing!.id;
    try {
      if (await repo.usageCount(id) > 0) {
        if (mounted) showSnack(context, l.errAccountInUse, kind: ToastKind.error);
        return;
      }
      if (!mounted || !await confirmDestructive(context, title: l.deleteAccountConfirm)) return;
      await repo.deleteAccount(id);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showSnack(context, errorMessage(l, e), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.existing == null ? l.addAccount : l.editAccount,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              maxLength: 60,
              decoration: InputDecoration(labelText: l.fieldName, border: const OutlineInputBorder()),
            ),
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              decoration: InputDecoration(labelText: l.fieldType, border: const OutlineInputBorder()),
              items: [
                for (final t in AccountType.values)
                  DropdownMenuItem(value: t, child: Text(accountTypeLabel(l, t))),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: l.fieldOpeningBalance,
                helperText: l.openingBalanceHint,
                prefixText: '৳ ',
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.existing != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: Text(l.accountActive),
                subtitle: Text(l.accountActiveHint),
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _saving ? null : _save,
              child: Text(l.save),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
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
