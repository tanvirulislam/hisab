import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../domain/category.dart';
import 'category_edit_sheet.dart';
import 'category_providers.dart';

/// Category management (§7.2). Tap a category for edit, subcategory,
/// archive and delete actions.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  CategoryType get _type => _tabs.index == 0 ? CategoryType.expense : CategoryType.income;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.moreCategories),
        bottom: TabBar(
          controller: _tabs,
          tabs: [Tab(text: l.categoryTypeExpense), Tab(text: l.categoryTypeIncome)],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCategoryEditSheet(context, type: _type),
        icon: const Icon(Icons.add),
        label: Text(l.addCategory),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _CategoryList(type: CategoryType.expense),
          _CategoryList(type: CategoryType.income),
        ],
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.type});

  final CategoryType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    return AsyncValueView(
      value: ref.watch(managedCategoryTreeProvider(type)),
      onRetry: () => ref.invalidate(managedCategoryTreeProvider(type)),
      data: (nodes) {
        if (nodes.isEmpty) {
          return EmptyState(icon: Icons.category_outlined, title: l.categoriesEmpty);
        }
        // Active first, archived at the end.
        final sorted = [
          ...nodes.where((n) => n.category.isActive),
          ...nodes.where((n) => !n.category.isActive),
        ];
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 96),
          itemCount: sorted.length,
          itemBuilder: (context, i) {
            final node = sorted[i];
            final c = node.category;
            final color = Color(c.color);
            Widget tile(Category cat, {bool child = false}) => Opacity(
              opacity: cat.isActive ? 1 : 0.5,
              child: ListTile(
                contentPadding: EdgeInsets.only(left: child ? 72 : 16, right: 8),
                leading: CategoryAvatar(iconKey: cat.iconKey, color: color, size: child ? 32 : 40),
                title: Text(cat.displayName(lang)),
                subtitle: !cat.isActive
                    ? Text(l.archivedLabel)
                    : !child && node.children.isNotEmpty
                        ? Text(l.subcategoryCount(node.children.length))
                        : null,
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => showCategoryActions(context, ref, cat),
                ),
                onTap: () => showCategoryActions(context, ref, cat),
              ),
            );
            if (node.children.isEmpty) return tile(c);
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              title: tile(c),
              showTrailingIcon: false,
              children: [for (final child in node.children) tile(child, child: true)],
            );
          },
        );
      },
    );
  }
}
