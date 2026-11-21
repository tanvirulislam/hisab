import '../../features/accounts/domain/account_repository.dart';
import '../../features/categories/domain/category_repository.dart';
import '../../features/transactions/domain/transaction_rules.dart';
import '../../l10n/l10n.dart';
import '../errors/app_exception.dart';

/// Localized, user-facing text for an error. Unknown errors get a generic
/// message: technical details are never shown to users.
String errorMessage(AppLocalizations l, Object error) {
  if (error is! AppException) return l.errorMessage;
  return switch (error.code) {
    TxnError.amountInvalid => l.errAmountInvalid,
    TxnError.accountNotFound || AccountError.notFound => l.errAccountNotFound,
    TxnError.accountInactive => l.errAccountInactive,
    TxnError.accountWorkspaceMismatch => l.errAccountWorkspace,
    TxnError.categoryNotFound || CategoryError.notFound => l.errCategoryNotFound,
    TxnError.categoryInactive => l.errCategoryInactive,
    TxnError.categoryTypeMismatch ||
    TxnError.categoryWorkspaceMismatch ||
    TxnError.categoryNotTopLevel ||
    TxnError.subcategoryMismatch => l.errCategoryInvalid,
    TxnError.sameAccountTransfer => l.errSameAccount,
    TxnError.entryNotFound => l.errEntryNotFound,
    TxnError.entryNotEditable || TxnError.typeChangeWithRefunds => l.errHasRefunds,
    TxnError.refundOriginalInvalid => l.errEntryNotFound,
    TxnError.refundExceedsOriginal => l.errRefundTooLarge,
    TxnError.amountBelowRefunded => l.errAmountBelowRefunded,
    TxnError.descriptionTooLong => l.errDescriptionTooLong,
    TxnError.workspaceNotFound => l.errorMessage,
    CategoryError.nameInvalid || AccountError.nameInvalid => l.errNameInvalid,
    CategoryError.nameDuplicate || AccountError.nameDuplicate => l.errNameDuplicate,
    CategoryError.protected => l.errCategoryProtected,
    CategoryError.inUse => l.errCategoryInUse,
    CategoryError.parentArchived => l.errParentArchived,
    CategoryError.parentInvalid || CategoryError.reassignInvalid => l.errCategoryInvalid,
    AccountError.inUse => l.errAccountInUse,
    AccountError.balanceInvalid => l.errAmountInvalid,
    _ => l.errorMessage,
  };
}
