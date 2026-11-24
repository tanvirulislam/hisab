import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';
import 'loans_dao.dart';

part 'accounts_dao.g.dart';

/// An account row plus its derived balance in paisa.
typedef AccountWithBalanceRow = ({AccountRow account, int balancePaisa});

@DriftAccessor(tables: [Accounts, Transactions, RecurringRules, LoanEntries])
class AccountsDao extends DatabaseAccessor<AppDatabase>
    with _$AccountsDaoMixin {
  AccountsDao(super.attachedDatabase);

  /// Signed effect of a transaction row on its account's balance (D4–D6).
  /// The single definition of balance arithmetic. Reuse it, never copy it.
  static const String signedAmountSql =
      "CASE WHEN t.type IN ('income', 'refund', 'transfer_in') THEN t.amount_paisa "
      "WHEN t.type IN ('expense', 'transfer_out') THEN -t.amount_paisa "
      'ELSE 0 END';

  /// Accounts in [workspaceIds] with live balances:
  /// opening balance + Σ signed amounts of transactions that are not deleted
  /// + Σ signed amounts of live loan entries on the account (D16).
  ///
  /// An empty [workspaceIds] returns nothing, so a query never runs without
  /// a workspace filter (D9).
  Stream<List<AccountWithBalanceRow>> watchWithBalances(
    List<String> workspaceIds, {
    bool activeOnly = false,
  }) {
    if (workspaceIds.isEmpty) return Stream.value(const []);
    final placeholders = List.filled(workspaceIds.length, '?').join(', ');
    final query = customSelect(
      'SELECT a.*, a.opening_balance_paisa '
      '+ COALESCE((SELECT SUM($signedAmountSql) FROM transactions t '
      'WHERE t.account_id = a.id AND t.deleted_at IS NULL), 0) '
      '+ COALESCE((SELECT SUM(${LoansDao.signedAmountSql}) FROM loan_entries l '
      'WHERE l.account_id = a.id AND l.deleted_at IS NULL), 0) AS balance_paisa '
      'FROM accounts a '
      'WHERE a.workspace_id IN ($placeholders) AND a.deleted_at IS NULL '
      '${activeOnly ? 'AND a.is_active = 1 ' : ''}'
      'ORDER BY a.sort_order, a.created_at',
      variables: [for (final id in workspaceIds) Variable.withString(id)],
      readsFrom: {accounts, transactions, loanEntries},
    );
    return query.watch().asyncMap(
      (rows) => Future.wait(
        rows.map((row) async => (
          account: await accounts.mapFromRow(row),
          balancePaisa: row.read<int>('balance_paisa'),
        )),
      ),
    );
  }

  /// Net money moved into savings accounts by transfers dated in [from]..[to]
  /// (yyyymmdd): transfers in minus transfers out, on 'savings' accounts only.
  /// A transfer between two savings accounts cancels out (D17).
  Stream<int> watchSavingsMoved(List<String> workspaceIds, int from, int to) {
    if (workspaceIds.isEmpty) return Stream.value(0);
    final placeholders = List.filled(workspaceIds.length, '?').join(', ');
    return customSelect(
      "SELECT COALESCE(SUM(CASE WHEN t.type = 'transfer_in' THEN t.amount_paisa "
      'ELSE -t.amount_paisa END), 0) AS moved '
      'FROM transactions t JOIN accounts a ON a.id = t.account_id '
      "WHERE a.type = 'savings' AND a.deleted_at IS NULL "
      "AND t.type IN ('transfer_in', 'transfer_out') AND t.deleted_at IS NULL "
      'AND a.workspace_id IN ($placeholders) AND t.local_date BETWEEN ? AND ?',
      variables: [
        for (final id in workspaceIds) Variable.withString(id),
        Variable.withInt(from),
        Variable.withInt(to),
      ],
      readsFrom: {accounts, transactions},
    ).watchSingle().map((r) => r.read<int>('moved'));
  }

  Future<AccountRow?> findById(String id) =>
      (select(accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Every account, including inactive and deleted ones.
  Future<List<AccountRow>> getAll() => select(accounts).get();

  Future<void> insertRow(AccountsCompanion row) => into(accounts).insert(row);

  Future<void> updateRow(String id, AccountsCompanion row) =>
      (update(accounts)..where((a) => a.id.equals(id))).write(row);

  Future<int> countRecurringReferences(String accountId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM recurring_rules WHERE (account_id = ?1 OR counter_account_id = ?1) '
      'AND deleted_at IS NULL',
      variables: [Variable.withString(accountId)],
      readsFrom: {recurringRules},
    ).getSingle();
    return row.read<int>('n');
  }

  Future<int> maxSortOrder(String workspaceId) async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(sort_order), 0) AS m FROM accounts WHERE workspace_id = ?',
      variables: [Variable.withString(workspaceId)],
      readsFrom: {accounts},
    ).getSingle();
    return row.read<int>('m');
  }
}
