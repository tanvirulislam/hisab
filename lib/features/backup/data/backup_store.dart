import 'dart:async';
import 'dart:io' show SocketException, HandshakeException, HttpException;
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../../core/errors/app_exception.dart';
import '../../../core/services/local_prefs.dart';
import '../domain/backup_file.dart';
import '../domain/backup_schedule.dart';
import '../domain/backup_summary.dart';
import 'drive_config.dart';
import 'google_account.dart';

/// Where backups are kept (D22: the owner's Google Drive only). Behind an
/// interface so tests use a fake.
abstract interface class BackupStore {
  /// The app's backups, newest first.
  Future<List<RemoteBackup>> list();

  Future<RemoteBackup> upload(EncodedBackup backup, {required int transactionCount});

  Future<Uint8List> download(String id);

  /// Deletes the app's backups beyond the newest [keep]. Returns how many.
  Future<int> deleteOld({int keep = BackupRetention.keepOnDrive});
}

/// Google Drive with the `drive.file` scope: the app sees only files it
/// made, kept in a "Hisab Backup" folder in My Drive.
class DriveBackupStore implements BackupStore {
  DriveBackupStore(this._account, this._prefs, {this.timeout = const Duration(seconds: 60)});

  final GoogleAccount _account;
  final LocalPrefs _prefs;
  final Duration timeout;

  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _fileMime = 'application/gzip';
  static const _fields = 'id,name,createdTime,size,appProperties';

  Future<T> _call<T>(Future<T> Function(drive.DriveApi api) body) async {
    final client = await _account.authClient();
    try {
      return await body(drive.DriveApi(client)).timeout(timeout);
    } on BackupException {
      rethrow;
    } on Object catch (e) {
      throw mapDriveError(e);
    } finally {
      client.close();
    }
  }

  /// Turns transport and API errors into [BackupException]s.
  static BackupException mapDriveError(Object e) {
    if (e is SocketException ||
        e is TimeoutException ||
        e is http.ClientException ||
        e is HandshakeException ||
        e is HttpException) {
      return BackupException(BackupError.network, '$e');
    }
    if (e is drive.DetailedApiRequestError) {
      final reasons = e.errors.map((d) => d.reason).toSet();
      final storageFull = e.status == 403 && (e.message ?? '').toLowerCase().contains('storage quota');
      if (reasons.contains('storageQuotaExceeded') || storageFull) {
        return BackupException(BackupError.driveQuota, '$e');
      }
      if (e.status == 401) return BackupException(BackupError.notSignedIn, '$e');
    }
    return BackupException(BackupError.driveError, '$e');
  }

  Future<String> _folderId(drive.DriveApi api) async {
    final cached = _prefs.getString(LocalPrefKeys.backupFolderId);
    if (cached != null && cached.isNotEmpty) {
      try {
        final f = await api.files.get(cached, $fields: 'id,trashed') as drive.File;
        if (f.trashed != true) return cached;
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    final found = await api.files.list(
      q: "name = '$kDriveFolderName' and mimeType = '$_folderMime' and trashed = false and 'root' in parents",
      spaces: 'drive',
      $fields: 'files(id)',
      pageSize: 1,
    );
    final id = found.files?.firstOrNull?.id ??
        (await api.files.create(
          drive.File()
            ..name = kDriveFolderName
            ..mimeType = _folderMime
            ..parents = ['root'],
          $fields: 'id',
        )).id!;
    await _prefs.setString(LocalPrefKeys.backupFolderId, id);
    return id;
  }

  static RemoteBackup? _toRemote(drive.File f) {
    final p = f.appProperties ?? const {};
    if (p['hisab_format'] == null || f.id == null) return null;
    return RemoteBackup(
      id: f.id!,
      name: f.name ?? '',
      createdAt: (DateTime.tryParse(p['created_at'] ?? '') ?? f.createdTime ?? DateTime(1970)).toLocal(),
      transactionCount: int.tryParse(p['tx_count'] ?? ''),
      schemaVersion: int.tryParse(p['schema'] ?? ''),
      sizeBytes: int.tryParse(f.size ?? ''),
    );
  }

  Future<List<RemoteBackup>> _list(drive.DriveApi api) async {
    final folder = await _folderId(api);
    final out = <RemoteBackup>[];
    String? page;
    do {
      final res = await api.files.list(
        q: "'$folder' in parents and trashed = false and mimeType = '$_fileMime'",
        spaces: 'drive',
        orderBy: 'createdTime desc',
        pageSize: 100,
        pageToken: page,
        $fields: 'nextPageToken,files($_fields)',
      );
      out.addAll((res.files ?? const []).map(_toRemote).nonNulls);
      page = res.nextPageToken;
    } while (page != null);
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  @override
  Future<List<RemoteBackup>> list() => _call(_list);

  @override
  Future<RemoteBackup> upload(EncodedBackup backup, {required int transactionCount}) => _call((api) async {
    final folder = await _folderId(api);
    final created = await api.files.create(
      drive.File()
        ..name = BackupCodec.fileName(backup.header.createdAt)
        ..mimeType = _fileMime
        ..parents = [folder]
        ..appProperties = RemoteBackup.appPropertiesFor(backup.header, transactionCount),
      uploadMedia: drive.Media(Stream.value(backup.bytes), backup.bytes.length, contentType: _fileMime),
      $fields: _fields,
    );
    return _toRemote(created)!;
  });

  @override
  Future<Uint8List> download(String id) => _call((api) async {
    final media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  });

  @override
  Future<int> deleteOld({int keep = BackupRetention.keepOnDrive}) => _call((api) async {
    final old = BackupRetention.toDelete(await _list(api), (b) => b.createdAt, keep: keep);
    for (final b in old) {
      await api.files.delete(b.id);
    }
    return old.length;
  });
}
