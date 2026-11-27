import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/errors/app_exception.dart';
import 'package:hisab/features/backup/domain/backup_file.dart';

import '../../helpers/test_db.dart';

Matcher throwsBackup(String code) =>
    throwsA(isA<BackupException>().having((e) => e.code, 'code', code));

/// Fills [db] with one of everything: a second account, expense, income,
/// a refund, a transfer pair, a soft-deleted expense, a subcategory, a
/// budget, a person with a loan and a part repayment, and settings.
Future<void> seedEverything(AppDatabase db) async {
  final ws = (await workspaceOfType(db, 'personal')).id;
  final cash = (await firstAccountOf(db, ws)).id;
  final bkash = await addAccount(db, ws);
  final food = await categoryByKey(db, 'grocery');
  final salary = (await (db.select(db.categories)..where((c) => c.type.equals('income'))).get()).first;
  final now = testNow.millisecondsSinceEpoch;

  await db.into(db.categories).insert(CategoriesCompanion.insert(
      id: 'sub-snacks', parentId: Value(food.id), type: 'expense', name: 'Snacks', icon: 'cookie',
      color: 0xFF00AA00, createdAt: now, updatedAt: now));
  await insertTxn(db, id: 'e1', workspaceId: ws, accountId: cash, type: 'expense', amountPaisa: 25000, categoryId: food.id);
  await insertTxn(db, id: 'i1', workspaceId: ws, accountId: bkash, type: 'income', amountPaisa: 5000000, categoryId: salary.id);
  await insertTxn(db, id: 'r1', workspaceId: ws, accountId: cash, type: 'refund', amountPaisa: 5000, categoryId: food.id, refundOfId: 'e1');
  await insertTxn(db, id: 'e2', workspaceId: ws, accountId: cash, type: 'expense', amountPaisa: 100, categoryId: food.id, deletedAt: now);
  await insertTxn(db, id: 't-out', workspaceId: ws, accountId: bkash, type: 'transfer_out', amountPaisa: 100000,
      transferGroupId: 'g1', counterAccountId: cash);
  await insertTxn(db, id: 't-in', workspaceId: ws, accountId: cash, type: 'transfer_in', amountPaisa: 100000,
      transferGroupId: 'g1', counterAccountId: bkash);
  await db.into(db.budgets).insert(BudgetsCompanion.insert(
      id: 'b1', workspaceId: ws, categoryId: food.id, amountPaisa: 1000000, year: 2026, month: 11,
      createdAt: now, updatedAt: now));
  await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'p1', workspaceId: ws, name: 'Karim', createdAt: now, updatedAt: now));
  await db.into(db.loanEntries).insert(LoanEntriesCompanion.insert(
      id: 'l1', workspaceId: ws, personId: 'p1', accountId: Value(cash), kind: 'lent', amountPaisa: 50000,
      localDate: 20261120, createdAt: now, updatedAt: now));
  await db.into(db.loanEntries).insert(LoanEntriesCompanion.insert(
      id: 'l2', workspaceId: ws, personId: 'p1', accountId: Value(cash), kind: 'repaid_to_me', amountPaisa: 20000,
      localDate: 20261121, createdAt: now, updatedAt: now));
  await db.settingsDao.put('month_start_day', '25', now);
}

/// Re-encodes [bytes] after [edit] changed its JSON, keeping the stored
/// header (so the checksum no longer matches) unless [rehash] is set.
List<int> tamper(List<int> bytes, void Function(Map<String, dynamic> json) edit, {bool rehash = false}) {
  final json = jsonDecode(utf8.decode(GZipCodec().decode(bytes))) as Map<String, dynamic>;
  edit(json);
  if (rehash) {
    final tables = (json['tables'] as Map).map((k, v) => MapEntry(
        k as String, [for (final r in v as List) (r as Map).cast<String, Object?>()]));
    final header = json['header'] as Map<String, dynamic>;
    header['sha256'] = BackupCodec.checksumOf(tables);
    header['counts'] = {for (final e in tables.entries) e.key: e.value.length};
  }
  return GZipCodec().encode(utf8.encode(jsonEncode(json)));
}

/// Account id → balance in paisa, computed by the app's own query.
Future<Map<String, int>> balances(AppDatabase db) async {
  final ws = (await db.select(db.workspaces).get()).map((w) => w.id).toList();
  final rows = await db.accountsDao.watchWithBalances(ws).first;
  return {for (final r in rows) r.account.id: r.balancePaisa};
}

