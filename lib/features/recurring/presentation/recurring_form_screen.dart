import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../accounts/presentation/account_providers.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../../settings/presentation/app_formats.dart';
import '../../transactions/domain/ledger_entry.dart';
import '../../transactions/presentation/transaction_providers.dart';
import '../../transactions/presentation/widgets/entry_pickers.dart';
import '../../workspaces/domain/workspace.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../domain/recurrence.dart';
import '../domain/recurring_rule.dart';
import 'recurring_providers.dart';
import 'recurring_screen.dart';

/// Create or edit a recurring rule (§14). Opened with [ruleId] to edit, or
/// [fromTransactionId] to start from an existing transaction.
class RecurringFormScreen extends ConsumerStatefulWidget {
  const RecurringFormScreen({super.key, this.ruleId, this.fromTransactionId});

  final String? ruleId;
  final String? fromTransactionId;

  @override
  ConsumerState<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends ConsumerState<RecurringFormScreen> {
  static const int _maxInterval = 99;

  final _amount = TextEditingController();
  final _note = TextEditingController();
  RecurringType _type = RecurringType.expense;
  String? _workspaceId;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  String? _subcategoryId;
  Frequency _frequency = Frequency.monthly;
  int _interval = 1;
  late LocalDate _today;
  late LocalDate _start;
  LocalDate? _end;

  /// The rule's original start, which may be in the past and is kept as is
  /// unless the user changes it.
  LocalDate? _savedStart;

  /// A start derived from a transaction follows frequency changes until the
  /// user picks a date.
  LocalDate? _anchor;
  bool _loading = false;
  bool _showErrors = false;

  bool get _isEdit => widget.ruleId != null;

  @override
  void initState() {
    super.initState();
    _today = ref.read(clockProvider).today();
    _start = _today;
    if (widget.ruleId != null || widget.fromTransactionId != null) {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _amountText(Money m) =>
      m.paisaPart == 0 ? '${m.taka}' : '${m.taka}.${m.paisaPart.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    if (widget.ruleId != null) {
      final r = await ref.read(recurringRepositoryProvider).watchRule(widget.ruleId!).first;
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (r == null) return;
        _type = r.type;
        _workspaceId = r.workspaceId;
        _accountId = r.accountId;
        _toAccountId = r.counterAccountId;
        _categoryId = r.categoryId;
        _subcategoryId = r.subcategoryId;
        _amount.text = _amountText(r.amount);
        _note.text = r.description ?? '';
        _frequency = r.frequency;
        _interval = r.interval;
        _start = r.startDate;
        _savedStart = r.startDate;
        _end = r.endDate;
      });
      return;
    }
    final item = await ref.read(transactionRepositoryProvider).watchItem(widget.fromTransactionId!).first;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (item == null) return;
      final e = item.entry;
      _amount.text = _amountText(e.amount);
      _note.text = e.description ?? '';
      if (e.kind.isTransfer) {
        _type = RecurringType.transfer;
        _accountId = item.fromAccount.id;
        _toAccountId = item.toAccount.id;
      } else {
        _type = e.kind == EntryKind.income ? RecurringType.income : RecurringType.expense;
        _workspaceId = e.workspaceId;
        _accountId = e.accountId;
        _categoryId = e.categoryId;
        _subcategoryId = e.subcategoryId;
      }
      // The transaction itself is the first occurrence: start at the next one,
      // so saving does not record it a second time.
      _anchor = e.date;
      _start = _nextFromAnchor();
    });
  }

  LocalDate _nextFromAnchor() {
    final r = Recurrence(frequency: _frequency, interval: _interval, start: _anchor!);
    return r.firstOnOrAfter(_today.isAfter(_anchor!) ? _today : _anchor!.addDays(1))!;
  }

  void _setSchedule({Frequency? frequency, int? interval}) => setState(() {
    _frequency = frequency ?? _frequency;
    _interval = interval ?? _interval;
    if (_anchor != null) _start = _nextFromAnchor();
  });

  Future<void> _pickDate({required bool end}) async {
    final first = end ? _start : (_savedStart != null && _savedStart!.isBefore(_today) ? _savedStart! : _today);
    final initial = end ? (_end ?? _start) : _start;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.toDateTime(),
      firstDate: first.toDateTime(),
      lastDate: DateTime(_today.year + 10, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      final d = LocalDate.fromDateTime(picked);
      if (end) {
        _end = d;
      } else {
        _start = d;
        _anchor = null;
        if (_end != null && _end!.isBefore(d)) _end = null;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _showErrors = true);
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive || _accountId == null) return;
    if (_type == RecurringType.transfer) {
      if (_toAccountId == null || _toAccountId == _accountId) return;
    } else if (_categoryId == null || _workspaceId == null) {
      return;
    }
    final ok = await ref.read(recurringControllerProvider.notifier).save(
      RecurringDraft(
        type: _type,
        workspaceId: _workspaceId ?? '',
        accountId: _accountId!,
        counterAccountId: _type == RecurringType.transfer ? _toAccountId : null,
        categoryId: _type == RecurringType.transfer ? null : _categoryId,
        subcategoryId: _type == RecurringType.transfer ? null : _subcategoryId,
        amount: amount,
        description: _note.text,
        frequency: _frequency,
        interval: _interval,
        startDate: _start,
        endDate: _end,
      ),
      id: widget.ruleId,
    );
    if (!mounted) return;
    final l = context.l10n;
    if (ok) {
      showSnack(context, l.savedMessage);
      Navigator.of(context).pop();
    } else {
      final err = ref.read(recurringControllerProvider).error;
      showSnack(context, err == null ? l.errorMessage : errorMessage(l, err));
    }
  }

  Future<void> _delete() async {
    final l = context.l10n;
    if (!await confirmDestructive(context, title: l.recurringDeleteConfirm, message: l.recurringDeleteNote)) return;
    final ok = await ref.read(recurringControllerProvider.notifier).delete(widget.ruleId!);
    if (!mounted) return;
    showSnack(context, ok ? l.deletedMessage : l.errorMessage);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final saving = ref.watch(recurringControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(_isEdit ? l.recurringEdit : l.recurringAdd),
        actions: [
          if (_isEdit)
            IconButton(tooltip: l.delete, icon: const Icon(Icons.delete_outline), onPressed: saving ? null : _delete),
        ],
      ),
      body: _loading ? const LoadingState() : _form(context),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(l.save),
                ),
              ),
            ),
    );
  }

  Widget _form(BuildContext context) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final workspaces = ref.watch(workspacesProvider).value ?? const <Workspace>[];
    if (_type != RecurringType.transfer && _workspaceId == null && workspaces.isNotEmpty) {
      _workspaceId = ref.read(entryDefaultsProvider).defaultWorkspaceId(workspaces);
    }
    final amount = Money.tryParse(_amount.text);
    final first = Recurrence(frequency: _frequency, interval: _interval, start: _start, end: _end)
        .firstOnOrAfter(_start);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        SegmentedButton<RecurringType>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: RecurringType.expense, label: Text(l.entryExpense)),
            ButtonSegment(value: RecurringType.income, label: Text(l.entryIncome)),
            ButtonSegment(value: RecurringType.transfer, label: Text(l.entryTransfer)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() {
            if (_type == s.first) return;
            _type = s.first;
            _categoryId = null;
            _subcategoryId = null;
          }),
        ),
        const SizedBox(height: 8),
        AmountField(
          controller: _amount,
          autofocus: !_isEdit && widget.fromTransactionId == null,
          errorText: _showErrors && (amount == null || !amount.isPositive) ? l.errAmountInvalid : null,
        ),
        if (_type == RecurringType.transfer) ..._transferFields(context) else ..._entryFields(context, workspaces),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          maxLength: 500,
          decoration: InputDecoration(labelText: l.fieldNote, border: const OutlineInputBorder(), counterText: ''),
        ),
        FormSectionLabel(l.recurringRepeats),
        SegmentedButton<Frequency>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: Frequency.daily, label: Text(l.freqDaily)),
            ButtonSegment(value: Frequency.weekly, label: Text(l.freqWeekly)),
            ButtonSegment(value: Frequency.monthly, label: Text(l.freqMonthly)),
            ButtonSegment(value: Frequency.yearly, label: Text(l.freqYearly)),
          ],
          selected: {_frequency},
          onSelectionChanged: (s) => _setSchedule(frequency: s.first),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text(scheduleLabel(l, f, _frequency, _interval))),
            IconButton.outlined(
              tooltip: l.intervalLess,
              icon: const Icon(Icons.remove),
              onPressed: _interval > 1 ? () => _setSchedule(interval: _interval - 1) : null,
            ),
            SizedBox(width: 40, child: Text(f.integer(_interval), textAlign: TextAlign.center)),
            IconButton.outlined(
              tooltip: l.intervalMore,
              icon: const Icon(Icons.add),
              onPressed: _interval < _maxInterval ? () => _setSchedule(interval: _interval + 1) : null,
            ),
          ],
        ),
        FormSectionLabel(l.recurringDates),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ActionChip(
              avatar: const Icon(Icons.play_arrow, size: 18),
              label: Text(l.recurringStarts(f.dateLong(_start))),
              onPressed: () => _pickDate(end: false),
            ),
            if (_end == null)
              ActionChip(
                avatar: const Icon(Icons.event_busy, size: 18),
                label: Text(l.recurringNoEnd),
                onPressed: () => _pickDate(end: true),
              )
            else
              InputChip(
                avatar: const Icon(Icons.stop, size: 18),
                label: Text(l.recurringEnds(f.dateLong(_end!))),
                onPressed: () => _pickDate(end: true),
                onDeleted: () => setState(() => _end = null),
              ),
          ],
        ),
        // When editing, occurrences already recorded are skipped, which only
        // the repository knows; the list screen shows the real next date.
        if (!_isEdit) ...[
          const SizedBox(height: 8),
          Text(
            first == null
                ? l.recurringNoMore
                : first == _today
                    ? l.recurringFirstToday
                    : l.recurringFirstOn(f.dateLong(first)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  List<Widget> _entryFields(BuildContext context, List<Workspace> workspaces) {
    final l = context.l10n;
    final wsId = _workspaceId;
    if (wsId == null) return const [LoadingState()];
    final type = _type == RecurringType.income ? CategoryType.income : CategoryType.expense;
    final nodes = ref.watch(workspaceCategoryTreeProvider(wsId, type)).value;
    final accounts = ref.watch(workspaceAccountsProvider(wsId)).value;
    if (accounts != null && !accounts.any((a) => a.account.id == _accountId)) {
      final last = ref.read(entryDefaultsProvider).lastAccountFor(wsId);
      _accountId = accounts.where((a) => a.account.id == last).firstOrNull?.account.id ??
          accounts.firstOrNull?.account.id;
    }
    final selected = nodes?.where((n) => n.category.id == _categoryId).firstOrNull;
    return [
      FormSectionLabel(l.fieldCategory, errorText: _showErrors && _categoryId == null ? l.chooseCategory : null),
      if (nodes == null)
        const SizedBox(height: 80, child: LoadingState())
      else
        CategoryGrid(
          nodes: nodes,
          selectedId: _categoryId,
          onSelected: (id) => setState(() {
            if (_categoryId != id) _subcategoryId = null;
            _categoryId = id;
          }),
        ),
      if (selected != null && selected.children.isNotEmpty) ...[
        FormSectionLabel(l.fieldSubcategory),
        SubcategoryChips(
          children: selected.children,
          selectedId: _subcategoryId,
          onSelected: (id) => setState(() => _subcategoryId = id),
        ),
      ],
      FormSectionLabel(l.fieldAccount, errorText: _showErrors && _accountId == null ? l.chooseAccount : null),
      if (accounts == null)
        const SizedBox(height: 40, child: LoadingState())
      else if (accounts.isEmpty)
        Text(l.noActiveAccounts)
      else
        AccountChips(
          accounts: [for (final a in accounts) a.account],
          selectedId: _accountId,
          onSelected: (id) => setState(() => _accountId = id),
        ),
    ];
  }

  List<Widget> _transferFields(BuildContext context) {
    final l = context.l10n;
    final accounts = ref.watch(allActiveAccountsProvider).value;
    if (accounts == null) return const [SizedBox(height: 80, child: LoadingState())];
    final list = [for (final a in accounts) a.account];
    return [
      const SizedBox(height: 16),
      AccountDropdown(
        label: l.fieldFromAccount,
        accounts: list,
        value: _accountId,
        errorText: _showErrors && _accountId == null ? l.chooseAccount : null,
        onChanged: (v) => setState(() => _accountId = v),
      ),
      const SizedBox(height: 12),
      AccountDropdown(
        label: l.fieldToAccount,
        accounts: list,
        value: _toAccountId,
        errorText: _showErrors && _toAccountId == null
            ? l.chooseAccount
            : _showErrors && _toAccountId == _accountId
                ? l.errSameAccount
                : null,
        onChanged: (v) => setState(() => _toAccountId = v),
      ),
    ];
  }
}
