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
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../../settings/presentation/app_formats.dart';
import '../../workspaces/domain/workspace.dart';
import '../../workspaces/presentation/widgets/workspace_labels.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../domain/drafts.dart';
import '../domain/ledger_entry.dart';
import 'transaction_providers.dart';
import 'widgets/entry_pickers.dart';

enum EntryMode { expense, income, transfer }

/// How the entry form was opened.
class EntryFormArgs {
  const EntryFormArgs({this.mode = EntryMode.expense, this.editId, this.repeatId});

  final EntryMode mode;

  /// Entry to edit (for a transfer, either of its rows).
  final String? editId;

  /// Entry to copy into a new transaction, dated now (§8.2 Repeat).
  final String? repeatId;

  static EntryFormArgs fromQuery(Map<String, String> q) => EntryFormArgs(
    mode: EntryMode.values.firstWhere((m) => m.name == q['type'], orElse: () => EntryMode.expense),
    editId: q['edit'],
    repeatId: q['repeat'],
  );
}

/// Add / edit income, expense or transfer.
class EntryFormScreen extends ConsumerStatefulWidget {
  const EntryFormScreen({super.key, required this.args});

  final EntryFormArgs args;

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  late EntryMode _mode = widget.args.mode;
  String? _workspaceId;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  String? _subcategoryId;
  late LocalDate _date;
  late TimeOfDay _time;
  EntrySource _source = EntrySource.manual;

  String? _editEntryId;
  String? _editGroupId;
  bool _loading = false;
  Object? _loadError;
  bool _showErrors = false;

  bool get _isEdit => widget.args.editId != null;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider).now();
    _date = LocalDate.fromDateTime(now);
    _time = TimeOfDay.fromDateTime(now);
    final sourceId = widget.args.editId ?? widget.args.repeatId;
    if (sourceId != null) {
      _loading = true;
      _load(sourceId);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Plain editable text for an amount: "350" or "100.50".
  static String _amountText(Money m) => m.isZero
      ? ''
      : m.paisaPart == 0
          ? '${m.taka}'
          : '${m.taka}.${m.paisaPart.toString().padLeft(2, '0')}';

  Future<void> _load(String id) async {
    try {
      final item = await ref.read(transactionRepositoryProvider).watchItem(id).first;
      if (!mounted) return;
      if (item == null) {
        setState(() => _loadError = const _Missing());
        return;
      }
      final e = item.entry;
      setState(() {
        _amount.text = _amountText(e.amount);
        _note.text = e.description ?? '';
        if (e.kind.isTransfer) {
          _mode = EntryMode.transfer;
          _accountId = item.fromAccount.id;
          _toAccountId = item.toAccount.id;
          _editGroupId = _isEdit ? e.transferGroupId : null;
        } else {
          _mode = e.kind == EntryKind.income ? EntryMode.income : EntryMode.expense;
          _workspaceId = e.workspaceId;
          _accountId = e.accountId;
          _categoryId = e.categoryId;
          _subcategoryId = e.subcategoryId;
          _editEntryId = _isEdit ? e.id : null;
        }
        if (_isEdit) {
          _date = e.date;
          _time = TimeOfDay.fromDateTime(e.occurredAt);
          _source = e.source;
        } else {
          _source = EntrySource.repeat;
        }
        _loading = false;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _applyTemplate(RecentTemplate t) {
    setState(() {
      _mode = t.type == EntryType.income ? EntryMode.income : EntryMode.expense;
      _workspaceId = t.workspaceId;
      _accountId = t.accountId;
      _categoryId = t.category.id;
      _subcategoryId = t.subcategory?.id;
      _amount.text = _amountText(t.amount);
      _note.text = t.description ?? '';
      _source = EntrySource.repeat;
    });
  }

  DateTime get _occurredAt =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _save() async {
    setState(() => _showErrors = true);
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive || _accountId == null) return;
    final controller = ref.read(addTransactionProvider.notifier);
    final bool ok;
    if (_mode == EntryMode.transfer) {
      if (_toAccountId == null || _toAccountId == _accountId) return;
      ok = await controller.saveTransfer(
        TransferDraft(
          fromAccountId: _accountId!,
          toAccountId: _toAccountId!,
          amount: amount,
          description: _note.text,
          occurredAt: _occurredAt,
          source: _source,
        ),
        groupId: _editGroupId,
      );
    } else {
      if (_categoryId == null || _workspaceId == null) return;
      ok = await controller.saveEntry(
        EntryDraft(
          type: _mode == EntryMode.income ? EntryType.income : EntryType.expense,
          workspaceId: _workspaceId!,
          accountId: _accountId!,
          amount: amount,
          categoryId: _categoryId!,
          subcategoryId: _subcategoryId,
          description: _note.text,
          occurredAt: _occurredAt,
          source: _source,
        ),
        editId: _editEntryId,
      );
    }
    if (!mounted) return;
    final l = context.l10n;
    if (ok) {
      showSnack(context, l.savedMessage);
      Navigator.of(context).pop(true);
    } else {
      final err = ref.read(addTransactionProvider).error;
      if (err != null) showSnack(context, errorMessage(l, err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final saving = ref.watch(addTransactionProvider).isLoading;

    Widget body;
    if (_loadError != null) {
      body = _loadError is _Missing
          ? EmptyState(icon: Icons.search_off, title: l.entryMissing)
          : ErrorState(error: _loadError);
    } else if (_loading) {
      body = const LoadingState();
    } else {
      body = _buildForm(context);
    }

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(_isEdit ? l.editTitle : l.addTitle),
      ),
      body: body,
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: saving ? null : _save,
                  icon: saving
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(l.save),
                ),
              ),
            ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final l = context.l10n;
    final workspaces = ref.watch(workspacesProvider).value ?? const <Workspace>[];
    if (_mode != EntryMode.transfer && _workspaceId == null && workspaces.isNotEmpty) {
      _workspaceId = ref.read(entryDefaultsProvider).defaultWorkspaceId(
          ref.read(activeWorkspaceScopeProvider), workspaces);
    }
    final amount = Money.tryParse(_amount.text);
    final amountError = _showErrors && (amount == null || !amount.isPositive) ? l.errAmountInvalid : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        SegmentedButton<EntryMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: EntryMode.expense, label: Text(l.entryExpense), icon: const Icon(Icons.north_east)),
            ButtonSegment(value: EntryMode.income, label: Text(l.entryIncome), icon: const Icon(Icons.south_west)),
            ButtonSegment(
              value: EntryMode.transfer,
              label: Text(l.entryTransfer),
              icon: const Icon(Icons.swap_horiz),
              // A saved entry cannot become a transfer or vice versa.
              enabled: !_isEdit || _mode == EntryMode.transfer,
            ),
          ],
          selected: {_mode},
          onSelectionChanged: _isEdit && _mode == EntryMode.transfer
              ? null
              : (s) => setState(() {
                    if (_mode != s.first) {
                      _mode = s.first;
                      _categoryId = null;
                      _subcategoryId = null;
                    }
                  }),
        ),
        const SizedBox(height: 8),
        AmountField(
          controller: _amount,
          autofocus: !_isEdit && widget.args.repeatId == null,
          errorText: amountError,
          onSubmitted: (_) => _save(),
        ),
        if (_mode == EntryMode.transfer)
          ..._transferFields(context)
        else
          ..._entryFields(context, workspaces),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l.fieldNote,
            border: const OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        DateTimeChips(
          date: _date,
          time: _time,
          onDate: (d) => setState(() => _date = d),
          onTime: (t) => setState(() => _time = t),
        ),
      ],
    );
  }

  List<Widget> _entryFields(BuildContext context, List<Workspace> workspaces) {
    final l = context.l10n;
    final wsId = _workspaceId;
    if (wsId == null) return const [LoadingState()];
    final type = _mode == EntryMode.income ? CategoryType.income : CategoryType.expense;
    final nodes = ref.watch(workspaceCategoryTreeProvider(wsId, type)).value;
    final accounts = ref.watch(workspaceAccountsProvider(wsId)).value;
    final recent = (_isEdit || widget.args.repeatId != null)
        ? null
        : ref.watch(recentTemplatesProvider(wsId)).value;

    // Default / repair the account choice once accounts are known.
    if (accounts != null && !accounts.any((a) => a.account.id == _accountId)) {
      final last = ref.read(entryDefaultsProvider).lastAccountFor(wsId);
      final match = accounts.where((a) => a.account.id == last);
      _accountId = match.isNotEmpty
          ? match.first.account.id
          : accounts.isNotEmpty
              ? accounts.first.account.id
              : null;
    }
    final selectedNode = nodes?.where((n) => n.category.id == _categoryId).firstOrNull;
    final templates = recent?.where((t) => t.type.categoryType == type).toList() ?? const [];

    return [
      if (workspaces.length > 1) ...[
        FormSectionLabel(l.fieldWorkspace),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            for (final w in workspaces)
              ButtonSegment(value: w.id, label: Text(workspaceTypeLabel(l, w.type))),
          ],
          selected: {wsId},
          onSelectionChanged: (s) => setState(() {
            if (_workspaceId == s.first) return;
            _workspaceId = s.first;
            _accountId = null;
            // Workspace-only categories may not exist in the other workspace.
            _categoryId = null;
            _subcategoryId = null;
          }),
        ),
      ],
      if (templates.isNotEmpty) ...[
        FormSectionLabel(l.recentTitle),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: templates.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _RecentChip(template: templates[i], onTap: _applyTemplate),
          ),
        ),
      ],
      FormSectionLabel(l.fieldCategory,
          errorText: _showErrors && _categoryId == null ? l.chooseCategory : null),
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
      if (selectedNode != null && selectedNode.children.isNotEmpty) ...[
        FormSectionLabel(l.fieldSubcategory),
        SubcategoryChips(
          children: selectedNode.children,
          selectedId: _subcategoryId,
          onSelected: (id) => setState(() => _subcategoryId = id),
        ),
      ],
      FormSectionLabel(l.fieldAccount,
          errorText: _showErrors && _accountId == null ? l.chooseAccount : null),
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
    final workspaces = ref.watch(workspacesProvider).value ?? const <Workspace>[];
    if (accounts == null) return const [SizedBox(height: 80, child: LoadingState())];
    final list = [for (final a in accounts) a.account];
    final types = {for (final w in workspaces) w.id: w.type};
    final from = list.where((a) => a.id == _accountId).firstOrNull;
    final to = list.where((a) => a.id == _toAccountId).firstOrNull;
    final crosses = from != null && to != null && from.workspaceId != to.workspaceId;
    final sameError = _showErrors && _accountId != null && _accountId == _toAccountId;
    return [
      const SizedBox(height: 16),
      AccountDropdown(
        label: l.fieldFromAccount,
        accounts: list,
        workspaceTypes: types,
        value: _accountId,
        errorText: _showErrors && _accountId == null ? l.chooseAccount : null,
        onChanged: (v) => setState(() => _accountId = v),
      ),
      const SizedBox(height: 12),
      AccountDropdown(
        label: l.fieldToAccount,
        accounts: list,
        workspaceTypes: types,
        value: _toAccountId,
        errorText: _showErrors && _toAccountId == null
            ? l.chooseAccount
            : sameError
                ? l.errSameAccount
                : null,
        onChanged: (v) => setState(() => _toAccountId = v),
      ),
      if (crosses)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(l.transferCrossWorkspaceNote, style: Theme.of(context).textTheme.bodySmall),
        ),
    ];
  }
}

class _RecentChip extends ConsumerWidget {
  const _RecentChip({required this.template, required this.onTap});

  final RecentTemplate template;
  final ValueChanged<RecentTemplate> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = Localizations.localeOf(context).languageCode;
    final f = ref.watch(appFormatsProvider);
    final name = template.description ??
        (template.subcategory ?? template.category).displayName(lang);
    return ActionChip(
      avatar: const Icon(Icons.replay, size: 18),
      label: Text('$name · ${f.money.format(template.amount)}'),
      onPressed: () => onTap(template),
    );
  }
}

class _Missing {
  const _Missing();
}
