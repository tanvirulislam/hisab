import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../core/providers.dart';
import '../../../core/utils/bn_digits.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../../settings/presentation/app_formats.dart';
import '../data/drive_config.dart';
import 'backup_providers.dart';

/// More → Backup & restore (D22): Google sign-in, "Back up now", restore
/// from Drive and undo the last restore.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(backupControllerProvider.notifier).start();
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    final toast = AppToast.of(context);
    final l = context.l10n;
    try {
      await action();
      if (success != null) toast.show(success, kind: ToastKind.success);
    } on Object catch (e) {
      toast.show(errorMessage(l, e), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final status = ref.watch(backupControllerProvider);
    final ctrl = ref.read(backupControllerProvider.notifier);
    final theme = Theme.of(context);
    final busy = status.busy != BackupBusy.none;

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(l.backupIntro, style: theme.textTheme.bodyLarge),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(
          l.backupIntroScope,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    ];

    if (!status.checked) {
      children.add(const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())));
    } else if (!status.signedIn) {
      children.add(Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: busy ? null : () => _run(ctrl.signIn),
          icon: status.busy == BackupBusy.signingIn ? const _Spinner() : const Icon(Icons.login),
          label: Text(status.busy == BackupBusy.signingIn ? l.backupSigningIn : l.backupSignIn),
        ),
      ));
      if (status.hasSafety) children.add(_undoTile(l, busy));
    } else {
      children.addAll([
        ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(l.backupAccount),
          subtitle: Text(status.email!),
        ),
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(l.backupFolder),
          subtitle: const Text(kDriveFolderName),
        ),
        ListTile(
          leading: Icon(
            status.lastErrorCode != null ? Icons.error_outline : Icons.cloud_done_outlined,
            color: status.lastErrorCode != null ? theme.colorScheme.error : null,
          ),
          title: Text(l.backupLast),
          subtitle: Text(_lastLine(l, status)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l.backupAutoHint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            onPressed: busy ? null : () => _run(ctrl.backupNow, success: l.backupDone),
            icon: status.busy == BackupBusy.backingUp ? const _Spinner() : const Icon(Icons.backup_outlined),
            label: Text(status.busy == BackupBusy.backingUp ? l.backupRunning : l.backupNow),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: OutlinedButton.icon(
            onPressed: busy ? null : () => context.push(Routes.backupRestore),
            icon: const Icon(Icons.restore),
            label: Text(l.restoreFromDrive),
          ),
        ),
        if (status.hasSafety) _undoTile(l, busy),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(l.backupSignOut),
          enabled: !busy,
          onTap: () => _run(ctrl.signOut, success: l.backupSignedOut),
        ),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.moreBackup)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: children),
    );
  }

  Widget _undoTile(AppLocalizations l, bool busy) => ListTile(
    leading: const Icon(Icons.undo),
    title: Text(l.restoreUndo),
    subtitle: Text(l.restoreUndoHint),
    enabled: !busy,
    onTap: () async {
      final ok = await confirmDestructive(
        context,
        title: l.restoreUndo,
        message: l.restoreUndoConfirm,
        confirmLabel: l.restoreAction,
      );
      if (!ok || !mounted) return;
      await _run(ref.read(backupControllerProvider.notifier).undoRestore, success: l.restoreUndone);
    },
  );

  String _lastLine(AppLocalizations l, BackupStatus s) {
    if (s.lastErrorCode != null) return l.backupLastFailed(backupErrorText(l, s.lastErrorCode!));
    if (s.lastSuccess == null) return l.backupNever;
    return relativeTime(l, ref.read(appFormatsProvider), s.lastSuccess!, ref.read(clockProvider).now());
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));
}

/// "5 minutes ago", "yesterday"-style text; older than a week shows the date.
String relativeTime(AppLocalizations l, AppFormats f, DateTime at, DateTime now) {
  String n(int v) => f.banglaDigits ? BnDigits.toBangla('$v') : '$v';
  final d = now.difference(at);
  if (d.inMinutes < 1) return l.timeJustNow;
  if (d.inHours < 1) return l.timeMinutesAgo(d.inMinutes, n(d.inMinutes));
  if (d.inDays < 1) return l.timeHoursAgo(d.inHours, n(d.inHours));
  if (d.inDays < 7) return l.timeDaysAgo(d.inDays, n(d.inDays));
  return dateTimeText(f, at);
}

/// "27 Nov 2026, 9:30 PM" in the app's language and digits.
String dateTimeText(AppFormats f, DateTime at) {
  final s = '${DateFormat('d MMM y', f.languageCode).format(at)}, ${DateFormat.jm(f.languageCode).format(at)}';
  return f.banglaDigits ? BnDigits.toBangla(s) : BnDigits.toLatin(s);
}
