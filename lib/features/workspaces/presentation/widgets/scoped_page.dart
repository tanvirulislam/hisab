import 'package:flutter/material.dart';

import 'workspace_selector.dart';

/// Page layout for scope-aware tabs (Home, History, Reports): an app bar
/// with the workspace switcher under it.
class ScopedPage extends StatelessWidget {
  const ScopedPage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: actions,
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(56),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: WorkspaceSelector(),
        ),
      ),
    ),
    body: body,
  );
}
