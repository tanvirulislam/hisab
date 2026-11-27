/// Typed errors raised by the domain and data layers.
///
/// Presentation code turns [code] into a localized message. Never show
/// [debugMessage] to the user.
sealed class AppException implements Exception {
  const AppException(this.code, [this.debugMessage]);

  final String code;
  final String? debugMessage;

  @override
  String toString() => '$runtimeType($code${debugMessage == null ? '' : ': $debugMessage'})';
}

/// Input failed a business rule (e.g. amount <= 0, account from another
/// workspace). Nothing was persisted.
final class ValidationException extends AppException {
  const ValidationException(super.code, [super.debugMessage]);
}

final class NotFoundException extends AppException {
  const NotFoundException(super.code, [super.debugMessage]);
}

/// The operation conflicts with existing data (e.g. deleting a category
/// that transactions still use).
final class ConflictException extends AppException {
  const ConflictException(super.code, [super.debugMessage]);
}

/// Unexpected storage failure (DB error, corrupt file).
final class StorageException extends AppException {
  const StorageException(super.code, [super.debugMessage]);
}

/// Backup or restore failed (D22). [code] is one of `BackupError`'s
/// constants. Nothing was changed when a restore throws this.
final class BackupException extends AppException {
  const BackupException(super.code, [super.debugMessage]);
}
