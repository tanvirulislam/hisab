import 'package:flutter/widgets.dart';

/// What the tab bar's Add button does on each screen (D21).
///
/// By default Add opens the transaction form. A screen inside a tab (Budgets,
/// Categories, Accounts, Loans, a person's loans) registers its own action
/// for its route path instead of showing a FAB, so one Add button does both.
/// The shell looks the action up by the current location, so a screen that
/// stays mounted in a hidden tab never takes over Add elsewhere.
class AddActions {
  final Map<String, VoidCallback> _byPath = {};

  void _register(String path, VoidCallback onAdd) => _byPath[path] = onAdd;

  void _unregister(String path, VoidCallback onAdd) {
    if (_byPath[path] == onAdd) _byPath.remove(path);
  }

  /// The action for [path], or null for the default (new transaction).
  VoidCallback? forPath(String path) => _byPath[path];
}

/// Puts [AddActions] below the shell so its screens can reach it.
class AddActionsScope extends InheritedWidget {
  const AddActionsScope({super.key, required this.actions, required super.child});

  final AddActions actions;

  static AddActions? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AddActionsScope>()?.actions;

  @override
  bool updateShouldNotify(AddActionsScope oldWidget) => !identical(actions, oldWidget.actions);
}

/// Makes the tab bar's Add button run [onAdd] while [path] is the current
/// location. Wrap a screen's Scaffold with it.
class AddAction extends StatefulWidget {
  const AddAction({super.key, required this.path, required this.onAdd, required this.child});

  final String path;
  final VoidCallback onAdd;
  final Widget child;

  @override
  State<AddAction> createState() => _AddActionState();
}

class _AddActionState extends State<AddAction> {
  AddActions? _actions;

  // Always calls the latest widget.onAdd, so the registry entry does not
  // change on every rebuild.
  void _call() => widget.onAdd();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final actions = AddActionsScope.maybeOf(context);
    if (!identical(actions, _actions)) {
      _actions?._unregister(widget.path, _call);
      _actions = actions?.._register(widget.path, _call);
    }
  }

  @override
  void didUpdateWidget(AddAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _actions?._unregister(oldWidget.path, _call);
      _actions?._register(widget.path, _call);
    }
  }

  @override
  void dispose() {
    _actions?._unregister(widget.path, _call);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
