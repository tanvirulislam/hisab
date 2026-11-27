import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/motion.dart';
import '../l10n/l10n.dart';
import 'add_action.dart';
import 'routes.dart';

/// Bottom navigation with five items: Home, History, Add, Reports, More.
///
/// The shell has four branches (Add is a pushed route), so navigation
/// index 2 opens Add and indices 3–4 map to branches 2–3.
///
/// Add opens the transaction form, unless the current screen registered its
/// own action with [AddAction] (D21): Budgets, Categories, Accounts, Loans.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const int _addIndex = 2;

  final _addActions = AddActions();

  StatefulNavigationShell get shell => widget.shell;

  int get _navIndex => shell.currentIndex >= _addIndex ? shell.currentIndex + 1 : shell.currentIndex;

  void _onTap(BuildContext context, int index) {
    if (index == _addIndex) {
      final path = GoRouter.of(context).state.uri.path;
      final screenAdd = _addActions.forPath(path);
      if (screenAdd != null) {
        screenAdd();
      } else {
        context.push(Routes.add);
      }
      return;
    }
    final branch = index > _addIndex ? index - 1 : index;
    // Tapping the current tab again returns it to its root.
    shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: AddActionsScope(actions: _addActions, child: shell),
      bottomNavigationBar: AppNavBar(
        selectedIndex: _navIndex,
        onSelected: (i) => _onTap(context, i),
        items: [
          AppNavItemData(icon: Icons.home_outlined, selectedIcon: Icons.home, label: l10n.navHome),
          AppNavItemData(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: l10n.navHistory),
          AppNavItemData(icon: Icons.add, label: l10n.navAdd, isAction: true),
          AppNavItemData(icon: Icons.bar_chart_outlined, selectedIcon: Icons.bar_chart, label: l10n.navReports),
          AppNavItemData(icon: Icons.menu, label: l10n.navMore),
        ],
      ),
    );
  }
}

class AppNavItemData {
  const AppNavItemData({required this.icon, this.selectedIcon, required this.label, this.isAction = false});

  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  /// Add: drawn as an outlined circle and never selected.
  final bool isAction;
}

/// The tab bar (D20): one highlight pill that glides to the tapped tab with
/// a small overshoot, and the new tab's icon pops once.
class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.selectedIndex, required this.onSelected, required this.items});

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<AppNavItemData> items;

  static const double _pillWidth = 64;
  static const double _pillHeight = 32;
  static const double _top = 12;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: LayoutBuilder(
            builder: (context, box) {
              final slot = box.maxWidth / items.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: Motion.of(context, const Duration(milliseconds: 420)),
                    curve: Curves.easeOutBack,
                    top: _top,
                    left: slot * selectedIndex + (slot - _pillWidth) / 2,
                    width: _pillWidth,
                    height: _pillHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(_pillHeight / 2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: AppNavItem(data: items[i], selected: i == selectedIndex, onTap: () => onSelected(i)),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class AppNavItem extends StatelessWidget {
  const AppNavItem({super.key, required this.data, required this.selected, required this.onTap});

  final AppNavItemData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    Widget icon;
    if (data.isAction) {
      // Outlined like the Home cards, so the tab bar does not shout.
      icon = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Icon(data.icon, color: scheme.primary, size: 26),
      );
    } else if (selected) {
      // A new key each time the tab is selected, so the pop plays again.
      icon = PopIn(
        key: ValueKey('pop-${data.label}'),
        child: Icon(data.selectedIcon ?? data.icon, color: color),
      );
    } else {
      icon = Icon(data.icon, color: color);
    }
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: AppNavBar._top),
            SizedBox(
              height: AppNavBar._pillHeight,
              child: Center(child: OverflowBox(maxHeight: 48, child: icon)),
            ),
            const SizedBox(height: 4),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds the tab branches and animates the switch (D20): the old tab fades
/// out quickly while the new one fades in rising a little. Every branch keeps
/// the same wrappers whether shown or not, so no tab loses its state.
class AnimatedBranchContainer extends StatefulWidget {
  const AnimatedBranchContainer({super.key, required this.currentIndex, required this.children});

  final int currentIndex;
  final List<Widget> children;

  @override
  State<AnimatedBranchContainer> createState() => _AnimatedBranchContainerState();
}

class _AnimatedBranchContainerState extends State<AnimatedBranchContainer> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 340);
  late final AnimationController _c = AnimationController(vsync: this, duration: _total, value: 1);
  late final Animation<double> _in = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.18, 1, curve: Motion.enter),
  );
  late final Animation<double> _out = CurvedAnimation(parent: _c, curve: const Interval(0, 0.35));
  int? _previous;

  @override
  void didUpdateWidget(AnimatedBranchContainer old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _previous = old.currentIndex;
      if (Motion.reduced(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final leaving = _c.isAnimating ? _previous : null;
      return Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            _branch(i, current: i == widget.currentIndex, leaving: i == leaving),
        ],
      );
    },
  );

  Widget _branch(int i, {required bool current, required bool leaving}) {
    final visible = current || leaving;
    final opacity = current ? _in.value : (leaving ? 1 - _out.value : 0.0);
    final rise = current ? 18 * (1 - _in.value) : 0.0;
    return Offstage(
      key: ValueKey(i),
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: IgnorePointer(
          ignoring: !current,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, rise), child: widget.children[i]),
          ),
        ),
      ),
    );
  }
}
