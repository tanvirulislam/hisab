import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../accounts/data/drift_account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/drift_category_repository.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/drafts.dart';
import '../../transactions/domain/ledger_entry.dart';
import '../../transactions/domain/transaction_repository.dart';
import '../../transactions/domain/transaction_rules.dart';
import '../../workspaces/domain/workspace.dart';
import '../domain/recurrence.dart';
import '../domain/recurring_repository.dart';
import '../domain/recurring_rule.dart';

class DriftRecurringRepository implements RecurringRepository {
  DriftRecurringRepository(this._db, this._transactions);

  final AppDatabase _db;

  /// Generated occurrences go through the normal, validated write path.
  final TransactionRepository _transactions;

  /// Generated transactions are timed at 09:00 on their occurrence date.
  static const int occurrenceHour = 9;
  static const int maxInterval = 999;

  int get _now => _db.clock.nowMillis();

  static RecurringRule toDomain(RecurringRuleRow r) => RecurringRule(
    id: r.id,
    workspaceId: r.workspaceId,
    type: RecurringType.fromDb(r.type),
    accountId: r.accountId,
    counterAccountId: r.counterAccountId,
    categoryId: r.categoryId,
    subcategoryId: r.subcategoryId,
    amount: Money(r.amountPaisa),
    description: r.description,
    frequency: Frequency.fromDb(r.frequency),
    interval: r.intervalCount,
    startDate: LocalDate.fromInt(r.startDate),
    endDate: r.endDate == null ? null : LocalDate.fromInt(r.endDate!),
    nextDueDate: LocalDate.fromInt(r.nextDueDate),
    isPaused: r.isPaused,
  );

  /// The editable template of [r].
  static RecurringDraft draftOf(RecurringRule r) => RecurringDraft(
    type: r.type,
    workspaceId: r.workspaceId,
    accountId: r.accountId,
    counterAccountId: r.counterAccountId,
    categoryId: r.categoryId,
    subcategoryId: r.subcategoryId,
    amount: r.amount,
    description: r.description,
    frequency: r.frequency,
    interval: r.interval,
    startDate: r.startDate,
    endDate: r.endDate,
  );

  // ------------------------------------------------------------- reading

  @override
  Stream<List<RecurringRuleItem>> watchRules(List<String> workspaceIds) =>
      _db.recurringDao.watchRules(workspaceIds).asyncMap((rows) async {
        final accounts = {
          for (final a in await _db.accountsDao.getAll()) a.id: DriftAccountRepository.toDomain(a),
        };
        final categories = {
          for (final c in await _db.categoriesDao.getAll()) c.id: DriftCategoryRepository.toDomain(c),
        };
        final types = {
          for (final w in await _db.workspacesDao.getAll()) w.id: WorkspaceType.fromDb(w.type),
        };
        return [
          for (final r in rows)
            RecurringRuleItem(
              rule: toDomain(r),
              workspaceType: types[r.workspaceId]!,
              account: accounts[r.accountId]!,
              counterAccount: accounts[r.counterAccountId],
              category: categories[r.categoryId],
              subcategory: categories[r.subcategoryId],
            ),
        ];
      });

  @override
  Stream<RecurringRule?> watchRule(String id) =>
      _db.recurringDao.watchById(id).map((r) => r == null ? null : toDomain(r));

  // ------------------------------------------------------------- writing

  Future<Account?> _liveAccount(String? id) async {
    if (id == null) return null;
    final r = await _db.accountsDao.findById(id);
    return r == null || r.deletedAt != null ? null : DriftAccountRepository.toDomain(r);
  }

  Future<Category?> _liveCategory(String? id) async {
    if (id == null) return null;
    final r = await _db.categoriesDao.findById(id);
    return r == null || r.deletedAt != null ? null : DriftCategoryRepository.toDomain(r);
  }

  /// Checks the template with the same rules as a real transaction, with
  /// active references required: the rule will create new entries.
  Future<RecurringRulesCompanion> _validated(RecurringDraft d) async {
    TransactionRules.checkAmount(d.amount);
    final description = TransactionRules.normalizeDescription(d.description);
    if (d.interval < 1 || d.interval > maxInterval) {
      throw const ValidationException(RecurringError.intervalInvalid);
    }
    if (d.endDate != null && d.endDate!.isBefore(d.startDate)) {
      throw const ValidationException(RecurringError.endBeforeStart);
    }

    final String workspaceId;
    if (d.type == RecurringType.transfer) {
      final from = await _liveAccount(d.accountId);
      final to = await _liveAccount(d.counterAccountId);
      TransactionRules.checkTransferAccounts(from, to, requireActive: true);
      workspaceId = from!.workspaceId;
    } else {
      workspaceId = d.workspaceId;
      final ws = await _db.workspacesDao.findById(workspaceId);
      if (ws == null || ws.deletedAt != null) {
        throw const ValidationException(TxnError.workspaceNotFound);
      }
      TransactionRules.checkAccount(await _liveAccount(d.accountId),
          workspaceId: workspaceId, requireActive: true);
      final category = await _liveCategory(d.categoryId);
      TransactionRules.checkCategory(category,
          expectedType: d.type.entryType!.categoryType, workspaceId: workspaceId, requireActive: true);
      TransactionRules.checkSubcategory(await _liveCategory(d.subcategoryId),
          subcategoryId: d.subcategoryId, category: category!, requireActive: true);
    }
    final isTransfer = d.type == RecurringType.transfer;
    return RecurringRulesCompanion(
      workspaceId: Value(workspaceId),
      type: Value(d.type.dbValue),
      accountId: Value(d.accountId),
      counterAccountId: Value(isTransfer ? d.counterAccountId : null),
      categoryId: Value(isTransfer ? null : d.categoryId),
      subcategoryId: Value(isTransfer ? null : d.subcategoryId),
      amountPaisa: Value(d.amount.paisa),
      description: Value(description),
      frequency: Value(d.frequency.dbValue),
      intervalCount: Value(d.interval),
      startDate: Value(d.startDate.toInt()),
      endDate: Value(d.endDate?.toInt()),
      updatedAt: Value(_now),
    );
  }

  @override
  Future<String> create(RecurringDraft d) => _db.transaction(() async {
    // A start in the past would silently back-fill entries the user may
    // already have recorded by hand.
    if (d.startDate.isBefore(_db.clock.today())) {
      throw const ValidationException(RecurringError.startInPast);
    }
    final row = await _validated(d);
    final id = _db.ids.newId();
    await _db.recurringDao.insertRule(row.copyWith(
      id: Value(id),
      nextDueDate: Value(d.startDate.toInt()),
      isPaused: const Value(false),
      createdAt: Value(_now),
    ));
    return id;
  });

  /// Next occurrence of [r] that has not been recorded and is not before
  /// today: occurrences missed while paused, or before an edit, are skipped.
  Future<LocalDate> _nextDueFromToday(String ruleId, Recurrence r) async {
    final last = await _db.recurringDao.lastOccurrence(ruleId);
    var floor = _db.clock.today();
    if (last != null) {
      final afterLast = LocalDate.fromInt(last).addDays(1);
      if (afterLast.isAfter(floor)) floor = afterLast;
    }
    return r.scheduledOnOrAfter(floor);
  }

  @override
  Future<void> update(String id, RecurringDraft d) => _db.transaction(() async {
    final existing = await _db.recurringDao.findById(id);
    if (existing == null || existing.deletedAt != null) {
      throw const ValidationException(RecurringError.notFound);
    }
    if (d.startDate.toInt() != existing.startDate && d.startDate.isBefore(_db.clock.today())) {
      throw const ValidationException(RecurringError.startInPast);
    }
    final row = await _validated(d);
    final schedule = Recurrence(frequency: d.frequency, interval: d.interval, start: d.startDate, end: d.endDate);
    await _db.recurringDao.updateRule(
        id, row.copyWith(nextDueDate: Value((await _nextDueFromToday(id, schedule)).toInt())));
  });

  @override
  Future<void> setPaused(String id, bool paused) => _db.transaction(() async {
    final existing = await _db.recurringDao.findById(id);
    if (existing == null || existing.deletedAt != null) {
      throw const ValidationException(RecurringError.notFound);
    }
    var row = RecurringRulesCompanion(isPaused: Value(paused), updatedAt: Value(_now));
    if (!paused) {
      final rule = toDomain(existing);
      // Fail now, not silently on the next generator run.
      await _validated(draftOf(rule));
      final next = await _nextDueFromToday(id, rule.recurrence);
      row = row.copyWith(nextDueDate: Value(next.toInt()));
    }
    await _db.recurringDao.updateRule(id, row);
  });

  @override
  Future<void> delete(String id) => _db.recurringDao.updateRule(
      id, RecurringRulesCompanion(deletedAt: Value(_now), updatedAt: Value(_now)));

  // ----------------------------------------------------------- generator

  @override
  Future<GenerationResult> generateDue(LocalDate today) async {
    var created = 0;
    final paused = <String>[];
    for (final row in await _db.recurringDao.dueRules(today.toInt())) {
      final rule = toDomain(row);
      for (final date in rule.recurrence.between(rule.nextDueDate, today)) {
        try {
          if (await _recordOccurrence(rule, date)) created++;
        } on ValidationException {
          // The template no longer passes validation (account deactivated,
          // category archived, …). Pause the rule rather than retrying on
          // every start; the user sees it paused and can fix it.
          await _db.recurringDao.updateRule(
              rule.id, RecurringRulesCompanion(isPaused: const Value(true), updatedAt: Value(_now)));
          paused.add(rule.id);
          break;
        }
      }
    }
    return GenerationResult(created: created, pausedRuleIds: paused);
  }

  /// Writes one occurrence, its execution row and the rule's next due date
  /// in one DB transaction. Returns false if it was already recorded.
  Future<bool> _recordOccurrence(RecurringRule rule, LocalDate date) => _db.transaction(() async {
    final next = rule.recurrence.scheduledOnOrAfter(date.addDays(1)).toInt();
    final already = await (_db.select(_db.recurringExecutions)
          ..where((e) => e.ruleId.equals(rule.id) & e.occurrenceDate.equals(date.toInt())))
        .getSingleOrNull();
    if (already != null) {
      await _db.recurringDao.updateRule(rule.id, RecurringRulesCompanion(nextDueDate: Value(next)));
      return false;
    }
    final at = DateTime(date.year, date.month, date.day, occurrenceHour);
    final String transactionId;
    if (rule.type == RecurringType.transfer) {
      final groupId = await _transactions.createTransfer(TransferDraft(
        fromAccountId: rule.accountId,
        toAccountId: rule.counterAccountId!,
        amount: rule.amount,
        description: rule.description,
        occurredAt: at,
        source: EntrySource.recurring,
        recurringRuleId: rule.id,
      ));
      transactionId = (await _transactions.transferLegs(groupId))
          .firstWhere((e) => e.kind == EntryKind.transferOut)
          .id;
    } else {
      transactionId = await _transactions.createEntry(EntryDraft(
        type: rule.type.entryType!,
        workspaceId: rule.workspaceId,
        accountId: rule.accountId,
        amount: rule.amount,
        categoryId: rule.categoryId!,
        subcategoryId: rule.subcategoryId,
        description: rule.description,
        occurredAt: at,
        source: EntrySource.recurring,
        recurringRuleId: rule.id,
      ));
    }
    // The unique (rule_id, occurrence_date) index is the final guard: a
    // duplicate fails here and rolls back the transaction above (D11).
    await _db.recurringDao.insertExecution(RecurringExecutionsCompanion.insert(
      id: _db.ids.newId(),
      ruleId: rule.id,
      occurrenceDate: date.toInt(),
      transactionId: Value(transactionId),
      executedAt: _now,
    ));
    await _db.recurringDao.updateRule(
        rule.id, RecurringRulesCompanion(nextDueDate: Value(next), updatedAt: Value(_now)));
    return true;
  });
}
