import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/bn_digits.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../settings/presentation/app_formats.dart';
import '../domain/backup_summary.dart';
import 'backup_providers.dart';
import 'backup_screen.dart';

/// The app's backups on Drive, newest first.
final remoteBackupsProvider = FutureProvider.autoDispose<List<RemoteBackup>>(
  (ref) => ref.read(backupControllerProvider.notifier).listRemote(),
  retry: (_, _) => null,
);

/// Restore list (D22): pick a backup → download and check → preview →
/// confirm → restore.
class RestoreScreen extends ConsumerWidget {
  const RestoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final backups = ref.watch(remoteBackupsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.restoreListTitle)),
      body: switch (backups) {
        AsyncData(:final value) when value.isEmpty =>
          EmptyState(icon: Icons.cloud_off_outlined, title: l.restoreListEmpty),
        AsyncData(:final value) => ListView.separated(
          itemCount: value.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, i) {
            final b = value[i];
            final n = b.transactionCount;
            return ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(dateTimeText(f, b.createdAt)),
              subtitle: n == null ? null : Text(l.restoreTxCount(n, _digits(f, n))),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, ref, b),
            );
          },
        ),
        AsyncError(:final error) => EmptyState(
          icon: Icons.error_outline,
          title: errorMessage(l, error),
          action: FilledButton.tonal(
            onPressed: () => ref.invalidate(remoteBackupsProvider),
            child: Text(l.retry),
          ),
        ),
        _ => const LoadingState(),
      },
    );
  }

  static String _digits(AppFormats f, int n) => f.banglaDigits ? BnDigits.toBangla('$n') : '$n';

  Future<void> _open(BuildContext context, WidgetRef ref, RemoteBackup backup) async {
    final l = context.l10n;
    final toast = AppToast.of(context);
    final nav = Navigator.of(context);
    final ctrl = ref.read(backupControllerProvider.notifier);

    final PreparedRestore prepared;
    try {
      prepared = await _withProgress(context, l.restoreChecking, () => ctrl.prepare(backup.id));
    } on Object catch (e) {
      toast.show(errorMessage(l, e), kind: ToastKind.error);
      return;
    }
    if (!context.mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => _PreviewDialog(summary: prepared.summary),
    );
    if (go != true || !context.mounted) return;
    final sure = await confirmDestructive(
      context,
      title: l.restoreConfirmTitle,
      message: l.restoreConfirmBody,
      confirmLabel: l.restoreAction,
    );
    if (!sure || !context.mounted) return;

    try {
      await _withProgress(context, l.restoreRunning, () => ctrl.restore(prepared));
      toast.show(l.restoreDone, kind: ToastKind.success);
      if (nav.mounted) nav.pop();
    } on Object catch (e) {
      toast.show(errorMessage(l, e), kind: ToastKind.error);
    }
  }

  /// Runs [work] behind a modal "please wait" dialog.
  static Future<T> _withProgress<T>(BuildContext context, String message, Future<T> Function() work) async {
    final nav = Navigator.of(context, rootNavigator: true);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ]),
        ),
      ),
    ));
    try {
      return await work();
    } finally {
      nav.pop();
    }
  }
}

class _PreviewDialog extends ConsumerWidget {
  const _PreviewDialog({required this.summary});

  final BackupSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final theme = Theme.of(context);
    Widget row(String label, int n) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text(RestoreScreen._digits(f, n), style: theme.textTheme.titleSmall),
      ]),
    );
    return AlertDialog(
      title: Text(l.restorePreviewTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.restoreTakenOn(dateTimeText(f, summary.createdAt)),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            row(l.restoreCountTransactions, summary.transactions),
            row(l.restoreCountAccounts, summary.accounts),
            row(l.restoreCountCategories, summary.categories),
            row(l.restoreCountBudgets, summary.budgets),
            row(l.restoreCountPersons, summary.persons),
            row(l.restoreCountLoanEntries, summary.loanEntries),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.restoreAction)),
      ],
    );
  }
}
