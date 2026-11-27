import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/services/clock.dart';
import 'package:hisab/features/backup/data/backup_repository.dart';

import '../../helpers/test_db.dart';
import 'backup_helpers.dart';

/// Local only: the owner's real phone data, copied off the phone by hand.
/// Skipped where the file does not exist (CI, other machines). The file and
/// anything read from it never go into the repository.
final _ownerCopy = File('${Platform.environment['HOME']}/Documents/hisab-release/data-backup/2026-11-27_hisab.sqlite');

void main() {
  test(
    "owner's data survives export and restore unchanged",
    () async {
      // Work on a copy so the backed-up file is never touched.
      final tmp = Directory.systemTemp.createTempSync('hisab_owner_');
      final copy = _ownerCopy.copySync('${tmp.path}/hisab.sqlite');
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final real = AppDatabase(NativeDatabase(copy), clock: FixedClock(testNow));
      final fresh = await openTestDb();
      try {
        final srcRepo = BackupRepository(real);
        final dstRepo = BackupRepository(fresh);
        final before = await srcRepo.dumpTables();
        expect(before['transactions'], isNotEmpty);

        final encoded = await srcRepo.export(appVersion: 'test', now: testNow);
        await dstRepo.restore(await dstRepo.prepare(encoded.bytes));

        expect(await dstRepo.dumpTables(), before);
        expect(await balances(fresh), await balances(real));
      } finally {
        await real.close();
        await fresh.close();
        tmp.deleteSync(recursive: true);
      }
    },
    skip: _ownerCopy.existsSync() ? false : 'owner data copy not on this machine',
  );
}
