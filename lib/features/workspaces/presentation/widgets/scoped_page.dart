import 'package:flutter/material.dart';

/// Page layout for the main tabs (Home, History, Reports).
class ScopedPage extends StatelessWidget {
  const ScopedPage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottom,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: actions,
      bottom: bottom,
    ),
    body: body,
  );
}
