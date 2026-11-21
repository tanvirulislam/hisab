import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n.dart';
import 'routes.dart';

/// Bottom navigation with five items: Home, History, Add, Reports, More.
///
/// The shell has four branches (Add is a pushed route), so navigation
/// index 2 opens Add and indices 3–4 map to branches 2–3.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const int _addIndex = 2;

  int get _navIndex =>
      shell.currentIndex >= _addIndex ? shell.currentIndex + 1 : shell.currentIndex;

  void _onTap(BuildContext context, int index) {
    if (index == _addIndex) {
      context.push(Routes.add);
      return;
    }
    final branch = index > _addIndex ? index - 1 : index;
    // Tapping the current tab again returns it to its root.
    shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => _onTap(context, i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: l10n.navHistory,
          ),
          NavigationDestination(
            icon: CircleAvatar(
              radius: 20,
              backgroundColor: scheme.tertiary,
              child: Icon(Icons.add, color: scheme.onTertiary, size: 28),
            ),
            label: l10n.navAdd,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: l10n.navReports,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu),
            label: l10n.navMore,
          ),
        ],
      ),
    );
  }
}
