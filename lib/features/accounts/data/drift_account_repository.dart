import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../domain/account.dart';
import '../domain/account_repository.dart';

class DriftAccountRepository implements AccountRepository {
  DriftAccountRepository(this._db);

  final AppDatabase _db;

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
}
