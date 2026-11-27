import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/features/backup/data/backup_repository.dart';
import 'package:hisab/features/backup/domain/backup_file.dart';
import 'package:hisab/features/backup/domain/backup_summary.dart';

import '../../helpers/test_db.dart';
import 'backup_helpers.dart';

void main() {
  late AppDatabase src, dst;
  late BackupRepository srcRepo, dstRepo;

  setUp(() async {
    src = await openTestDb();
    dst = await openTestDb();
    srcRepo = BackupRepository(src);
    dstRepo = BackupRepository(dst);
    await seedEverything(src);
  });
  tearDown(() async {
    await src.close();
    await dst.close();
  });

  Future<List<int>> exported() async => (await srcRepo.export(appVersion: 'test', now: testNow)).bytes;

  test('the table list matches tables.dart and puts parents first', () async {
    final names = (await srcRepo.schema()).tables.map((t) => t.name).toList();
    expect(names.toSet(), {for (final t in src.allTables) t.actualTableName});
    expect(names.indexOf('workspaces'), lessThan(names.indexOf('accounts')));
    expect(names.indexOf('recurring_rules'), lessThan(names.indexOf('transactions')));
    expect(names.indexOf('persons'), lessThan(names.indexOf('loan_entries')));
    expect(names, contains('app_settings'));
  });

  test('round trip: export, restore into another DB, every table identical', () async {
    final before = await srcRepo.dumpTables();
    final data = await dstRepo.prepare(await exported());
    expect(data.header.schemaVersion, 4);
    expect(data.header.counts['transactions'], 6);
    await dstRepo.restore(data);
    expect(await dstRepo.dumpTables(), before);
    expect(await balances(dst), await balances(src));
    // Settings travel with the data (D15 month start day).
    expect((await dst.settingsDao.getAll())['month_start_day'], '25');
  });

  test('summary counts what the user sees, a transfer once', () async {
    final s = BackupSummary.of(await dstRepo.prepare(await exported()));
    expect(s.transactions, 4); // e1, i1, r1, one transfer; e2 is deleted
    expect(s.accounts, 2);
    expect(s.budgets, 1);
    expect(s.persons, 1);
    expect(s.loanEntries, 2);
    expect(s.createdAt, testNow);
  });

  test('a changed value with the old checksum is refused', () async {
    final bad = tamper(await exported(), (j) => (j['tables']['transactions'] as List).first['amount_paisa'] = 1);
    expect(() => dstRepo.prepare(bad), throwsBackup(BackupError.checksumMismatch));
  });

  test('a flipped byte is refused', () async {
    final bytes = [...await exported()];
    bytes[bytes.length ~/ 2] ^= 0xFF;
    await expectLater(
      dstRepo.prepare(bytes),
      throwsA(isA<Object>().having((e) => '$e', 'error', anyOf(contains(BackupError.corruptFile), contains(BackupError.checksumMismatch)))),
    );
  });

  test('truncated or non-gzip files are corrupt', () async {
    final bytes = await exported();
    expect(() => dstRepo.prepare(bytes.sublist(0, bytes.length ~/ 2)), throwsBackup(BackupError.corruptFile));
    expect(() => dstRepo.prepare('hello'.codeUnits), throwsBackup(BackupError.corruptFile));
    expect(() => dstRepo.prepare(GZipCodec().encode('[1,2]'.codeUnits)), throwsBackup(BackupError.corruptFile));
  });

  test('schema 5 is too new, schema 3 too old, format 2 unknown', () async {
    final tables = await srcRepo.dumpTables();
    List<int> withSchema(int v) =>
        BackupCodec.encode(tables, schemaVersion: v, appVersion: 'x', createdAt: testNow).bytes;
    expect(() => dstRepo.prepare(withSchema(5)), throwsBackup(BackupError.tooNew));
    expect(() => dstRepo.prepare(withSchema(3)), throwsBackup(BackupError.tooOld));
    final v2 = tamper(withSchema(4), (j) => j['header']['format_version'] = 2);
    expect(() => dstRepo.prepare(v2), throwsBackup(BackupError.unknownFormat));
  });

  group('invalid data is refused before anything is written', () {
    Future<void> expectInvalid(void Function(Map<String, dynamic> tables) edit) async {
      final bad = tamper(await exported(), (j) => edit(j['tables'] as Map<String, dynamic>), rehash: true);
      await expectLater(dstRepo.prepare(bad), throwsBackup(BackupError.invalidData));
    }

    List<dynamic> rows(Map<String, dynamic> t, String name) => t[name] as List;
    Map<String, dynamic> row(Map<String, dynamic> t, String name, String id) =>
        rows(t, name).cast<Map<String, dynamic>>().firstWhere((r) => r['id'] == id);

    test('dangling foreign key', () => expectInvalid((t) => row(t, 'transactions', 'e1')['account_id'] = 'nope'));
    test('broken transfer pair', () => expectInvalid((t) => rows(t, 'transactions').removeWhere((r) => r['id'] == 't-in')));
    test('transfer legs disagree', () => expectInvalid((t) => row(t, 'transactions', 't-in')['amount_paisa'] = 1));
    test('over-repayment', () => expectInvalid((t) => row(t, 'loan_entries', 'l2')['amount_paisa'] = 60000));
    test('two workspaces', () => expectInvalid((t) {
      final copy = Map<String, dynamic>.of(rows(t, 'workspaces').first as Map<String, dynamic>)..['id'] = 'other';
      rows(t, 'workspaces').add(copy);
    }));
    test('missing required column', () => expectInvalid((t) => row(t, 'accounts', 'bkash').remove('name')));
    test('unknown column', () => expectInvalid((t) => row(t, 'accounts', 'bkash')['colour'] = 1));
    test('missing table', () => expectInvalid((t) => t.remove('persons')));
    test('duplicate key', () => expectInvalid((t) => rows(t, 'persons').add(Map.of(rows(t, 'persons').first as Map))));
  });

  test('a failure in the middle of a restore leaves the old data intact', () async {
    final before = await dstRepo.dumpTables();
    final data = await dstRepo.prepare(await exported());
    final faulty = BackupRepository(dst, faultAfterTable: 'transactions');
    await expectLater(faulty.restore(data), throwsStateError);
    expect(await dstRepo.dumpTables(), before);
  });

  test('fingerprint changes with the data', () async {
    final a = await srcRepo.fingerprint();
    expect(await srcRepo.fingerprint(), a);
    await src.settingsDao.put('theme', 'dark', testNow.millisecondsSinceEpoch + 1);
    expect(await srcRepo.fingerprint(), isNot(a));
  });

  test('user data: seeded categories and accounts do not count', () async {
    expect(await dstRepo.hasUserData(), isFalse);
    expect(await srcRepo.hasUserData(), isTrue);
  });

  test('file name', () {
    expect(BackupCodec.fileName(DateTime(2026, 11, 27, 9, 5, 3)), 'hisab-backup-20261127-090503.hisab');
  });
}
