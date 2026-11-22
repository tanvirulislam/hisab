import 'package:drift/drift.dart';

import '../../../core/constants/default_categories.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/daos/transactions_dao.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../accounts/data/drift_account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/drift_category_repository.dart';
import '../../categories/domain/category.dart';
import '../../workspaces/domain/workspace.dart';
import '../domain/drafts.dart';
import '../domain/history_filter.dart';
import '../domain/ledger_entry.dart';
import '../domain/transaction_repository.dart';
import '../domain/transaction_rules.dart';

class DriftTransactionRepository implements TransactionRepository {
  DriftTransactionRepository(this._db);

  final AppDatabase _db;

  TransactionsDao get _dao => _db.transactionsDao;
  int get _now => _db.clock.nowMillis();

  // ------------------------------------------------------------- mapping

  static LedgerEntry toEntry(TransactionRow r) => LedgerEntry(
    id: r.id,
    workspaceId: r.workspaceId,
    accountId: r.accountId,
    kind: EntryKind.fromDb(r.type),
    amount: Money(r.amountPaisa),
    categoryId: r.categoryId,
    subcategoryId: r.subcategoryId,
    description: r.description,
    date: LocalDate.fromInt(r.localDate),
    occurredAt: DateTime.fromMillisecondsSinceEpoch(r.occurredAt),
    transferGroupId: r.transferGroupId,
    counterAccountId: r.counterAccountId,
    refundOfId: r.refundOfId,
    source: EntrySource.fromDb(r.source),
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt),
  );

  /// Every category, account and workspace, including archived and deleted
  /// ones, so old transactions can always be displayed.
  Future<_Lookups> _lookups() async {
    final cats = await _db.categoriesDao.getAll();
    final accs = await _db.accountsDao.getAll();
    final wss = await _db.workspacesDao.getAll();
    return _Lookups(
      categories: {for (final c in cats) c.id: DriftCategoryRepository.toDomain(c)},
      accounts: {for (final a in accs) a.id: DriftAccountRepository.toDomain(a)},
      workspaceTypes: {for (final w in wss) w.id: WorkspaceType.fromDb(w.type)},
    );
  }

  // ------------------------------------------- validated reference loading

  Future<WorkspaceRow?> _liveWorkspace(String id) async {
    final r = await _db.workspacesDao.findById(id);
    return r == null || r.deletedAt != null ? null : r;
  }

  Future<Account?> _liveAccount(String id) async {
    final r = await _db.accountsDao.findById(id);
    return r == null || r.deletedAt != null ? null : DriftAccountRepository.toDomain(r);
  }

  Future<Category?> _liveCategory(String? id) async {
    if (id == null) return null;
    final r = await _db.categoriesDao.findById(id);
    return r == null || r.deletedAt != null ? null : DriftCategoryRepository.toDomain(r);
  }

  Future<TransactionRow?> _liveRow(String id) async {
    final r = await _dao.findById(id);
    return r == null || r.deletedAt != null ? null : r;
  }

  /// Validates an income/expense draft. [existing] is set when editing.
  Future<String?> _validateEntry(EntryDraft d, {TransactionRow? existing}) async {
    TransactionRules.checkAmount(d.amount);
    final description = TransactionRules.normalizeDescription(d.description);
    if (await _liveWorkspace(d.workspaceId) == null) {
      throw const ValidationException(TxnError.workspaceNotFound);
    }
    TransactionRules.checkAccount(
      await _liveAccount(d.accountId),
      workspaceId: d.workspaceId,
      requireActive: existing == null || existing.accountId != d.accountId,
    );
    final category = await _liveCategory(d.categoryId);
    TransactionRules.checkCategory(
      category,
      expectedType: d.type.categoryType,
      workspaceId: d.workspaceId,
      requireActive: existing == null || existing.categoryId != d.categoryId,
    );
    TransactionRules.checkSubcategory(
      await _liveCategory(d.subcategoryId),
      subcategoryId: d.subcategoryId,
      category: category!,
      requireActive: existing == null || existing.subcategoryId != d.subcategoryId,
    );
    return description;
  }

  TransactionsCompanion _entryCompanion(EntryDraft d, String? description, int now) =>
      TransactionsCompanion(
        workspaceId: Value(d.workspaceId),
        accountId: Value(d.accountId),
        type: Value(d.type.kind.dbValue),
        amountPaisa: Value(d.amount.paisa),
        categoryId: Value(d.categoryId),
        subcategoryId: Value(d.subcategoryId),
        description: Value(description),
        localDate: Value(LocalDate.fromDateTime(d.occurredAt).toInt()),
        occurredAt: Value(d.occurredAt.millisecondsSinceEpoch),
        updatedAt: Value(now),
      );

  // --------------------------------------------------- income / expense

  @override
  Future<String> createEntry(EntryDraft d) => _db.transaction(() async {
    final description = await _validateEntry(d);
    final id = _db.ids.newId();
    final now = _now;
    await _dao.insertRow(_entryCompanion(d, description, now).copyWith(
      id: Value(id),
      source: Value(d.source.dbValue),
      recurringRuleId: Value(d.recurringRuleId),
      createdAt: Value(now),
    ));
    return id;
  });

  @override
  Future<List<String>> createEntries(List<EntryDraft> drafts) =>
      _db.transaction(() async => [for (final d in drafts) await createEntry(d)]);

  @override
  Future<void> updateEntry(String id, EntryDraft d) => _db.transaction(() async {
    final existing = await _liveRow(id);
    if (existing == null) throw const ValidationException(TxnError.entryNotFound);
    final kind = EntryKind.fromDb(existing.type);
    if (kind != EntryKind.income && kind != EntryKind.expense) {
      throw const ValidationException(TxnError.entryNotEditable);
    }
    final description = await _validateEntry(d, existing: existing);

    final refunded = Money(await _dao.refundedTotal(id));
    TransactionRules.checkExpenseEdit(newType: d.type, newAmount: d.amount, refunded: refunded);
    if (!refunded.isZero && d.workspaceId != existing.workspaceId) {
      // Refunds live in the expense's workspace and would be left behind.
      throw const ValidationException(TxnError.entryNotEditable, 'workspace change with refunds');
    }

    final now = _now;
    await _dao.updateRow(id, _entryCompanion(d, description, now));
    if (!refunded.isZero) {
      await _dao.moveRefundsToCategory(id,
          categoryId: d.categoryId, subcategoryId: d.subcategoryId, now: now);
    }
  });

  // ------------------------------------------------------------ transfer

  Future<(Account, Account, String?)> _validateTransfer(
    TransferDraft d, {
    List<TransactionRow>? existingLegs,
  }) async {
    TransactionRules.checkAmount(d.amount);
    final description = TransactionRules.normalizeDescription(d.description);
    final from = await _liveAccount(d.fromAccountId);
    final to = await _liveAccount(d.toAccountId);
    final oldOut = existingLegs?.firstWhere((r) => r.type == EntryKind.transferOut.dbValue);
    TransactionRules.checkTransferAccounts(
      from,
      to,
      requireActive: oldOut == null ||
          oldOut.accountId != d.fromAccountId ||
          oldOut.counterAccountId != d.toAccountId,
    );
    for (final a in [from!, to!]) {
      if (await _liveWorkspace(a.workspaceId) == null) {
        throw const ValidationException(TxnError.workspaceNotFound);
      }
    }
    return (from, to, description);
  }

  /// The two rows of a transfer. Each belongs to its own account's
  /// workspace (D4, rule 11).
  (TransactionsCompanion, TransactionsCompanion) _transferLegs(
    TransferDraft d,
    Account from,
    Account to,
    String? description,
    int now,
  ) {
    final common = TransactionsCompanion(
      amountPaisa: Value(d.amount.paisa),
      description: Value(description),
      localDate: Value(LocalDate.fromDateTime(d.occurredAt).toInt()),
      occurredAt: Value(d.occurredAt.millisecondsSinceEpoch),
      categoryId: const Value(null),
      subcategoryId: const Value(null),
      updatedAt: Value(now),
    );
    return (
      common.copyWith(
        workspaceId: Value(from.workspaceId),
        accountId: Value(from.id),
        counterAccountId: Value(to.id),
        type: Value(EntryKind.transferOut.dbValue),
      ),
      common.copyWith(
        workspaceId: Value(to.workspaceId),
        accountId: Value(to.id),
        counterAccountId: Value(from.id),
        type: Value(EntryKind.transferIn.dbValue),
      ),
    );
  }

  @override
  Future<String> createTransfer(TransferDraft d) => _db.transaction(() async {
    final (from, to, description) = await _validateTransfer(d);
    final groupId = _db.ids.newId();
    final now = _now;
    final (out, inn) = _transferLegs(d, from, to, description, now);
    for (final leg in [out, inn]) {
      await _dao.insertRow(leg.copyWith(
        id: Value(_db.ids.newId()),
        transferGroupId: Value(groupId),
        source: Value(d.source.dbValue),
        recurringRuleId: Value(d.recurringRuleId),
        createdAt: Value(now),
      ));
    }
    return groupId;
  });

  @override
  Future<void> updateTransfer(String groupId, TransferDraft d) => _db.transaction(() async {
    final legs = await _dao.findByGroup(groupId);
    final outRow = legs.where((r) => r.type == EntryKind.transferOut.dbValue).firstOrNull;
    final inRow = legs.where((r) => r.type == EntryKind.transferIn.dbValue).firstOrNull;
    if (legs.length != 2 || outRow == null || inRow == null) {
      throw const ValidationException(TxnError.entryNotFound);
    }
    final (from, to, description) = await _validateTransfer(d, existingLegs: legs);
    final (out, inn) = _transferLegs(d, from, to, description, _now);
    await _dao.updateRow(outRow.id, out);
    await _dao.updateRow(inRow.id, inn);
  });

  // -------------------------------------------------------------- refund

  @override
  Future<String> createRefund(RefundDraft d) => _db.transaction(() async {
    final original = await _liveRow(d.originalId);
    final description = await _validateRefund(d, original: original);
    final id = _db.ids.newId();
    final now = _now;
    await _dao.insertRow(TransactionsCompanion.insert(
      id: id,
      workspaceId: original!.workspaceId,
      accountId: d.accountId,
      type: EntryKind.refund.dbValue,
      amountPaisa: d.amount.paisa,
      categoryId: Value(original.categoryId),
      subcategoryId: Value(original.subcategoryId),
      description: Value(description),
      localDate: LocalDate.fromDateTime(d.occurredAt).toInt(),
      occurredAt: d.occurredAt.millisecondsSinceEpoch,
      refundOfId: Value(original.id),
      createdAt: now,
      updatedAt: now,
    ));
    return id;
  });

  @override
  Future<void> updateRefund(String id, RefundDraft d) => _db.transaction(() async {
    final existing = await _liveRow(id);
    if (existing == null || existing.type != EntryKind.refund.dbValue) {
      throw const ValidationException(TxnError.entryNotFound);
    }
    final original = await _liveRow(existing.refundOfId!);
    final description = await _validateRefund(
      d.copyWith(originalId: existing.refundOfId!),
      original: original,
      existing: existing,
    );
    await _dao.updateRow(id, TransactionsCompanion(
      accountId: Value(d.accountId),
      amountPaisa: Value(d.amount.paisa),
      description: Value(description),
      localDate: Value(LocalDate.fromDateTime(d.occurredAt).toInt()),
      occurredAt: Value(d.occurredAt.millisecondsSinceEpoch),
      updatedAt: Value(_now),
    ));
  });

  Future<String?> _validateRefund(
    RefundDraft d, {
    required TransactionRow? original,
    TransactionRow? existing,
  }) async {
    TransactionRules.checkAmount(d.amount);
    final description = TransactionRules.normalizeDescription(d.description);
    TransactionRules.checkRefund(
      original: original == null ? null : toEntry(original),
      alreadyRefunded: original == null
          ? Money.zero
          : Money(await _dao.refundedTotal(original.id, excludeId: existing?.id)),
      amount: d.amount,
    );
    TransactionRules.checkAccount(
      await _liveAccount(d.accountId),
      workspaceId: original!.workspaceId,
      requireActive: existing == null || existing.accountId != d.accountId,
    );
    return description;
  }

  // ------------------------------------------------------ delete / restore

  @override
  Future<DeletionReceipt> delete(String id) => _db.transaction(() async {
    final row = await _liveRow(id);
    if (row == null) throw const ValidationException(TxnError.entryNotFound);
    final ids = <String>[id];
    if (row.transferGroupId != null) {
      ids
        ..clear()
        ..addAll((await _dao.findByGroup(row.transferGroupId!)).map((r) => r.id));
    } else if (row.type == EntryKind.expense.dbValue) {
      ids.addAll((await _dao.refundsOf(id)).map((r) => r.id));
    }
    final now = _now;
    await _dao.setDeleted(ids, deletedAt: now, now: now);
    return DeletionReceipt(ids: ids);
  });

  @override
  Future<void> restore(DeletionReceipt receipt) => _db.transaction(() async {
    final rows = await _dao.findByIds(receipt.ids);
    final restoring = receipt.ids.toSet();
    for (final r in rows) {
      if (r.type != EntryKind.refund.dbValue || restoring.contains(r.refundOfId)) continue;
      // Restoring a refund on its own: its expense must still exist and the
      // refund limit must still hold.
      final original = await _liveRow(r.refundOfId!);
      TransactionRules.checkRefund(
        original: original == null ? null : toEntry(original),
        alreadyRefunded: Money(await _dao.refundedTotal(r.refundOfId!, excludeId: r.id)),
        amount: Money(r.amountPaisa),
      );
    }
    await _dao.setDeleted(receipt.ids, deletedAt: null, now: _now);
  });

  // -------------------------------------------------------------- queries

  @override
  Stream<HistoryPage> watchHistory(HistoryQuery query) async* {
    final lookups = await _lookups();
    final params = _toSqlParams(query, lookups);
    yield* _dao.watchHistory(params).asyncMap((result) async {
      final fresh = await _lookups();
      return HistoryPage(
        items: result.rows.map(fresh.toItem).toList(),
        hasMore: result.totalCount > result.rows.length,
      );
    });
  }

  HistorySqlParams _toSqlParams(HistoryQuery q, _Lookups lookups) {
    final f = q.filter;
    final types = <String>{
      for (final t in f.types)
        ...switch (t) {
          HistoryTypeFilter.income => [EntryKind.income.dbValue],
          HistoryTypeFilter.expense => [EntryKind.expense.dbValue, EntryKind.refund.dbValue],
          HistoryTypeFilter.transfer => [EntryKind.transferOut.dbValue, EntryKind.transferIn.dbValue],
        },
    };
    final search = f.search.trim().toLowerCase();
    return HistorySqlParams(
      workspaceIds: q.workspaceIds,
      dbTypes: types,
      categoryId: f.categoryId,
      subcategoryId: f.subcategoryId,
      accountId: f.accountId,
      fromDate: f.range?.start.toInt(),
      toDate: f.range?.end.toInt(),
      searchLike: search.isEmpty ? null : '%${_escapeLike(search)}%',
      searchCategoryIds: search.isEmpty ? const [] : lookups.categoriesMatching(search),
      limit: q.limit < 1 ? 1 : q.limit,
    );
  }

  static String _escapeLike(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  @override
  Stream<HistoryItem?> watchItem(String id) => _dao.watchById(id).asyncMap((row) async {
    if (row == null || row.deletedAt != null) return null;
    return (await _lookups()).toItem(row);
  });

  @override
  Future<List<LedgerEntry>> transferLegs(String transferGroupId) async =>
      (await _dao.findByGroup(transferGroupId)).map(toEntry).toList();

  @override
  Stream<List<HistoryItem>> watchRefundsOf(String expenseId) =>
      _dao.watchRefundsOf(expenseId).asyncMap((rows) async {
        final lk = await _lookups();
        return rows.map(lk.toItem).toList();
      });

  @override
  Future<Money> refundedTotal(String expenseId) async =>
      Money(await _dao.refundedTotal(expenseId));

  @override
  Stream<List<RecentTemplate>> watchRecentTemplates(
    List<String> workspaceIds, {
    int limit = 8,
  }) =>
      // Fetch extra rows: templates with archived references are skipped.
      _dao.watchRecent(workspaceIds, limit * 2).asyncMap((rows) async {
        final lk = await _lookups();
        final out = <RecentTemplate>[];
        for (final r in rows) {
          final cat = lk.categories[r.categoryId];
          final sub = r.subcategoryId == null ? null : lk.categories[r.subcategoryId];
          final acc = lk.accounts[r.accountId];
          if (cat == null || !cat.isActive || acc == null || !acc.isActive) continue;
          if (r.subcategoryId != null && (sub == null || !sub.isActive)) continue;
          out.add(RecentTemplate(
            sourceEntryId: r.id,
            type: r.type == EntryKind.income.dbValue ? EntryType.income : EntryType.expense,
            workspaceId: r.workspaceId,
            accountId: r.accountId,
            amount: Money(r.amountPaisa),
            category: cat,
            subcategory: sub,
            description: r.description,
          ));
          if (out.length == limit) break;
        }
        return out;
      });
}

class _Lookups {
  _Lookups({
    required this.categories,
    required this.accounts,
    required this.workspaceTypes,
  });

  final Map<String, Category> categories;
  final Map<String, Account> accounts;
  final Map<String, WorkspaceType> workspaceTypes;

  HistoryItem toItem(TransactionRow r) => HistoryItem(
    entry: DriftTransactionRepository.toEntry(r),
    workspaceType: workspaceTypes[r.workspaceId]!,
    account: accounts[r.accountId]!,
    category: r.categoryId == null ? null : categories[r.categoryId],
    subcategory: r.subcategoryId == null ? null : categories[r.subcategoryId],
    counterAccount: r.counterAccountId == null ? null : accounts[r.counterAccountId],
  );

  /// IDs of categories whose stored, English or Bangla name contains [q].
  List<String> categoriesMatching(String q) => [
    for (final c in categories.values)
      if (_names(c).any((n) => n.toLowerCase().contains(q))) c.id,
  ];

  static Iterable<String> _names(Category c) sync* {
    yield c.name;
    final seeded = c.systemKey == null ? null : defaultCategoryByKey[c.systemKey];
    if (seeded != null) {
      yield seeded.en;
      yield seeded.bn;
    }
  }
}
