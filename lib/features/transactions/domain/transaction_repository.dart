import '../../../core/utils/money.dart';
import 'drafts.dart';
import 'history_filter.dart';
import 'ledger_entry.dart';

/// A page of history. [hasMore] means older rows exist beyond this page.
class HistoryPage {
  const HistoryPage({required this.items, required this.hasMore});

  final List<HistoryItem> items;
  final bool hasMore;
}

abstract interface class TransactionRepository {
  /// Creates an income or expense. Returns the new entry ID.
  /// Throws [ValidationException] and persists nothing when invalid.
  Future<String> createEntry(EntryDraft draft);

  /// Creates several entries in one DB transaction: all or nothing
  /// (voice entry with several items).
  Future<List<String>> createEntries(List<EntryDraft> drafts);

  Future<void> updateEntry(String id, EntryDraft draft);

  /// Creates both transfer rows atomically. Returns the transfer group ID.
  Future<String> createTransfer(TransferDraft draft);

  Future<void> updateTransfer(String transferGroupId, TransferDraft draft);

  Future<String> createRefund(RefundDraft draft);

  Future<void> updateRefund(String id, RefundDraft draft);

  /// Soft-deletes an entry together with its dependants: the other transfer
  /// row, or an expense's refunds (D7).
  Future<DeletionReceipt> delete(String id);

  /// Undoes [delete]. Re-checks refund limits.
  Future<void> restore(DeletionReceipt receipt);

  Stream<HistoryPage> watchHistory(HistoryQuery query);

  /// One entry with its references, or null once deleted.
  Stream<HistoryItem?> watchItem(String id);

  /// Rows belonging to the same transfer.
  Future<List<LedgerEntry>> transferLegs(String transferGroupId);

  /// Refunds of an expense that are not deleted.
  Stream<List<HistoryItem>> watchRefundsOf(String expenseId);

  Future<Money> refundedTotal(String expenseId);

  /// Most recent distinct income/expense combinations, for Repeat.
  Stream<List<RecentTemplate>> watchRecentTemplates(
    List<String> workspaceIds, {
    int limit = 8,
  });
}
