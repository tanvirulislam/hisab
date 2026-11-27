import '../../features/accounts/domain/account_repository.dart';
import '../../features/backup/domain/backup_file.dart';
import '../../features/budgets/domain/budget.dart';
import '../../features/categories/domain/category_repository.dart';
import '../../features/loans/domain/loan_repository.dart';
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
    BudgetError.amountInvalid => l.errAmountInvalid,
    BudgetError.thresholdInvalid => l.errThresholdInvalid,
    BudgetError.categoryInvalid => l.errCategoryInvalid,
    BudgetError.duplicate => l.errBudgetDuplicate,
    BudgetError.notFound => l.errEntryNotFound,
    LoanError.amountInvalid => l.errAmountInvalid,
    LoanError.nameInvalid => l.errNameInvalid,
    LoanError.nameDuplicate => l.errNameDuplicate,
    LoanError.personNotFound || LoanError.entryNotFound => l.errEntryNotFound,
    LoanError.personInUse => l.errLoanPersonInUse,
    LoanError.accountRequired => l.errLoanAccountRequired,
    LoanError.accountNotFound => l.errAccountNotFound,
    LoanError.accountInactive => l.errAccountInactive,
    LoanError.exceedsOutstanding => l.errLoanExceeds,
    LoanError.noteTooLong => l.errDescriptionTooLong,
    BackupError.notConfigured => l.errBackupNotConfigured,
    BackupError.notSignedIn => l.errBackupNotSignedIn,
    BackupError.signInCancelled => l.errBackupSignInCancelled,
    BackupError.signInFailed => l.errBackupSignInFailed,
    BackupError.network => l.errBackupNetwork,
    BackupError.driveQuota => l.errBackupDriveQuota,
    BackupError.driveError => l.errBackupDrive,
    BackupError.corruptFile => l.errBackupCorrupt,
    BackupError.checksumMismatch => l.errBackupChecksum,
    BackupError.unknownFormat => l.errBackupUnknownFormat,
    BackupError.tooNew => l.errBackupTooNew,
    BackupError.tooOld => l.errBackupTooOld,
    BackupError.invalidData => l.errBackupInvalid,
    BackupError.busy => l.errBackupBusy,
    BackupError.noSafetyBackup => l.errBackupNoSafety,
    _ => l.errorMessage,
  };
}

/// Text for a stored backup error code (the Backup screen's "last backup
/// failed" line).
String backupErrorText(AppLocalizations l, String code) =>
    errorMessage(l, BackupException(code));
