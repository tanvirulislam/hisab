import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'reports_dao.g.dart';

/// Raw totals in paisa for a date range.
typedef TotalsRow = ({
  int income,
  int expense,
  int refund,
  int transferIn,
  int transferOut,
  int count,
});

typedef DailyRow = ({int localDate, int income, int netExpense});
typedef MonthRow = ({int yearMonth, int income, int netExpense});
typedef KeyAmountRow = ({String? key, int amount});

/// SQL aggregation for dashboard and reports (§11, §24).
///
/// Reporting rules (§23):
/// - Income = Σ income.
/// - Expense = Σ expense − Σ refund (D5). Refunds are never income.
/// - Transfers never count as income or expense (rule 4). They are reported
///   separately as transfer in/out.
/// - Dates use `local_date` (rules 12–13). Deleted rows are ignored.
/// - An empty workspace list never runs an unscoped query (D9).
@DriftAccessor(tables: [Transactions, Categories])
class ReportsDao extends DatabaseAccessor<AppDatabase> with _$ReportsDaoMixin {
  ReportsDao(super.attachedDatabase);

  static const String _netExpense =
      "SUM(CASE WHEN type = 'expense' THEN amount_paisa "
      "WHEN type = 'refund' THEN -amount_paisa ELSE 0 END)";
  static const String _income =
      "SUM(CASE WHEN type = 'income' THEN amount_paisa ELSE 0 END)";

  (String, List<Variable<Object>>) _scope(List<String> ids, int from, int to) {
    final ph = List.filled(ids.length, '?').join(', ');
    return (
      'deleted_at IS NULL AND workspace_id IN ($ph) AND local_date BETWEEN ? AND ?',
      [...ids.map(Variable.withString), Variable.withInt(from), Variable.withInt(to)],
    );
  }

  Stream<TotalsRow> watchTotals(List<String> ids, int from, int to) {
    if (ids.isEmpty) {
      return Stream.value((income: 0, expense: 0, refund: 0, transferIn: 0, transferOut: 0, count: 0));
    }
    final (where, vars) = _scope(ids, from, to);
    return customSelect(
      'SELECT '
      "COALESCE(SUM(CASE WHEN type = 'income' THEN amount_paisa END), 0) AS income, "
      "COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_paisa END), 0) AS expense, "
      "COALESCE(SUM(CASE WHEN type = 'refund' THEN amount_paisa END), 0) AS refund, "
      "COALESCE(SUM(CASE WHEN type = 'transfer_in' THEN amount_paisa END), 0) AS transfer_in, "
      "COALESCE(SUM(CASE WHEN type = 'transfer_out' THEN amount_paisa END), 0) AS transfer_out, "
      "COUNT(CASE WHEN type IN ('income', 'expense', 'refund') THEN 1 END) AS n "
      'FROM transactions WHERE $where',
      variables: vars,
      readsFrom: {transactions},
    ).watchSingle().map((r) => (
      income: r.read<int>('income'),
      expense: r.read<int>('expense'),
      refund: r.read<int>('refund'),
      transferIn: r.read<int>('transfer_in'),
      transferOut: r.read<int>('transfer_out'),
      count: r.read<int>('n'),
    ));
  }

  /// Per-day income and net expense; days with no rows are omitted.
  Stream<List<DailyRow>> watchDaily(List<String> ids, int from, int to) {
    if (ids.isEmpty) return Stream.value(const []);
    final (where, vars) = _scope(ids, from, to);
    return customSelect(
      'SELECT local_date, COALESCE($_income, 0) AS income, COALESCE($_netExpense, 0) AS expense '
      "FROM transactions WHERE $where AND type IN ('income', 'expense', 'refund') "
      'GROUP BY local_date ORDER BY local_date',
      variables: vars,
      readsFrom: {transactions},
    ).watch().map((rows) => [
      for (final r in rows)
        (localDate: r.read<int>('local_date'), income: r.read<int>('income'), netExpense: r.read<int>('expense')),
    ]);
  }

  /// Per-month (yyyymm) income and net expense.
  Stream<List<MonthRow>> watchMonthly(List<String> ids, int from, int to) {
    if (ids.isEmpty) return Stream.value(const []);
    final (where, vars) = _scope(ids, from, to);
    return customSelect(
      'SELECT local_date / 100 AS ym, COALESCE($_income, 0) AS income, COALESCE($_netExpense, 0) AS expense '
      "FROM transactions WHERE $where AND type IN ('income', 'expense', 'refund') "
      'GROUP BY ym ORDER BY ym',
      variables: vars,
      readsFrom: {transactions},
    ).watch().map((rows) => [
      for (final r in rows)
        (yearMonth: r.read<int>('ym'), income: r.read<int>('income'), netExpense: r.read<int>('expense')),
    ]);
  }

  /// Net expense (or income) per top-level category, largest first.
  Stream<List<KeyAmountRow>> watchByCategory(
    List<String> ids,
    int from,
    int to, {
    required bool income,
  }) {
    if (ids.isEmpty) return Stream.value(const []);
    final (where, vars) = _scope(ids, from, to);
    final sum = income ? _income : _netExpense;
    final types = income ? "('income')" : "('expense', 'refund')";
    return customSelect(
      'SELECT category_id AS k, COALESCE($sum, 0) AS amount FROM transactions '
      'WHERE $where AND type IN $types GROUP BY category_id ORDER BY amount DESC',
      variables: vars,
      readsFrom: {transactions, categories},
    ).watch().map((rows) => [
      for (final r in rows) (key: r.readNullable<String>('k'), amount: r.read<int>('amount')),
    ]);
  }

  /// Net expense per subcategory of [categoryId] (NULL key = no subcategory).
  Stream<List<KeyAmountRow>> watchBySubcategory(
    List<String> ids,
    int from,
    int to,
    String categoryId,
  ) {
    if (ids.isEmpty) return Stream.value(const []);
    final (where, vars) = _scope(ids, from, to);
    return customSelect(
      'SELECT subcategory_id AS k, COALESCE($_netExpense, 0) AS amount FROM transactions '
      "WHERE $where AND type IN ('expense', 'refund') AND category_id = ? "
      'GROUP BY subcategory_id ORDER BY amount DESC',
      variables: [...vars, Variable.withString(categoryId)],
      readsFrom: {transactions, categories},
    ).watch().map((rows) => [
      for (final r in rows) (key: r.readNullable<String>('k'), amount: r.read<int>('amount')),
    ]);
  }
}
