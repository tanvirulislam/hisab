import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/providers.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_field.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../accounts/presentation/account_providers.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../../settings/presentation/app_formats.dart';
import '../../transactions/domain/drafts.dart';
import '../../transactions/domain/ledger_entry.dart';
import '../../transactions/presentation/transaction_providers.dart';
import '../../transactions/presentation/widgets/entry_pickers.dart';
import '../../workspaces/domain/workspace.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../domain/transaction_text_parser.dart';
import 'voice_providers.dart';

/// One editable proposal on the confirmation screen.
class _Item {
  _Item(ParsedProposal p)
    : type = p.type,
      amount = TextEditingController(text: p.amount == null ? '' : _amountText(p.amount!)),
      note = TextEditingController(text: p.description ?? ''),
      categoryId = p.categoryId,
      subcategoryId = p.subcategoryId,
      date = p.date,
      needsReview = p.needsReview,
      source = p.sourceText;

  EntryType type;
  final TextEditingController amount;
  final TextEditingController note;
  String? categoryId;
  String? subcategoryId;
  LocalDate date;
  bool include = true;
  bool needsReview;
  final String source;

  static String _amountText(Money m) =>
      m.paisaPart == 0 ? '${m.taka}' : '${m.taka}.${m.paisaPart.toString().padLeft(2, '0')}';

  Money? get parsedAmount {
    final m = Money.tryParse(amount.text);
    return m != null && m.isPositive ? m : null;
  }

  bool get isComplete => parsedAmount != null && categoryId != null;

  void dispose() {
    amount.dispose();
    note.dispose();
  }
}

/// Voice confirmation (§9.1 steps 5–9): proposals parsed from [text] are
/// shown for editing, and nothing is saved until the user confirms.
class VoiceConfirmScreen extends ConsumerStatefulWidget {
  const VoiceConfirmScreen({super.key, required this.text});

  final String text;

  @override
  ConsumerState<VoiceConfirmScreen> createState() => _VoiceConfirmScreenState();
}

class _VoiceConfirmScreenState extends ConsumerState<VoiceConfirmScreen> {
  String? _workspaceId;
  String? _accountId;
  List<_Item>? _items;

  /// Workspace the items were parsed for; categories differ per workspace.
  String? _parsedFor;
  bool _showErrors = false;

  @override
  void dispose() {
    for (final i in _items ?? const <_Item>[]) {
      i.dispose();
    }
    super.dispose();
  }

  void _parse(String workspaceId) {
    final lexicon = ref.read(voiceLexiconProvider(workspaceId)).value;
    if (lexicon == null) return;
    final proposals = ref.read(transactionTextParserProvider).parse(
          widget.text,
          ParseContext(today: ref.read(clockProvider).today(), lexicon: lexicon),
        );
    // The fields still hold the old controllers until this frame is built.
    final old = _items;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final i in old) {
          i.dispose();
        }
      });
    }
    _items = [for (final p in proposals) _Item(p)];
    _parsedFor = workspaceId;
  }

  Future<void> _save() async {
    setState(() => _showErrors = true);
    final items = (_items ?? const <_Item>[]).where((i) => i.include).toList();
    if (items.isEmpty || _accountId == null || items.any((i) => !i.isComplete)) return;
    final now = ref.read(clockProvider).now();
    final drafts = [
      for (final i in items)
        EntryDraft(
          type: i.type,
          workspaceId: _workspaceId!,
          accountId: _accountId!,
          amount: i.parsedAmount!,
          categoryId: i.categoryId!,
          subcategoryId: i.subcategoryId,
          description: i.note.text,
          occurredAt: DateTime(i.date.year, i.date.month, i.date.day, now.hour, now.minute),
          source: EntrySource.voice,
        ),
    ];
    final ok = await ref.read(addTransactionProvider.notifier).saveEntries(drafts);
    if (!mounted) return;
    final l = context.l10n;
    if (ok) {
      showSnack(context, l.voiceSaved(ref.read(appFormatsProvider).integer(drafts.length)), kind: ToastKind.success);
      context.go(Routes.home);
    } else {
      final err = ref.read(addTransactionProvider).error;
      showSnack(context, err == null ? l.errorMessage : errorMessage(l, err),
          kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final workspaces = ref.watch(workspacesProvider).value ?? const <Workspace>[];
    _workspaceId ??= workspaces.isEmpty
        ? null
        : ref.read(entryDefaultsProvider).defaultWorkspaceId(workspaces);
    final wsId = _workspaceId;
    final lexicon = wsId == null ? null : ref.watch(voiceLexiconProvider(wsId));
    if (wsId != null && lexicon?.value != null && _parsedFor != wsId) _parse(wsId);
    final saving = ref.watch(addTransactionProvider).isLoading;
    final included = _items?.where((i) => i.include).length ?? 0;

    Widget body;
    if (lexicon?.hasError ?? false) {
      body = ErrorState(error: lexicon!.error);
    } else if (_items == null || wsId == null) {
      body = const LoadingState();
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: Text(l.voiceYouSaid),
              subtitle: Text(widget.text),
            ),
          ),
          _AccountPicker(
            workspaceId: wsId,
            selectedId: _accountId,
            showError: _showErrors && _accountId == null,
            onSelected: (id) => setState(() => _accountId = id),
          ),
          FormSectionLabel(l.voiceProposals),
          if (_items!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(l.voiceNothingFound, textAlign: TextAlign.center),
            ),
          for (final (index, item) in _items!.indexed)
            _ProposalCard(
              key: ValueKey('proposal-$index'),
              item: item,
              workspaceId: wsId,
              showErrors: _showErrors,
              onChanged: () => setState(() {}),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.voiceConfirmTitle)),
      body: body,
      bottomNavigationBar: _items == null || _items!.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: saving || included == 0 ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(l.voiceSaveCount(ref.watch(appFormatsProvider).integer(included))),
                ),
              ),
            ),
    );
  }
}

/// Account for all items, defaulting to the last one used in the workspace.
class _AccountPicker extends ConsumerWidget {
  const _AccountPicker({
    required this.workspaceId,
    required this.selectedId,
    required this.showError,
    required this.onSelected,
  });

  final String workspaceId;
  final String? selectedId;
  final bool showError;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final accounts = ref.watch(workspaceAccountsProvider(workspaceId)).value;
    if (accounts != null && accounts.isNotEmpty && !accounts.any((a) => a.account.id == selectedId)) {
      final last = ref.read(entryDefaultsProvider).lastAccountFor(workspaceId);
      final id = accounts.where((a) => a.account.id == last).firstOrNull?.account.id ?? accounts.first.account.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSelected(id));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormSectionLabel(l.fieldAccount, errorText: showError ? l.chooseAccount : null),
        if (accounts == null)
          const SizedBox(height: 40, child: LoadingState())
        else if (accounts.isEmpty)
          Text(l.noActiveAccounts)
        else
          AccountChips(accounts: [for (final a in accounts) a.account], selectedId: selectedId, onSelected: onSelected),
      ],
    );
  }
}

class _ProposalCard extends ConsumerWidget {
  const _ProposalCard({
    super.key,
    required this.item,
    required this.workspaceId,
    required this.showErrors,
    required this.onChanged,
  });

  final _Item item;
  final String workspaceId;
  final bool showErrors;
  final VoidCallback onChanged;

  Future<void> _pickCategory(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategorySheet(
        workspaceId: workspaceId,
        type: item.type.categoryType,
        categoryId: item.categoryId,
        subcategoryId: item.subcategoryId,
      ),
    );
    if (picked == null) return;
    item
      ..categoryId = picked.$1
      ..subcategoryId = picked.$2
      ..needsReview = false;
    onChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final tree = ref.watch(workspaceCategoryTreeProvider(workspaceId, item.type.categoryType)).value ?? const [];
    final node = tree.where((n) => n.category.id == item.categoryId).firstOrNull;
    final sub = node?.children.where((c) => c.id == item.subcategoryId).firstOrNull;
    final cat = sub ?? node?.category;
    final dateLabel = f.isToday(item.date)
        ? l.today
        : f.isYesterday(item.date)
            ? l.yesterday
            : f.dateLong(item.date);

    return Card(
      child: Opacity(
        opacity: item.include ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: item.include,
                    onChanged: (v) {
                      item.include = v ?? false;
                      onChanged();
                    },
                  ),
                  Expanded(
                    child: Text('“${item.source}”',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ),
                  if (item.needsReview)
                    Tooltip(
                      message: l.voiceCheckThis,
                      child: Icon(Icons.help_outline, color: context.financeColors.warning, size: 20),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<EntryType>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -2, vertical: -2)),
                      segments: [
                        ButtonSegment(value: EntryType.expense, label: Text(l.entryExpense)),
                        ButtonSegment(value: EntryType.income, label: Text(l.entryIncome)),
                      ],
                      selected: {item.type},
                      onSelectionChanged: item.include
                          ? (s) {
                              if (item.type == s.first) return;
                              item
                                ..type = s.first
                                ..categoryId = null
                                ..subcategoryId = null;
                              onChanged();
                            }
                          : null,
                    ),
                    const SizedBox(height: 8),
                    AmountField(
                      controller: item.amount,
                      large: false,
                      label: l.fieldAmount,
                      errorText: showErrors && item.include && item.parsedAmount == null ? l.errAmountInvalid : null,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ActionChip(
                          avatar: cat == null
                              ? const Icon(Icons.category_outlined, size: 18)
                              : CategoryAvatar(iconKey: cat.iconKey, color: Color(node!.category.color), size: 24),
                          label: Text(cat == null
                              ? l.chooseCategory
                              : sub == null
                                  ? cat.displayName(lang)
                                  : '${node!.category.displayName(lang)} · ${sub.displayName(lang)}'),
                          side: showErrors && item.include && cat == null
                              ? BorderSide(color: theme.colorScheme.error)
                              : null,
                          onPressed: item.include ? () => _pickCategory(context, ref) : null,
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.calendar_today, size: 18),
                          label: Text(dateLabel),
                          onPressed: item.include
                              ? () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: item.date.toDateTime(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(f.today.year + 1, 12, 31),
                                  );
                                  if (picked == null) return;
                                  item.date = LocalDate.fromDateTime(picked);
                                  onChanged();
                                }
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: item.note,
                      maxLength: 500,
                      enabled: item.include,
                      decoration: InputDecoration(
                        labelText: l.fieldNote,
                        isDense: true,
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({required this.workspaceId, required this.type, this.categoryId, this.subcategoryId});

  final String workspaceId;
  final CategoryType type;
  final String? categoryId;
  final String? subcategoryId;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  late String? _categoryId = widget.categoryId;
  late String? _subcategoryId = widget.subcategoryId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final nodes = ref.watch(workspaceCategoryTreeProvider(widget.workspaceId, widget.type)).value;
    final node = nodes?.where((n) => n.category.id == _categoryId).firstOrNull;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.fieldCategory, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
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
              if (node != null && node.children.isNotEmpty) ...[
                FormSectionLabel(l.fieldSubcategory),
                SubcategoryChips(
                  children: node.children,
                  selectedId: _subcategoryId,
                  onSelected: (id) => setState(() => _subcategoryId = id),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _categoryId == null ? null : () => Navigator.of(context).pop((_categoryId!, _subcategoryId)),
                child: Text(l.voiceUseCategory),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
