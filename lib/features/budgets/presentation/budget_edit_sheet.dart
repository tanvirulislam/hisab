import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/presentation/app_formats.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../transactions/presentation/widgets/entry_pickers.dart';
import '../domain/budget.dart';
import '../domain/budget_repository.dart';
import 'budget_providers.dart';

/// Create a budget for [workspaceId] in [month], or edit [existing].
/// [budgeted]: categories that already have a budget that month.
Future<void> showBudgetEditSheet(
  BuildContext context, {
  required String workspaceId,
  required LocalDate month,
  BudgetStatus? existing,
  Set<String> budgeted = const {},
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _BudgetEditSheet(workspaceId: workspaceId, month: month, existing: existing, budgeted: budgeted),
);

class _BudgetEditSheet extends ConsumerStatefulWidget {
  const _BudgetEditSheet({required this.workspaceId, required this.month, this.existing, required this.budgeted});

  final String workspaceId;
  final LocalDate month;
  final BudgetStatus? existing;
  final Set<String> budgeted;

  @override
  ConsumerState<_BudgetEditSheet> createState() => _BudgetEditSheetState();
}

class _BudgetEditSheetState extends ConsumerState<_BudgetEditSheet> {
  static const int _minThreshold = 10;

  late final _amount = TextEditingController(text: _initialAmount());
  late String? _categoryId = widget.existing?.category.id;
  late int _threshold = widget.existing?.budget.warningThreshold ??
      (ref.read(appSettingsProvider).value ?? const AppSettings()).budgetWarningDefault.clamp(_minThreshold, 100);
  bool _showErrors = false;

  String _initialAmount() {
    final m = widget.existing?.budget.amount;
    if (m == null) return '';
    return m.paisaPart == 0 ? '${m.taka}' : '${m.taka}.${m.paisaPart.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _showErrors = true);
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive || _categoryId == null) return;
    final c = ref.read(budgetControllerProvider.notifier);
    final existing = widget.existing;
    final ok = existing == null
        ? await c.create(BudgetDraft(
            workspaceId: widget.workspaceId,
            categoryId: _categoryId!,
            amount: amount,
            year: widget.month.year,
            month: widget.month.month,
            warningThreshold: _threshold,
          ))
        : await c.edit(existing.budget.id, amount, _threshold);
    if (!mounted) return;
    final l = context.l10n;
    if (ok) {
      Navigator.of(context).pop();
      showSnack(context, l.savedMessage, kind: ToastKind.success);
    } else {
      final err = ref.read(budgetControllerProvider).error;
      if (err != null) showSnack(context, errorMessage(l, err), kind: ToastKind.error);
    }
  }

  Future<void> _delete() async {
    final l = context.l10n;
    if (!await confirmDestructive(context, title: l.budgetDeleteConfirm)) return;
    final ok = await ref.read(budgetControllerProvider.notifier).delete(widget.existing!.budget.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    showSnack(context, ok ? l.deletedMessage : l.errorMessage,
        kind: ok ? ToastKind.success : ToastKind.error);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final lang = Localizations.localeOf(context).languageCode;
    final saving = ref.watch(budgetControllerProvider).isLoading;
    final amount = Money.tryParse(_amount.text);
    final existing = widget.existing;

    Widget categoryPart;
    if (existing != null) {
      categoryPart = Text(existing.category.displayName(lang), style: Theme.of(context).textTheme.titleMedium);
    } else {
      final nodes = ref.watch(workspaceCategoryTreeProvider(widget.workspaceId, CategoryType.expense)).value;
      categoryPart = nodes == null
          ? const SizedBox(height: 80, child: LoadingState())
          : CategoryGrid(
              nodes: [for (final n in nodes) if (!widget.budgeted.contains(n.category.id)) n],
              selectedId: _categoryId,
              onSelected: (id) => setState(() => _categoryId = id),
            );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(existing == null ? l.budgetAdd : l.budgetEdit, style: Theme.of(context).textTheme.titleLarge),
              FormSectionLabel(l.fieldCategory,
                  errorText: _showErrors && _categoryId == null ? l.chooseCategory : null),
              categoryPart,
              const SizedBox(height: 16),
              AmountField(
                controller: _amount,
                large: false,
                label: l.budgetMonthlyLimit,
                autofocus: existing != null,
                errorText: _showErrors && (amount == null || !amount.isPositive) ? l.errAmountInvalid : null,
                onSubmitted: (_) => _save(),
              ),
              FormSectionLabel(l.budgetWarnAt(f.integer(_threshold))),
              Slider(
                value: _threshold.toDouble(),
                min: _minThreshold.toDouble(),
                max: 100,
                divisions: (100 - _minThreshold) ~/ 5,
                label: '${f.integer(_threshold)}%',
                onChanged: (v) => setState(() => _threshold = v.round()),
              ),
              Text(l.budgetThresholdHint, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (existing != null)
                    TextButton.icon(
                      onPressed: saving ? null : _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l.delete),
                      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    ),
                  const Spacer(),
                  FilledButton(onPressed: saving ? null : _save, child: Text(l.save)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
