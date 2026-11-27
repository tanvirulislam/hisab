import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/services/local_prefs.dart';
import '../../notifications/presentation/notification_coordinator.dart';
import '../data/backup_repository.dart';
import '../data/backup_store.dart';
import '../data/google_account.dart';
import '../data/safety_backups.dart';
import '../domain/backup_file.dart';
import '../domain/backup_schedule.dart';
import '../domain/backup_summary.dart';

part 'backup_providers.g.dart';

@Riverpod(keepAlive: true)
GoogleAccount googleAccount(Ref ref) => GoogleSignInAccountService();

@Riverpod(keepAlive: true)
BackupStore backupStore(Ref ref) =>
    DriveBackupStore(ref.watch(googleAccountProvider), ref.watch(localPrefsProvider));

@Riverpod(keepAlive: true)
SafetyBackups safetyBackups(Ref ref) => SafetyBackups(
  () async => Directory('${(await getApplicationDocumentsDirectory()).path}/safety'),
);

@Riverpod(keepAlive: true)
BackupRepository backupRepository(Ref ref) => BackupRepository(ref.watch(appDatabaseProvider));

/// "1.0.0+1", or "unknown" where the platform cannot say (tests).
@Riverpod(keepAlive: true)
Future<String> appVersion(Ref ref) async {
  try {
    final p = await PackageInfo.fromPlatform();
    return '${p.version}+${p.buildNumber}';
  } on Object {
    return 'unknown';
  }
}

/// True once the user has made anything (D22 fresh-install offer).
@riverpod
Stream<bool> hasUserData(Ref ref) => ref.watch(backupRepositoryProvider).watchHasUserData();

enum BackupBusy { none, signingIn, backingUp, restoring }

/// What the Backup screen shows.
@immutable
class BackupStatus {
  const BackupStatus({
    this.checked = false,
    this.email,
    this.busy = BackupBusy.none,
    this.lastSuccess,
    this.lastErrorCode,
    this.lastErrorAt,
    this.hasSafety = false,
  });

  /// The silent sign-in has been tried.
  final bool checked;
  final String? email;
  final BackupBusy busy;
  final DateTime? lastSuccess;

  /// Set when the last attempt failed (after [lastSuccess]).
  final String? lastErrorCode;
  final DateTime? lastErrorAt;

  /// An "undo restore" copy exists on the device.
  final bool hasSafety;

  bool get signedIn => email != null;

  BackupStatus copyWith({
    bool? checked,
    String? Function()? email,
    BackupBusy? busy,
    DateTime? lastSuccess,
    String? Function()? lastErrorCode,
    DateTime? Function()? lastErrorAt,
    bool? hasSafety,
  }) => BackupStatus(
    checked: checked ?? this.checked,
    email: email == null ? this.email : email(),
    busy: busy ?? this.busy,
    lastSuccess: lastSuccess ?? this.lastSuccess,
    lastErrorCode: lastErrorCode == null ? this.lastErrorCode : lastErrorCode(),
    lastErrorAt: lastErrorAt == null ? this.lastErrorAt : lastErrorAt(),
    hasSafety: hasSafety ?? this.hasSafety,
  );
}

/// A downloaded, validated backup waiting for the user's confirmation.
class PreparedRestore {
  const PreparedRestore(this.data, this.summary);

  final BackupData data;
  final BackupSummary summary;
}

/// Coordinates sign-in, backups and restores (D22). Only one backup or
/// restore runs at a time.
@Riverpod(keepAlive: true)
class BackupController extends _$BackupController {
  Future<void>? _started;

  GoogleAccount get _account => ref.read(googleAccountProvider);
  BackupStore get _store => ref.read(backupStoreProvider);
  BackupRepository get _repo => ref.read(backupRepositoryProvider);
  SafetyBackups get _safety => ref.read(safetyBackupsProvider);
  LocalPrefs get _prefs => ref.read(localPrefsProvider);
  DateTime _now() => ref.read(clockProvider).now();

  @override
  BackupStatus build() {
    final success = int.tryParse(_prefs.getString(LocalPrefKeys.backupLastSuccess) ?? '');
    String? code;
    DateTime? at;
    try {
      final raw = _prefs.getString(LocalPrefKeys.backupLastError);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        code = m['code'] as String?;
        at = DateTime.fromMillisecondsSinceEpoch(m['at'] as int);
      }
    } on Object {
      // Ignore a damaged value.
    }
    return BackupStatus(
      email: _account.email,
      lastSuccess: success == null ? null : DateTime.fromMillisecondsSinceEpoch(success),
      lastErrorCode: code,
      lastErrorAt: at,
    );
  }

  /// Silent sign-in and the safety-copy check. Safe to call often.
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    final wasSignedIn = _prefs.getString(LocalPrefKeys.backupSignedIn) == '1';
    final email = wasSignedIn ? await _account.signInSilently() : null;
    bool hasSafety;
    try {
      hasSafety = await _safety.hasAny();
    } on Object {
      hasSafety = false;
    }
    if (!ref.mounted) return;
    state = state.copyWith(checked: true, email: () => email, hasSafety: hasSafety);
  }

  Future<T> _exclusive<T>(BackupBusy kind, Future<T> Function() body) async {
    if (state.busy != BackupBusy.none) throw const BackupException(BackupError.busy);
    state = state.copyWith(busy: kind);
    try {
      return await body();
    } finally {
      if (ref.mounted) state = state.copyWith(busy: BackupBusy.none);
    }
  }

  Future<void> signIn() => _exclusive(BackupBusy.signingIn, () async {
    final email = await _account.signIn();
    await _prefs.setString(LocalPrefKeys.backupSignedIn, '1');
    state = state.copyWith(checked: true, email: () => email);
  });

  Future<void> signOut() async {
    await _account.signOut();
    await _prefs.setString(LocalPrefKeys.backupSignedIn, '');
    await _prefs.setString(LocalPrefKeys.backupFolderId, '');
    state = state.copyWith(email: () => null);
  }

  // ------------------------------------------------------------- backup

  /// "Back up now". Throws [BackupException]; the failure is also recorded.
  Future<void> backupNow() => _exclusive(BackupBusy.backingUp, _upload);

  /// Runs the automatic backup if it is due (D22). Never throws, never shows
  /// UI: a failure is recorded for the Backup screen.
  Future<void> autoBackupIfDue() async {
    try {
      await start();
      if (!state.signedIn || state.busy != BackupBusy.none) return;
      final now = _now();
      final due = BackupSchedule.isDue(
        now: now,
        lastSuccess: state.lastSuccess,
        lastFingerprint: _prefs.getString(LocalPrefKeys.backupFingerprint),
        currentFingerprint: await _repo.fingerprint(),
        hasUserData: await _repo.hasUserData(),
        lastFailure: state.lastErrorAt,
      );
      if (!due) return;
      await _exclusive(BackupBusy.backingUp, _upload);
    } on Object catch (e) {
      debugPrint('Auto backup skipped: $e');
    }
  }

  Future<void> _upload() async {
    try {
      final fingerprint = await _repo.fingerprint();
      final encoded = await _repo.export(appVersion: await ref.read(appVersionProvider.future), now: _now());
      final txCount = BackupSummary.liveTransactionCount(await _repo.dumpTables());
      await _store.upload(encoded, transactionCount: txCount);
      try {
        await _store.deleteOld();
      } on Object catch (e) {
        // The new backup is safe; old ones go next time.
        debugPrint('Old backup cleanup failed: $e');
      }
      final at = encoded.header.createdAt;
      await _prefs.setString(LocalPrefKeys.backupLastSuccess, '${at.millisecondsSinceEpoch}');
      await _prefs.setString(LocalPrefKeys.backupFingerprint, fingerprint);
      await _prefs.setString(LocalPrefKeys.backupLastError, '');
      if (ref.mounted) state = state.copyWith(lastSuccess: at, lastErrorCode: () => null, lastErrorAt: () => null);
    } on Object catch (e) {
      await _recordFailure(e);
      rethrow;
    }
  }

  Future<void> _recordFailure(Object e) async {
    final code = e is BackupException ? e.code : BackupError.driveError;
    final at = _now();
    await _prefs.setString(LocalPrefKeys.backupLastError, jsonEncode({'code': code, 'at': at.millisecondsSinceEpoch}));
    if (code == BackupError.notSignedIn) {
      await _account.signOut();
      await _prefs.setString(LocalPrefKeys.backupSignedIn, '');
    }
    if (ref.mounted) {
      state = state.copyWith(
        lastErrorCode: () => code,
        lastErrorAt: () => at,
        email: code == BackupError.notSignedIn ? () => null : null,
      );
    }
  }

  // ------------------------------------------------------------ restore

  Future<List<RemoteBackup>> listRemote() => _store.list();

  /// Downloads and validates a Drive backup. Nothing is changed yet.
  Future<PreparedRestore> prepare(String id) async {
    final bytes = await _store.download(id);
    final data = await _repo.prepare(bytes);
    return PreparedRestore(data, BackupSummary.of(data));
  }

  /// Replaces all data with [prepared], after saving a safety copy.
  Future<void> restore(PreparedRestore prepared) => _exclusive(BackupBusy.restoring, () async {
    final current = await _repo.export(appVersion: await ref.read(appVersionProvider.future), now: _now());
    await _safety.save(current);
    await _repo.restore(prepared.data);
    await _afterRestore();
  });

  /// Puts back the data from before the last restore.
  Future<void> undoRestore() => _exclusive(BackupBusy.restoring, () async {
    final bytes = await _safety.latest();
    if (bytes == null) throw const BackupException(BackupError.noSafetyBackup);
    await _repo.restore(await _repo.prepare(bytes));
    await _safety.dropLatest();
    await _afterRestore();
  });

  Future<void> _afterRestore() async {
    final prefs = _prefs;
    // Budget alerts start over for the restored budgets.
    await prefs.setString(LocalPrefKeys.budgetAlertLevels, '{}');
    // Forget a remembered account that no longer exists.
    try {
      final raw = prefs.getString(LocalPrefKeys.lastAccountId);
      if (raw != null) {
        final db = ref.read(appDatabaseProvider);
        final ids = (await db.select(db.accounts).get()).where((a) => a.deletedAt == null).map((a) => a.id).toSet();
        final map = (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>()
          ..removeWhere((_, id) => !ids.contains(id));
        await prefs.setString(LocalPrefKeys.lastAccountId, jsonEncode(map));
      }
    } on Object {
      await prefs.setString(LocalPrefKeys.lastAccountId, '{}');
    }
    await prefs.setString(LocalPrefKeys.backupRestoreOfferDone, '1');
    ref.read(notificationCoordinatorProvider.notifier).resync();
    bool hasSafety;
    try {
      hasSafety = await _safety.hasAny();
    } on Object {
      hasSafety = false;
    }
    if (ref.mounted) state = state.copyWith(hasSafety: hasSafety);
  }

  /// Tests: the newest safety copy.
  @visibleForTesting
  Future<Uint8List?> latestSafety() => _safety.latest();
}

/// Whether the fresh-install restore offer should show (once per install).
@riverpod
class RestoreOffer extends _$RestoreOffer {
  @override
  bool build() {
    final prefs = ref.watch(localPrefsProvider);
    if (prefs.getString(LocalPrefKeys.backupRestoreOfferDone) == '1') return false;
    final hasData = ref.watch(hasUserDataProvider).value;
    if (hasData == null) return false;
    if (hasData) {
      // Data exists: the offer is no longer needed on this install.
      Future.microtask(() => prefs.setString(LocalPrefKeys.backupRestoreOfferDone, '1'));
      return false;
    }
    return true;
  }

  Future<void> dismiss() async {
    await ref.read(localPrefsProvider).setString(LocalPrefKeys.backupRestoreOfferDone, '1');
    state = false;
  }
}
