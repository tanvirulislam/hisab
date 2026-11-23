import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'loans_dao.g.dart';

/// Raw totals of one person's live entries, in paisa.
typedef PersonTotalsRow = ({
  PersonRow person,
  int lent,
  int repaidToMe,
  int borrowed,
  int repaidByMe,
  int? lastDate,
});

@DriftAccessor(tables: [Persons, LoanEntries])
class LoansDao extends DatabaseAccessor<AppDatabase> with _$LoansDaoMixin {
  LoansDao(super.attachedDatabase);

  /// Signed effect of a loan entry on its account's balance (D16). Rows with
  /// no account (old loans from before the app) change no balance.
  /// Same role as `AccountsDao.signedAmountSql`: reuse it, never copy it.
  static const String signedAmountSql =
      "CASE WHEN l.kind IN ('repaid_to_me', 'borrowed') THEN l.amount_paisa "
      "WHEN l.kind IN ('lent', 'repaid_by_me') THEN -l.amount_paisa "
      'ELSE 0 END';

  Stream<List<PersonTotalsRow>> watchTotals(List<String> workspaceIds) {
    if (workspaceIds.isEmpty) return Stream.value(const []);
    final placeholders = List.filled(workspaceIds.length, '?').join(', ');
    String sumOf(String kind) =>
        "COALESCE(SUM(CASE WHEN l.kind = '$kind' THEN l.amount_paisa END), 0)";
    final query = customSelect(
      'SELECT p.*, '
      "${sumOf('lent')} AS lent, ${sumOf('repaid_to_me')} AS repaid_to_me, "
      "${sumOf('borrowed')} AS borrowed, ${sumOf('repaid_by_me')} AS repaid_by_me, "
      'MAX(l.local_date) AS last_date '
      'FROM persons p '
      'LEFT JOIN loan_entries l ON l.person_id = p.id AND l.deleted_at IS NULL '
      'WHERE p.workspace_id IN ($placeholders) AND p.deleted_at IS NULL '
      'GROUP BY p.id ORDER BY p.name COLLATE NOCASE',
      variables: [for (final id in workspaceIds) Variable.withString(id)],
      readsFrom: {persons, loanEntries},
    );
    return query.watch().asyncMap(
      (rows) => Future.wait(
        rows.map((row) async => (
          person: await persons.mapFromRow(row),
          lent: row.read<int>('lent'),
          repaidToMe: row.read<int>('repaid_to_me'),
          borrowed: row.read<int>('borrowed'),
          repaidByMe: row.read<int>('repaid_by_me'),
          lastDate: row.read<int?>('last_date'),
        )),
      ),
    );
  }

  /// Live entries of a person, newest first.
  Stream<List<LoanEntryRow>> watchEntries(String personId) =>
      (select(loanEntries)
            ..where((e) => e.personId.equals(personId) & e.deletedAt.isNull())
            ..orderBy([
              (e) => OrderingTerm.desc(e.localDate),
              (e) => OrderingTerm.desc(e.createdAt),
            ]))
          .watch();

  Stream<PersonRow?> watchPerson(String id) =>
      (select(persons)..where((p) => p.id.equals(id) & p.deletedAt.isNull()))
          .watchSingleOrNull();

  Future<PersonRow?> findPerson(String id) =>
      (select(persons)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<List<PersonRow>> livePersons(String workspaceId) =>
      (select(persons)
            ..where((p) => p.workspaceId.equals(workspaceId) & p.deletedAt.isNull()))
          .get();

  Future<LoanEntryRow?> findEntry(String id) =>
      (select(loanEntries)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<void> insertPerson(PersonsCompanion row) => into(persons).insert(row);

  Future<void> updatePerson(String id, PersonsCompanion row) =>
      (update(persons)..where((p) => p.id.equals(id))).write(row);

  Future<void> insertEntry(LoanEntriesCompanion row) =>
      into(loanEntries).insert(row);

  Future<void> updateEntry(String id, LoanEntriesCompanion row) =>
      (update(loanEntries)..where((e) => e.id.equals(id))).write(row);

  /// Sums of the live entries of one person, in paisa, by kind.
  Future<Map<String, int>> sumsByKind(String personId) async {
    final rows = await customSelect(
      'SELECT kind, SUM(amount_paisa) AS total FROM loan_entries '
      'WHERE person_id = ? AND deleted_at IS NULL GROUP BY kind',
      variables: [Variable.withString(personId)],
      readsFrom: {loanEntries},
    ).get();
    return {for (final r in rows) r.read<String>('kind'): r.read<int>('total')};
  }

  Future<int> countLiveEntries(String personId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM loan_entries WHERE person_id = ? AND deleted_at IS NULL',
      variables: [Variable.withString(personId)],
      readsFrom: {loanEntries},
    ).getSingle();
    return row.read<int>('n');
  }

  /// Live loan entries that use an account (blocks deleting the account).
  Future<int> countReferencingAccount(String accountId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM loan_entries WHERE account_id = ? AND deleted_at IS NULL',
      variables: [Variable.withString(accountId)],
      readsFrom: {loanEntries},
    ).getSingle();
    return row.read<int>('n');
  }
}
