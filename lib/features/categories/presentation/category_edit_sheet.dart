import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../../settings/presentation/app_formats.dart';
import '../domain/category.dart';
import '../domain/category_repository.dart';
import 'category_providers.dart';

const List<int> categoryPalette = [
  0xFF2E7D32, 0xFF00838F, 0xFF1565C0, 0xFF283593, 0xFF6A1B9A, 0xFFAD1457,
  0xFFC62828, 0xFFE65100, 0xFFF9A825, 0xFF6D4C41, 0xFF4E342E, 0xFF546E7A,
];

/// Create a category / subcategory, or edit an existing one.
Future<void> showCategoryEditSheet(
  BuildContext context, {
  required CategoryType type,
  Category? existing,
  Category? parent,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _CategoryEditSheet(type: type, existing: existing, parent: parent),
);

class _CategoryEditSheet extends ConsumerStatefulWidget {
  const _CategoryEditSheet({required this.type, this.existing, this.parent});

  final CategoryType type;
  final Category? existing;
  final Category? parent;

  @override
  ConsumerState<_CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends ConsumerState<_CategoryEditSheet> {
  late final _name = TextEditingController();
  late String _icon = widget.existing?.iconKey ?? widget.parent?.iconKey ?? 'label';
  late int _color = widget.existing?.color ?? widget.parent?.color ?? categoryPalette.first;

  /// NULL = all workspaces. Only chosen when creating a top-level category.
  bool _saving = false;

  bool get _isSub => widget.parent != null || (widget.existing?.isSubcategory ?? false);

  /// The name shown when the sheet opened (translated for seeded ones).
  String? _initialName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialName == null && widget.existing != null) {
      _initialName = widget.existing!.displayName(Localizations.localeOf(context).languageCode);
      _name.text = _initialName!;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(categoryRepositoryProvider);
    final l = context.l10n;
    try {
      if (widget.existing != null) {
        // An untouched (translated) name keeps the stored one, so a seeded
        // category stays translated in both languages.
        final name = _name.text == _initialName ? widget.existing!.name : _name.text;
        await repo.updateCategory(widget.existing!.id, name: name, iconKey: _icon, color: _color);
      } else {
        await repo.createCategory(CategoryDraft(
          name: _name.text,
          type: widget.type,
          iconKey: _icon,
          color: _color,
          parentId: widget.parent?.id,
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showSnack(context, errorMessage(l, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final title = widget.existing != null
        ? l.editCategory
        : _isSub
            ? '${l.addSubcategory} · ${widget.parent!.displayName(lang)}'
            : l.addCategory;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CategoryAvatar(iconKey: _icon, color: Color(_color), size: 48),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.fieldName, border: const OutlineInputBorder()),
            ),
            if (!_isSub) ...[
              Text(l.fieldColor, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categoryPalette)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = c),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Color(c),
                        child: c == _color ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(l.fieldIcon, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            SizedBox(
              height: 160,
              child: GridView.count(
                crossAxisCount: 7,
                children: [
                  for (final key in AppIcons.byKey.keys)
                    IconButton(
                      isSelected: key == _icon,
                      style: IconButton.styleFrom(
                        backgroundColor: key == _icon
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : null,
                      ),
                      icon: Icon(AppIcons.of(key)),
                      onPressed: () => setState(() => _icon = key),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _saving ? null : _save,
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }
}

/// Actions for a category: edit, add subcategory, archive / restore, delete
/// (with safe reassignment when in use, §7.2).
Future<void> showCategoryActions(BuildContext context, WidgetRef ref, Category c) async {
  final l = context.l10n;
  final lang = Localizations.localeOf(context).languageCode;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: CategoryAvatar(iconKey: c.iconKey, color: Color(c.color)),
            title: Text(c.displayName(lang), style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l.edit),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showCategoryEditSheet(context, type: c.type, existing: c);
            },
          ),
          if (!c.isSubcategory && c.isActive)
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l.addSubcategory),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showCategoryEditSheet(context, type: c.type, parent: c);
              },
            ),
          if (!c.isProtected)
            ListTile(
              leading: Icon(c.isActive ? Icons.archive_outlined : Icons.unarchive_outlined),
              title: Text(c.isActive ? l.archive : l.unarchive),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                try {
                  await ref.read(categoryRepositoryProvider).setArchived(c.id, archived: c.isActive);
                } on Object catch (e) {
                  if (context.mounted) showSnack(context, errorMessage(l, e));
                }
              },
            ),
          if (!c.isProtected)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text(l.delete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _deleteCategory(context, ref, c);
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> _deleteCategory(BuildContext context, WidgetRef ref, Category c) async {
  final l = context.l10n;
  final repo = ref.read(categoryRepositoryProvider);
  try {
    final used = await repo.usageCount(c.id);
    if (!context.mounted) return;
    if (used == 0) {
      if (await confirmDestructive(context, title: l.deleteCategoryConfirm)) {
        await repo.deleteCategory(c.id);
      }
      return;
    }
    final target = await showDialog<_InUseChoice>(
      context: context,
      builder: (_) => _InUseDialog(category: c, usage: used),
    );
    if (target == null) return;
    if (target.archiveOnly) {
      await repo.setArchived(c.id, archived: true);
    } else {
      await repo.reassignAndArchive(c.id, toId: target.toId);
    }
  } on Object catch (e) {
    if (context.mounted) showSnack(context, errorMessage(l, e));
  }
}

class _InUseChoice {
  const _InUseChoice({this.toId, this.archiveOnly = false});

  final String? toId;
  final bool archiveOnly;
}

class _InUseDialog extends ConsumerStatefulWidget {
  const _InUseDialog({required this.category, required this.usage});

  final Category category;
  final int usage;

  @override
  ConsumerState<_InUseDialog> createState() => _InUseDialogState();
}

class _InUseDialogState extends ConsumerState<_InUseDialog> {
  String? _toId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final c = widget.category;
    final tree = ref.watch(categoryTreeProvider(c.type)).value ?? const [];
    // Targets must be usable wherever the source was (rule 11).
    final targets = [
      for (final n in tree)
        if (n.category.id != c.id &&
            (n.category.workspaceId == null || n.category.workspaceId == c.workspaceId))
          n.category,
    ];
    return AlertDialog(
      title: Text(l.errCategoryInUse),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.categoryInUseMessage(ref.watch(appFormatsProvider).integer(widget.usage))),
          const SizedBox(height: 16),
          if (c.isSubcategory)
            Text(l.removeSubcategoryNote)
          else
            DropdownButtonFormField<String>(
              initialValue: _toId,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.moveTransactionsTo, border: const OutlineInputBorder()),
              items: [
                for (final t in targets)
                  DropdownMenuItem(value: t.id, child: Text(t.displayName(lang))),
              ],
              onChanged: (v) => setState(() => _toId = v),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(const _InUseChoice(archiveOnly: true)),
          child: Text(l.archive),
        ),
        FilledButton(
          onPressed: c.isSubcategory || _toId != null
              ? () => Navigator.of(context).pop(_InUseChoice(toId: _toId))
              : null,
          child: Text(l.moveAndArchive),
        ),
      ],
    );
  }
}
