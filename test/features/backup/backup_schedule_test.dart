import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hisab/features/backup/data/backup_store.dart';
import 'package:hisab/features/backup/domain/backup_file.dart';
import 'package:hisab/features/backup/domain/backup_schedule.dart';

import '../../helpers/fakes.dart';

void main() {
  final now = DateTime(2026, 11, 27, 10);

  group('BackupSchedule.isDue', () {
    bool due({
      DateTime? lastSuccess,
      String? lastFp = 'old',
      String fp = 'new',
      bool hasData = true,
      DateTime? lastFailure,
    }) =>
        BackupSchedule.isDue(
          now: now,
          lastSuccess: lastSuccess,
          lastFingerprint: lastFp,
          currentFingerprint: fp,
          hasUserData: hasData,
          lastFailure: lastFailure,
        );

    test('never backed up and there is data: due', () => expect(due(lastFp: null), isTrue));
    test('no user data (fresh install): not due', () => expect(due(lastFp: null, hasData: false), isFalse));
    test('23 h after the last backup: not due', () {
      expect(due(lastSuccess: now.subtract(const Duration(hours: 23))), isFalse);
    });
    test('24 h after the last backup with changes: due', () {
      expect(due(lastSuccess: now.subtract(const Duration(hours: 24))), isTrue);
    });
    test('unchanged data is never backed up again', () {
      expect(due(lastSuccess: now.subtract(const Duration(days: 9)), lastFp: 'same', fp: 'same'), isFalse);
    });
    test('a failure 10 minutes ago waits; one 2 h ago retries', () {
      final old = now.subtract(const Duration(days: 2));
      expect(due(lastSuccess: old, lastFailure: now.subtract(const Duration(minutes: 10))), isFalse);
      expect(due(lastSuccess: old, lastFailure: now.subtract(const Duration(hours: 2))), isTrue);
    });
    test('a failure older than the last success does not block', () {
      final success = now.subtract(const Duration(days: 2));
      expect(due(lastSuccess: success, lastFailure: success.subtract(const Duration(minutes: 1))), isTrue);
    });
  });

  test('retention keeps the newest N', () {
    final days = [for (var i = 1; i <= 13; i++) DateTime(2026, 11, i)]..shuffle();
    final gone = BackupRetention.toDelete(days, (d) => d, keep: 10)..sort();
    expect(gone, [DateTime(2026, 11, 1), DateTime(2026, 11, 2), DateTime(2026, 11, 3)]);
    expect(BackupRetention.toDelete(days.take(5).toList(), (d) => d, keep: 10), isEmpty);
  });

  test('store keeps the newest 10 and never touches files it did not make', () async {
    final store = FakeBackupStore()..addForeign('someone-elses-file');
    final tables = <String, List<Map<String, Object?>>>{'t': []};
    for (var i = 0; i < 12; i++) {
      await store.upload(
        BackupCodec.encode(tables, schemaVersion: 4, appVersion: 'x', createdAt: DateTime(2026, 11, 1 + i)),
        transactionCount: i,
      );
    }
    expect(await store.deleteOld(), 2);
    final left = await store.list();
    expect(left, hasLength(10));
    expect(left.first.createdAt, DateTime(2026, 11, 12));
    expect(left.last.createdAt, DateTime(2026, 11, 3));
    expect(store.foreign, contains('someone-elses-file'));
  });

  test('Drive errors map to backup error codes', () {
    String code(Object e) => DriveBackupStore.mapDriveError(e).code;
    expect(code(const SocketException('no route')), BackupError.network);
    expect(code(TimeoutException('slow')), BackupError.network);
    expect(
      code(drive.DetailedApiRequestError(403, "The user's Drive storage quota has been exceeded.")),
      BackupError.driveQuota,
    );
    expect(code(drive.DetailedApiRequestError(401, 'expired')), BackupError.notSignedIn);
    expect(code(drive.DetailedApiRequestError(500, 'oops')), BackupError.driveError);
  });
}
