import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../accounts/presentation/account_providers.dart';
import '../../settings/presentation/app_formats.dart';
import '../domain/loan.dart';
import 'loan_entry_sheet.dart';
import 'loan_labels.dart';
import 'loan_providers.dart';

/// One person: what is open, the four actions, and the full history.
class PersonLoanScreen extends ConsumerWidget {
  const PersonLoanScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final person = ref.watch(loanPersonProvider(personId));
    final summary = ref
        .watch(loanSummariesProvider)
        .value
        ?.where((s) => s.person.id == personId)
        .firstOrNull;
    final entries = ref.watch(loanEntriesProvider(personId));
    final p = person.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(p?.name ?? ''),
        actions: [
          if (p != null)
            IconButton(
              tooltip: l.loanEditPerson,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editPerson(context, ref, p),
            ),
        ],
      ),
      body: p == null
          ? (person.isLoading ? const LoadingState() : const SizedBox.shrink())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Header(person: p, summary: summary),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in LoanKind.values)
                      FilledButton.tonalIcon(
                        icon: Icon(loanKindIcon(k)),
                        label: Text(loanKindLabel(l, k)),
                        // A repayment only makes sense while something is open.
                        onPressed: _canUse(k, summary)
                            ? () => showLoanEntrySheet(
                                  context,
                                  workspaceId: p.workspaceId,
                                  person: p,
                                  kind: k,
                                )
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                AsyncValueView(
                  value: entries,
                  onRetry: () => ref.invalidate(loanEntriesProvider(personId)),
                  data: (list) => list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(child: Text(l.loanNoEntries)),
                        )
                      : Column(
                          children: [
                            for (final e in list) _EntryTile(entry: e, workspaceId: p.workspaceId),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  bool _canUse(LoanKind k, PersonLoanSummary? s) => switch (k) {
    LoanKind.repaidToMe => s != null && s.owedToMe.isPositive,
    LoanKind.repaidByMe => s != null && s.iOwe.isPositive,
    _ => true,
  };

  Future<void> _editPerson(BuildContext context, WidgetRef ref, Person p) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _PersonSheet(person: p),
      );
}

class _Header extends ConsumerWidget {
  const _Header({required this.person, required this.summary});

  final Person person;
  final PersonLoanSummary? summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final fmt = ref.watch(appFormatsProvider).money;
    final colors = context.financeColors;
    final theme = Theme.of(context);
    final s = summary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s == null || s.isSettled)
              Text(l.loanSettled, style: theme.textTheme.titleMedium)
            else ...[
              if (s.owedToMe.isPositive)
                Text(
                  l.loanOwesYou(fmt.format(s.owedToMe)),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.income,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (s.iOwe.isPositive)
                Text(
                  l.loanYouOwe(fmt.format(s.iOwe)),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.expense,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
            if (person.phone != null) ...[
              const SizedBox(height: 4),
              Text(person.phone!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            Text(
              l.loanNotIncome,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.workspaceId});

  final LoanEntry entry;
  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final colors = context.financeColors;
    final accounts = ref.watch(accountBalanceProvider).value ?? const [];
    final accountName = accounts
        .where((a) => a.account.id == entry.accountId)
        .firstOrNull
        ?.account
        .name;
    final color = loanKindColor(colors, entry.kind);
    final parts = [
      f.date(entry.date),
      ?accountName,
      if (entry.accountId == null) l.loanOldBadge,
      ?entry.note,
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => showLoanEntrySheet(context, workspaceId: workspaceId, existing: entry),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(loanKindIcon(entry.kind), color: color, size: 20),
      ),
      title: Text(loanKindLabel(l, entry.kind)),
      subtitle: Text(parts.join(' · ')),
      trailing: Text(
        f.money.format(entry.amount),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PersonSheet extends ConsumerStatefulWidget {
  const _PersonSheet({required this.person});

  final Person person;

  @override
  ConsumerState<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends ConsumerState<_PersonSheet> {
  late final _name = TextEditingController(text: widget.person.name);
  late final _phone = TextEditingController(text: widget.person.phone ?? '');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    try {
      await ref
          .read(loanRepositoryProvider)
          .updatePerson(widget.person.id, name: _name.text, phone: _phone.text);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showSnack(context, errorMessage(l, e), kind: ToastKind.error);
    }
  }

  Future<void> _delete() async {
    final l = context.l10n;
    if (!await confirmDestructive(context, title: l.loanDeletePersonConfirm)) return;
    try {
      await ref.read(loanRepositoryProvider).deletePerson(widget.person.id);
      if (!mounted) return;
      Navigator.of(context).pop(); // sheet
      Navigator.of(context).pop(); // person screen
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
            Text(l.loanEditPerson, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.loanPersonName, border: const OutlineInputBorder()),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              maxLength: 30,
              decoration: InputDecoration(labelText: l.loanPersonPhone, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _save,
              child: Text(l.save),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: Text(l.delete),
            ),
          ],
        ),
      ),
    );
  }
}
