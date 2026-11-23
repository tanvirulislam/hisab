import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/money.dart';
import '../domain/account.dart';
import '../domain/account_repository.dart';

class DriftAccountRepository implements AccountRepository {
  DriftAccountRepository(this._db);

  final AppDatabase _db;

  static const int maxNameLength = 60;

  @override
  Stream<List<AccountBalance>> watchAccountBalances(
    List<String> workspaceIds, {
    bool activeOnly = false,
  }) => _db.accountsDao
      .watchWithBalances(workspaceIds, activeOnly: activeOnly)
      .map(
        (rows) => [
          for (final r in rows)
            AccountBalance(
              account: toDomain(r.account),
              balance: Money(r.balancePaisa),
            ),
        ],
      );

  static Account toDomain(AccountRow row) => Account(
    id: row.id,
    workspaceId: row.workspaceId,
    name: row.name,
    type: AccountType.fromDb(row.type),
    openingBalance: Money(row.openingBalancePaisa),
    isActive: row.isActive,
    sortOrder: row.sortOrder,
  );

  String _validName(String name) {
    final n = name.trim();
    if (n.isEmpty || n.length > maxNameLength) {
      throw const ValidationException(AccountError.nameInvalid);
    }
    return n;
  }

  void _checkBalance(Money m) {
    if (m.paisa.abs() > Money.maxInputPaisa) {
      throw const ValidationException(AccountError.balanceInvalid);
    }
  }

  Future<void> _checkUnique(String name, String workspaceId, {String? excludeId}) async {
    final lower = name.toLowerCase();
    final all = await _db.accountsDao.getAll();
    final clash = all.any((a) =>
        a.deletedAt == null &&
        a.id != excludeId &&
        a.workspaceId == workspaceId &&
        a.name.toLowerCase() == lower);
    if (clash) throw const ValidationException(AccountError.nameDuplicate);
  }

  Future<AccountRow> _require(String id) async {
    final row = await _db.accountsDao.findById(id);
    if (row == null || row.deletedAt != null) {
      throw const ValidationException(AccountError.notFound);
    }
    return row;
  }

  @override
  Future<String> createAccount(AccountDraft d) => _db.transaction(() async {
    final name = _validName(d.name);
    _checkBalance(d.openingBalance);
    final ws = await _db.workspacesDao.findById(d.workspaceId);
    if (ws == null || ws.deletedAt != null) {
      throw const ValidationException(AccountError.notFound, 'workspace');
    }
    await _checkUnique(name, d.workspaceId);
    final id = _db.ids.newId();
    final now = _db.clock.nowMillis();
    await _db.accountsDao.insertRow(AccountsCompanion.insert(
      id: id,
      workspaceId: d.workspaceId,
      name: name,
      type: d.type.dbValue,
      openingBalancePaisa: Value(d.openingBalance.paisa),
      sortOrder: Value(await _db.accountsDao.maxSortOrder(d.workspaceId) + 1),
      createdAt: now,
      updatedAt: now,
    ));
    return id;
  });

  @override
  Future<void> updateAccount(
    String id, {
    required String name,
    required AccountType type,
    required Money openingBalance,
  }) => _db.transaction(() async {
    final row = await _require(id);
    final n = _validName(name);
    _checkBalance(openingBalance);
    await _checkUnique(n, row.workspaceId, excludeId: id);
    await _db.accountsDao.updateRow(id, AccountsCompanion(
      name: Value(n),
      type: Value(type.dbValue),
      openingBalancePaisa: Value(openingBalance.paisa),
      updatedAt: Value(_db.clock.nowMillis()),
    ));
  });

  @override
  Future<void> setActive(String id, {required bool active}) => _db.transaction(() async {
    await _require(id);
    await _db.accountsDao.updateRow(id, AccountsCompanion(
      isActive: Value(active),
      updatedAt: Value(_db.clock.nowMillis()),
    ));
  });

  @override
  Future<int> usageCount(String id) async =>
      await _db.transactionsDao.countReferencingAccount(id) +
      await _db.accountsDao.countRecurringReferences(id) +
      await _db.loansDao.countReferencingAccount(id);

  @override
  Future<void> deleteAccount(String id) => _db.transaction(() async {
    await _require(id);
    if (await usageCount(id) > 0) throw const ConflictException(AccountError.inUse);
    final now = _db.clock.nowMillis();
    await _db.accountsDao.updateRow(id, AccountsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  });
}
