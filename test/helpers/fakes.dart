import 'dart:io';
import 'dart:typed_data';

import 'package:hisab/core/errors/app_exception.dart';
import 'package:hisab/core/notifications/notification_service.dart';
import 'package:hisab/features/backup/data/backup_store.dart';
import 'package:hisab/features/backup/data/google_account.dart';
import 'package:hisab/features/backup/data/safety_backups.dart';
import 'package:hisab/features/backup/domain/backup_file.dart';
import 'package:hisab/features/backup/domain/backup_schedule.dart';
import 'package:hisab/features/backup/domain/backup_summary.dart';
import 'package:hisab/features/voice/data/speech_input.dart';
import 'package:http/http.dart' as http;

typedef Notice = ({int id, String channel, String title, String body, String? payload, DateTime? at});

/// Records notifications instead of showing them.
class RecordingNotifications implements NotificationService {
  bool permitted = true;
  int permissionRequests = 0;
  final List<Notice> shown = [];
  final Map<int, Notice> scheduled = {};

  @override
  Future<void> initialize({required void Function(String? payload) onTap}) async {}

  @override
  Future<String?> launchPayload() async => null;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permitted;
  }

  @override
  Future<void> show({
    required int id,
    required NoticeChannel channel,
    required String title,
    required String body,
    String? payload,
  }) async =>
      shown.add((id: id, channel: channel.id, title: title, body: body, payload: payload, at: null));

  @override
  Future<void> schedule({
    required int id,
    required NoticeChannel channel,
    required DateTime at,
    required String title,
    required String body,
    String? payload,
  }) async =>
      scheduled[id] = (id: id, channel: channel.id, title: title, body: body, payload: payload, at: at);

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
}

/// Speech that "hears" [script] (or fails with [failure]).
class ScriptedSpeech implements SpeechInput {
  ScriptedSpeech({this.script = '', this.failure});

  String script;
  SpeechFailure? failure;
  String? lastLocale;

  @override
  Future<SpeechFailure?> initialize() async => failure;

  @override
  Future<String?> localeFor(String languageCode) async => languageCode == 'bn' ? 'bn_BD' : 'en_US';

  @override
  Future<void> listen({
    required String? localeId,
    required void Function(String text, bool isFinal) onText,
    required void Function(SpeechFailure? failure) onDone,
  }) async {
    lastLocale = localeId;
    onText(script, true);
    onDone(null);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

/// A Google account that signs in without any platform UI.
class FakeGoogleAccount implements GoogleAccount {
  FakeGoogleAccount({this.signedInEmail, this.signInEmail = 'owner@example.com', this.signInError});

  /// Who is signed in silently (a previous session), or null.
  String? signedInEmail;
  String signInEmail;

  /// Code thrown by [signIn], if any.
  String? signInError;
  String? _email;

  @override
  String? get email => _email;

  @override
  Future<String?> signInSilently() async => _email = signedInEmail;

  @override
  Future<String> signIn() async {
    if (signInError != null) throw BackupException(signInError!);
    signedInEmail = signInEmail;
    return _email = signInEmail;
  }

  @override
  Future<void> signOut() async => _email = signedInEmail = null;

  @override
  Future<http.Client> authClient({bool interactive = false}) async {
    if (_email == null) throw const BackupException(BackupError.notSignedIn);
    return http.Client();
  }
}

/// Drive in memory. [foreign] files were not made by the app (no
/// `hisab_format`), so the app must never list or delete them.
class FakeBackupStore implements BackupStore {
  final Map<String, ({RemoteBackup meta, Uint8List bytes})> files = {};
  final Set<String> foreign = {};

  /// When set, every call fails with this code (e.g. no internet).
  String? failWith;
  int uploads = 0;

  void _maybeFail() {
    if (failWith != null) throw BackupException(failWith!);
  }

  void addForeign(String id) => foreign.add(id);

  @override
  Future<List<RemoteBackup>> list() async {
    _maybeFail();
    return files.values.map((f) => f.meta).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<RemoteBackup> upload(EncodedBackup backup, {required int transactionCount}) async {
    _maybeFail();
    uploads++;
    final id = 'file-$uploads';
    final meta = RemoteBackup(
      id: id,
      name: BackupCodec.fileName(backup.header.createdAt),
      createdAt: backup.header.createdAt,
      transactionCount: transactionCount,
      schemaVersion: backup.header.schemaVersion,
      sizeBytes: backup.bytes.length,
    );
    files[id] = (meta: meta, bytes: backup.bytes);
    return meta;
  }

  /// Puts a ready-made backup on "Drive" (as if from another phone).
  void put(String id, EncodedBackup backup, {int? transactionCount}) => files[id] = (
    meta: RemoteBackup(
      id: id,
      name: BackupCodec.fileName(backup.header.createdAt),
      createdAt: backup.header.createdAt,
      transactionCount: transactionCount,
      schemaVersion: backup.header.schemaVersion,
    ),
    bytes: backup.bytes,
  );

  @override
  Future<Uint8List> download(String id) async {
    _maybeFail();
    return files[id]!.bytes;
  }

  @override
  Future<int> deleteOld({int keep = BackupRetention.keepOnDrive}) async {
    _maybeFail();
    final old = BackupRetention.toDelete(await list(), (b) => b.createdAt, keep: keep);
    for (final b in old) {
      files.remove(b.id);
    }
    return old.length;
  }
}

/// Safety copies in a fresh temporary folder.
SafetyBackups tempSafetyBackups() {
  final dir = Directory.systemTemp.createTempSync('hisab_safety_');
  return SafetyBackups(() async => dir);
}
