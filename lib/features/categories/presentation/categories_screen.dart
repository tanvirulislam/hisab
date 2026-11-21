import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../domain/category.dart';
import 'category_providers.dart';

/// Read-only category tree. Add, edit and archive come in Phase 2.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.moreCategories),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.categoryTypeExpense),
              Tab(text: l10n.categoryTypeIncome),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CategoryList(type: CategoryType.expense),
            _CategoryList(type: CategoryType.income),
          ],
        ),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.type});

  final CategoryType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    return AsyncValueView(
      value: ref.watch(categoryTreeProvider(type)),
      onRetry: () => ref.invalidate(categoryTreeProvider(type)),
      data: (nodes) {
        if (nodes.isEmpty) {
          return EmptyState(icon: Icons.category_outlined, title: l10n.categoriesEmpty);
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: nodes.length,
          itemBuilder: (context, i) {
            final node = nodes[i];
            final color = Color(node.category.color);
            final leading = CategoryAvatar(iconKey: node.category.iconKey, color: color);
            final title = Text(node.category.displayName(lang));
            if (node.children.isEmpty) {
              return ListTile(leading: leading, title: title);
            }
            return ExpansionTile(
              leading: leading,
              title: title,
              subtitle: Text(l10n.subcategoryCount(node.children.length)),
              shape: const Border(),
              children: [
                for (final child in node.children)
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 72, right: 16),
                    leading: CategoryAvatar(iconKey: child.iconKey, color: color, size: 32),
                    title: Text(child.displayName(lang)),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
