import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Confirmation for destructive actions (§6.5). Resolves to true only when
/// the user confirms.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
}) async {
  final l10n = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel ?? l10n.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}
