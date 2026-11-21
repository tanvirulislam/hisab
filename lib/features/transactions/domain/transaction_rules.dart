import '../../../core/errors/app_exception.dart';
import '../../../core/utils/money.dart';
import '../../accounts/domain/account.dart';
import '../../categories/domain/category.dart';
import 'ledger_entry.dart';

/// Validation error codes. Presentation code maps them to localized text.
abstract final class TxnError {
  static const amountInvalid = 'txn.amount_invalid';
  static const workspaceNotFound = 'txn.workspace_not_found';
  static const accountNotFound = 'txn.account_not_found';
  static const accountInactive = 'txn.account_inactive';
  static const accountWorkspaceMismatch = 'txn.account_workspace_mismatch';
  static const categoryNotFound = 'txn.category_not_found';
  static const categoryInactive = 'txn.category_inactive';
  static const categoryTypeMismatch = 'txn.category_type_mismatch';
  static const categoryWorkspaceMismatch = 'txn.category_workspace_mismatch';
  static const categoryNotTopLevel = 'txn.category_not_top_level';
  static const subcategoryMismatch = 'txn.subcategory_mismatch';
  static const sameAccountTransfer = 'txn.same_account_transfer';
  static const entryNotFound = 'txn.entry_not_found';
  static const entryNotEditable = 'txn.entry_not_editable';
  static const refundOriginalInvalid = 'txn.refund_original_invalid';
  static const refundExceedsOriginal = 'txn.refund_exceeds_original';
  static const amountBelowRefunded = 'txn.amount_below_refunded';
  static const typeChangeWithRefunds = 'txn.type_change_with_refunds';
  static const descriptionTooLong = 'txn.description_too_long';
}

/// Pure business rules for ledger writes (PRD §6.6, §23). The repository
/// loads the referenced rows inside the write transaction and calls these
/// checks before anything is persisted.
abstract final class TransactionRules {
  static const int maxDescriptionLength = 500;

  static Never _fail(String code, [String? detail]) =>
      throw ValidationException(code, detail);

  static void checkAmount(Money amount) {
    if (amount.paisa <= 0 || amount.paisa > Money.maxInputPaisa) {
      _fail(TxnError.amountInvalid, '$amount');
    }
  }

  /// Trims, turns empty into null, and enforces the length limit.
  static String? normalizeDescription(String? text) {
    final t = text?.trim();
    if (t == null || t.isEmpty) return null;
    if (t.length > maxDescriptionLength) _fail(TxnError.descriptionTooLong);
    return t;
  }

  /// [requireActive] is false when editing an entry and the account was not
  /// changed, so old entries on an archived account can still be edited.
  static void checkAccount(
    Account? account, {
    required String workspaceId,
    required bool requireActive,
  }) {
    if (account == null) _fail(TxnError.accountNotFound);
    if (account.workspaceId != workspaceId) {
      _fail(TxnError.accountWorkspaceMismatch); // rule 11
    }
    if (requireActive && !account.isActive) _fail(TxnError.accountInactive);
  }

  static void checkCategory(
    Category? category, {
    required CategoryType expectedType,
    required String workspaceId,
    required bool requireActive,
  }) {
    if (category == null) _fail(TxnError.categoryNotFound);
    if (category.isSubcategory) _fail(TxnError.categoryNotTopLevel);
    if (category.type != expectedType) _fail(TxnError.categoryTypeMismatch);
    if (category.workspaceId != null && category.workspaceId != workspaceId) {
      _fail(TxnError.categoryWorkspaceMismatch); // rule 11
    }
    if (requireActive && !category.isActive) _fail(TxnError.categoryInactive);
  }

  static void checkSubcategory(
    Category? subcategory, {
    required String? subcategoryId,
    required Category category,
    required bool requireActive,
  }) {
    if (subcategoryId == null) return;
    if (subcategory == null || subcategory.parentId != category.id) {
      _fail(TxnError.subcategoryMismatch);
    }
    if (requireActive && !subcategory.isActive) _fail(TxnError.categoryInactive);
  }

  static void checkTransferAccounts(
    Account? from,
    Account? to, {
    required bool requireActive,
  }) {
    if (from == null || to == null) _fail(TxnError.accountNotFound);
    if (from.id == to.id) _fail(TxnError.sameAccountTransfer);
    if (requireActive && (!from.isActive || !to.isActive)) {
      _fail(TxnError.accountInactive);
    }
  }

  /// [alreadyRefunded] excludes the refund being edited.
  static void checkRefund({
    required LedgerEntry? original,
    required Money alreadyRefunded,
    required Money amount,
  }) {
    if (original == null || original.kind != EntryKind.expense) {
      _fail(TxnError.refundOriginalInvalid);
    }
    if (alreadyRefunded + amount > original.amount) {
      _fail(TxnError.refundExceedsOriginal);
    }
  }

  /// Editing an expense that has refunds: the type cannot change and the
  /// amount cannot drop below what was already refunded.
  static void checkExpenseEdit({
    required EntryType newType,
    required Money newAmount,
    required Money refunded,
  }) {
    if (refunded.isZero) return;
    if (newType != EntryType.expense) _fail(TxnError.typeChangeWithRefunds);
    if (newAmount < refunded) _fail(TxnError.amountBelowRefunded);
  }
}
