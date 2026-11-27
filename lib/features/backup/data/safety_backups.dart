import 'dart:io';
import 'dart:typed_data';

import '../domain/backup_file.dart';
import '../domain/backup_schedule.dart';

/// Copies of the data taken right before a restore, so the restore can be
/// undone (D22). Kept on the device in `<documents>/safety/`, newest 3 only.
/// These are not backups: they never leave the phone.
class SafetyBackups {
  SafetyBackups(this._dir);

  /// Resolves the folder lazily (path_provider is async).
  final Future<Directory> Function() _dir;

  Future<Directory> _folder() async {
    final d = await _dir();
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }

  Future<List<File>> _files() async {
    final d = await _folder();
    final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.hisab')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> save(EncodedBackup backup) async {
    final d = await _folder();
    final name = 'safety-${backup.header.createdAt.microsecondsSinceEpoch.toString().padLeft(20, '0')}.hisab';
    await File('${d.path}/$name').writeAsBytes(backup.bytes, flush: true);
    // Names sort by time, newest first.
    for (final f in (await _files()).skip(BackupRetention.keepSafety)) {
      await f.delete();
    }
  }

  Future<bool> hasAny() async => (await _files()).isNotEmpty;

  Future<int> count() async => (await _files()).length;

  /// The newest safety backup, or null.
  Future<Uint8List?> latest() async {
    final files = await _files();
    return files.isEmpty ? null : files.first.readAsBytes();
  }

  /// Removes the newest one (after it was restored).
  Future<void> dropLatest() async {
    final files = await _files();
    if (files.isNotEmpty) await files.first.delete();
  }
}
