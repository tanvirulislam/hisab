import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../domain/loan.dart';
import '../domain/loan_repository.dart';

class DriftLoanRepository implements LoanRepository {
  DriftLoanRepository(this._db);

  final AppDatabase _db;

  static const int maxNameLength = 60;
  static const int maxPhoneLength = 30;
  static const int maxNoteLength = 500;

  static Person _person(PersonRow r) =>
      Person(id: r.id, workspaceId: r.workspaceId, name: r.name, phone: r.phone);

  static LoanEntry _entry(LoanEntryRow r) => LoanEntry(
    id: r.id,
    personId: r.personId,
    workspaceId: r.workspaceId,
    accountId: r.accountId,
    kind: LoanKind.fromDb(r.kind),
    amount: Money(r.amountPaisa),
    date: LocalDate.fromInt(r.localDate),
    note: r.note,
  );

  @override
  Stream<List<PersonLoanSummary>> watchSummaries(List<String> workspaceIds) =>
      _db.loansDao.watchTotals(workspaceIds).map((rows) => [
        for (final r in rows)
          PersonLoanSummary(
            person: _person(r.person),
            owedToMe: Money(r.lent - r.repaidToMe),
            iOwe: Money(r.borrowed - r.repaidByMe),
            lastDate: r.lastDate == null ? null : LocalDate.fromInt(r.lastDate!),
          ),
      ]);

  @override
  Stream<Person?> watchPerson(String id) =>
      _db.loansDao.watchPerson(id).map((r) => r == null ? null : _person(r));

  @override
  Stream<List<LoanEntry>> watchEntries(String personId) =>
      _db.loansDao.watchEntries(personId).map((rows) => rows.map(_entry).toList());

  String _validName(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty || n.length > maxNameLength) {
      throw const ValidationException(LoanError.nameInvalid);
    }
    return n;
  }

  String? _validPhone(String? phone) {
    final p = (phone ?? '').trim();
    if (p.length > maxPhoneLength) throw const ValidationException(LoanError.nameInvalid);
    return p.isEmpty ? null : p;
  }

  String? _validNote(String? note) {
    final n = (note ?? '').trim();
    if (n.length > maxNoteLength) throw const ValidationException(LoanError.noteTooLong);
    return n.isEmpty ? null : n;
  }

  Money _validAmount(Money amount) {
    if (!amount.isPositive || amount.paisa > Money.maxInputPaisa) {
      throw const ValidationException(LoanError.amountInvalid);
    }
    return amount;
  }

  Future<PersonRow> _requirePerson(String id) async {
    final row = await _db.loansDao.findPerson(id);
    if (row == null || row.deletedAt != null) {
      throw const ValidationException(LoanError.personNotFound);
    }
    return row;
  }

  Future<LoanEntryRow> _requireEntry(String id) async {
    final row = await _db.loansDao.findEntry(id);
    if (row == null || row.deletedAt != null) {
      throw const ValidationException(LoanError.entryNotFound);
    }
    return row;
  }

  /// The account of an entry must exist and belong to the entry's workspace.
  /// A new entry also needs an active account; an old entry keeps working
  /// after its account is archived, so [requireActive] is off for edits that
  /// keep the same account.
  Future<void> _checkAccount(
    String accountId,
    String workspaceId, {
    required bool requireActive,
  }) async {
    final acc = await _db.accountsDao.findById(accountId);
    if (acc == null || acc.deletedAt != null || acc.workspaceId != workspaceId) {
      throw const ValidationException(LoanError.accountNotFound);
    }
    if (requireActive && !acc.isActive) {
      throw const ValidationException(LoanError.accountInactive);
    }
  }

  /// The one rule that keeps loans honest: a repayment can never be larger
  /// than what is still open. Checked after every write, inside the same
  /// database transaction, so a failing check rolls the write back.
  Future<void> _assertConsistent(String personId) async {
    final sums = await _db.loansDao.sumsByKind(personId);
    int sum(LoanKind k) => sums[k.dbValue] ?? 0;
    if (sum(LoanKind.repaidToMe) > sum(LoanKind.lent) ||
        sum(LoanKind.repaidByMe) > sum(LoanKind.borrowed)) {
      throw const ConflictException(LoanError.exceedsOutstanding);
    }
  }

  @override
  Future<String> addEntry(LoanEntryDraft d) => _db.transaction(() async {
    final amount = _validAmount(d.amount);
    final note = _validNote(d.note);
    final ws = await _db.workspacesDao.findById(d.workspaceId);
    if (ws == null || ws.deletedAt != null) {
      throw const ValidationException(LoanError.personNotFound, 'workspace');
    }
    final now = _db.clock.nowMillis();

    final String personId;
    if (d.personId != null) {
      final p = await _requirePerson(d.personId!);
      if (p.workspaceId != d.workspaceId) {
        throw const ValidationException(LoanError.personNotFound, 'workspace');
      }
      personId = p.id;
    } else {
      final name = _validName(d.personName);
      final existing = (await _db.loansDao.livePersons(d.workspaceId))
          .where((p) => p.name.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      if (existing != null) {
        personId = existing.id;
      } else {
        personId = _db.ids.newId();
        await _db.loansDao.insertPerson(PersonsCompanion.insert(
          id: personId,
          workspaceId: d.workspaceId,
          name: name,
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    if (!d.kind.isOrigin && d.accountId == null) {
      throw const ValidationException(LoanError.accountRequired);
    }
    if (d.accountId != null) {
      await _checkAccount(d.accountId!, d.workspaceId, requireActive: true);
    }

    final id = _db.ids.newId();
    await _db.loansDao.insertEntry(LoanEntriesCompanion.insert(
      id: id,
      workspaceId: d.workspaceId,
      personId: personId,
      accountId: Value(d.accountId),
      kind: d.kind.dbValue,
      amountPaisa: amount.paisa,
      localDate: d.date.toInt(),
      note: Value(note),
      createdAt: now,
      updatedAt: now,
    ));
    await _assertConsistent(personId);
    return id;
  });

  @override
  Future<void> updateEntry(
    String id, {
    required Money amount,
    required LocalDate date,
    String? accountId,
    String? note,
  }) => _db.transaction(() async {
    final row = await _requireEntry(id);
    final kind = LoanKind.fromDb(row.kind);
    final amt = _validAmount(amount);
    final n = _validNote(note);
    if (!kind.isOrigin && accountId == null) {
      throw const ValidationException(LoanError.accountRequired);
    }
    if (accountId != null) {
      await _checkAccount(
        accountId,
        row.workspaceId,
        requireActive: accountId != row.accountId,
      );
    }
    await _db.loansDao.updateEntry(id, LoanEntriesCompanion(
      amountPaisa: Value(amt.paisa),
      localDate: Value(date.toInt()),
      accountId: Value(accountId),
      note: Value(n),
      updatedAt: Value(_db.clock.nowMillis()),
    ));
    await _assertConsistent(row.personId);
  });

  @override
  Future<void> deleteEntry(String id) => _db.transaction(() async {
    final row = await _requireEntry(id);
    final now = _db.clock.nowMillis();
    await _db.loansDao.updateEntry(id, LoanEntriesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
    await _assertConsistent(row.personId);
  });

  @override
  Future<void> updatePerson(String id, {required String name, String? phone}) =>
      _db.transaction(() async {
        final row = await _requirePerson(id);
        final n = _validName(name);
        final clash = (await _db.loansDao.livePersons(row.workspaceId)).any(
          (p) => p.id != id && p.name.toLowerCase() == n.toLowerCase(),
        );
        if (clash) throw const ValidationException(LoanError.nameDuplicate);
        await _db.loansDao.updatePerson(id, PersonsCompanion(
          name: Value(n),
          phone: Value(_validPhone(phone)),
          updatedAt: Value(_db.clock.nowMillis()),
        ));
      });

  @override
  Future<void> deletePerson(String id) => _db.transaction(() async {
    await _requirePerson(id);
    if (await _db.loansDao.countLiveEntries(id) > 0) {
      throw const ConflictException(LoanError.personInUse);
    }
    final now = _db.clock.nowMillis();
    await _db.loansDao.updatePerson(id, PersonsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  });
}
