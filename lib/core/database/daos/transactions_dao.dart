import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'transactions_dao.g.dart';

/// SQL-level history parameters, built by the repository from a
/// `HistoryQuery`.
class HistorySqlParams {
  const HistorySqlParams({
    required this.workspaceIds,
    this.dbTypes = const {},
    this.categoryId,
    this.subcategoryId,
    this.accountId,
    this.fromDate,
    this.toDate,
    this.searchLike,
    this.searchCategoryIds = const [],
    this.limit = 50,
  });

  final List<String> workspaceIds;

  /// Empty = all types.
  final Set<String> dbTypes;
  final String? categoryId;
  final String? subcategoryId;
  final String? accountId;
  final int? fromDate;
  final int? toDate;

  /// Already escaped LIKE pattern (e.g. `%fish%`), matched against the
  /// description with ESCAPE '\'.
  final String? searchLike;

  /// Categories whose (translated) names match the search text.
  final List<String> searchCategoryIds;
  final int limit;
}

typedef HistoryRows = ({List<TransactionRow> rows, int totalCount});

@DriftAccessor(tables: [Transactions, Categories, Accounts, Workspaces])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.attachedDatabase);

  static const String _order = 't.local_date DESC, t.occurred_at DESC, t.id DESC';

  // ---------------------------------------------------------------- reads

  Future<TransactionRow?> findById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<TransactionRow>> findByIds(List<String> ids) =>
      (select(transactions)..where((t) => t.id.isIn(ids))).get();

  /// Transfer rows of a group that are not deleted.
  Future<List<TransactionRow>> findByGroup(String groupId) => (select(transactions)
        ..where((t) => t.transferGroupId.equals(groupId) & t.deletedAt.isNull()))
      .get();

  Future<List<TransactionRow>> refundsOf(String expenseId) => (select(transactions)
        ..where((t) => t.refundOfId.equals(expenseId) & t.deletedAt.isNull()))
      .get();

  /// Sum of refunds of [expenseId] that are not deleted, optionally excluding
  /// one refund (the one being edited).
  Future<int> refundedTotal(String expenseId, {String? excludeId}) async {
    final sum = transactions.amountPaisa.sum();
    final query = selectOnly(transactions)
      ..addColumns([sum])
      ..where(transactions.refundOfId.equals(expenseId) &
          transactions.deletedAt.isNull());
    if (excludeId != null) query.where(transactions.id.equals(excludeId).not());
    final row = await query.getSingle();
    return row.read(sum) ?? 0;
  }

  Stream<TransactionRow?> watchById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Stream<List<TransactionRow>> watchRefundsOf(String expenseId) => (select(transactions)
        ..where((t) => t.refundOfId.equals(expenseId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
      .watch();

  /// Number of transactions (including deleted ones, which still reference
  /// the row) that use any of [categoryIds] as category or subcategory.
  /// Each transaction is counted once.
  Future<int> countReferencingCategories(List<String> categoryIds) async {
    final count = transactions.id.count();
    final row = await (selectOnly(transactions)
          ..addColumns([count])
          ..where(transactions.categoryId.isIn(categoryIds) |
              transactions.subcategoryId.isIn(categoryIds)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> countReferencingAccount(String accountId) async {
    final count = transactions.id.count();
    final row = await (selectOnly(transactions)
          ..addColumns([count])
          ..where(transactions.accountId.equals(accountId) |
              transactions.counterAccountId.equals(accountId)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  // -------------------------------------------------------------- history

  /// The WHERE clause for history, with its variables in order.
  (String, List<Variable<Object>>) _historyWhere(HistorySqlParams p) {
    final ids = p.workspaceIds;
    final ph = List.filled(ids.length, '?').join(', ');
    final vars = <Variable<Object>>[];
    final sql = StringBuffer('t.deleted_at IS NULL AND t.workspace_id IN ($ph)');
    vars.addAll(ids.map(Variable.withString));

    // Show a transfer once when both rows are in scope: hide the incoming
    // row whose outgoing row is also visible.
    sql.write(" AND NOT (t.type = 'transfer_in' AND EXISTS ("
        'SELECT 1 FROM transactions o WHERE o.transfer_group_id = t.transfer_group_id '
        "AND o.type = 'transfer_out' AND o.deleted_at IS NULL AND o.workspace_id IN ($ph)))");
    vars.addAll(ids.map(Variable.withString));

    if (p.dbTypes.isNotEmpty) {
      sql.write(' AND t.type IN (${List.filled(p.dbTypes.length, '?').join(', ')})');
      vars.addAll(p.dbTypes.map(Variable.withString));
    }
    if (p.categoryId != null) {
      sql.write(' AND t.category_id = ?');
      vars.add(Variable.withString(p.categoryId!));
    }
    if (p.subcategoryId != null) {
      sql.write(' AND t.subcategory_id = ?');
      vars.add(Variable.withString(p.subcategoryId!));
    }
    if (p.accountId != null) {
      // A transfer matches either of its accounts.
      sql.write(" AND (t.account_id = ? OR (t.type IN ('transfer_out', 'transfer_in') "
          'AND t.counter_account_id = ?))');
      vars
        ..add(Variable.withString(p.accountId!))
        ..add(Variable.withString(p.accountId!));
    }
    if (p.fromDate != null) {
      sql.write(' AND t.local_date >= ?');
      vars.add(Variable.withInt(p.fromDate!));
    }
    if (p.toDate != null) {
      sql.write(' AND t.local_date <= ?');
      vars.add(Variable.withInt(p.toDate!));
    }
    if (p.searchLike != null) {
      sql.write(" AND (t.description LIKE ? ESCAPE '\\'");
      vars.add(Variable.withString(p.searchLike!));
      if (p.searchCategoryIds.isNotEmpty) {
        final cph = List.filled(p.searchCategoryIds.length, '?').join(', ');
        sql.write(' OR t.category_id IN ($cph) OR t.subcategory_id IN ($cph)');
        vars
          ..addAll(p.searchCategoryIds.map(Variable.withString))
          ..addAll(p.searchCategoryIds.map(Variable.withString));
      }
      sql.write(')');
    }
    return (sql.toString(), vars);
  }

  /// Newest-first history. Returns at least [HistorySqlParams.limit] rows
  /// when available and always includes the whole of the oldest day loaded,
  /// so day totals computed from a page are exact.
  Stream<HistoryRows> watchHistory(HistorySqlParams p) {
    if (p.workspaceIds.isEmpty) {
      return Stream.value((rows: const <TransactionRow>[], totalCount: 0));
    }
    final (where, vars) = _historyWhere(p);
    final query = customSelect(
      'SELECT t.*, (SELECT COUNT(*) FROM transactions t WHERE $where) AS total_count '
      'FROM transactions t '
      'WHERE $where AND t.local_date >= COALESCE(('
      'SELECT t.local_date FROM transactions t WHERE $where '
      'ORDER BY $_order LIMIT 1 OFFSET ?), 0) '
      'ORDER BY $_order',
      variables: [...vars, ...vars, ...vars, Variable.withInt(p.limit - 1)],
      readsFrom: {transactions, categories, accounts},
    );
    return query.watch().asyncMap((rows) async {
      final mapped = await Future.wait(rows.map(transactions.mapFromRow));
      final total = rows.isEmpty ? 0 : rows.first.read<int>('total_count');
      return (rows: mapped, totalCount: total);
    });
  }

  /// Latest row of each distinct income/expense combination (workspace,
  /// type, category, subcategory, account, description), newest first.
  Stream<List<TransactionRow>> watchRecent(List<String> workspaceIds, int limit) {
    if (workspaceIds.isEmpty) return Stream.value(const []);
    final ph = List.filled(workspaceIds.length, '?').join(', ');
    final query = customSelect(
      'SELECT t.* FROM transactions t WHERE t.id IN ('
      'SELECT id FROM (SELECT id, ROW_NUMBER() OVER ('
      "PARTITION BY workspace_id, type, category_id, IFNULL(subcategory_id, ''), "
      "account_id, IFNULL(description, '') "
      'ORDER BY occurred_at DESC, created_at DESC) AS rn '
      'FROM transactions '
      "WHERE deleted_at IS NULL AND type IN ('income', 'expense') "
      'AND workspace_id IN ($ph)) WHERE rn = 1) '
      'ORDER BY t.occurred_at DESC, t.created_at DESC LIMIT ?',
      variables: [...workspaceIds.map(Variable.withString), Variable.withInt(limit)],
      readsFrom: {transactions, categories, accounts},
    );
    return query.watch().asyncMap((rows) => Future.wait(rows.map(transactions.mapFromRow)));
  }

  // --------------------------------------------------------------- writes

  Future<void> insertRow(TransactionsCompanion row) => into(transactions).insert(row);

  Future<void> updateRow(String id, TransactionsCompanion row) async {
    final n = await (update(transactions)..where((t) => t.id.equals(id))).write(row);
    if (n != 1) throw StateError('Expected to update 1 row for $id, updated $n');
  }

  /// Sets or clears `deleted_at` (soft delete / restore) and bumps
  /// `updated_at`, which future sync relies on.
  Future<void> setDeleted(List<String> ids, {required int? deletedAt, required int now}) =>
      (update(transactions)..where((t) => t.id.isIn(ids))).write(
        TransactionsCompanion(deletedAt: Value(deletedAt), updatedAt: Value(now)),
      );

  /// Keeps refunds in their expense's category after the expense is edited.
  Future<void> moveRefundsToCategory(
    String expenseId, {
    required String categoryId,
    required String? subcategoryId,
    required int now,
  }) =>
      (update(transactions)..where((t) => t.refundOfId.equals(expenseId))).write(
        TransactionsCompanion(
          categoryId: Value(categoryId),
          subcategoryId: Value(subcategoryId),
          updatedAt: Value(now),
        ),
      );

  /// Reassigns transactions from one top-level category to another. Their
  /// subcategory is cleared because it belonged to the old parent.
  Future<int> reassignCategory(String fromId, String toId, int now) =>
      (update(transactions)..where((t) => t.categoryId.equals(fromId))).write(
        TransactionsCompanion(
          categoryId: Value(toId),
          subcategoryId: const Value(null),
          updatedAt: Value(now),
        ),
      );

  /// Removes a subcategory from transactions; they stay in the parent.
  Future<int> clearSubcategory(String subcategoryId, int now) =>
      (update(transactions)..where((t) => t.subcategoryId.equals(subcategoryId))).write(
        TransactionsCompanion(subcategoryId: const Value(null), updatedAt: Value(now)),
      );
}
