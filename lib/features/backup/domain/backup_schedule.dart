/// When the automatic backup runs (D22). Pure, so it is unit-tested.
abstract final class BackupSchedule {
  /// Time between automatic backups.
  static const interval = Duration(hours: 24);

  /// After a failed attempt, wait this long before trying again, so a phone
  /// without internet does not retry on every resume.
  static const retryDelay = Duration(hours: 1);

  /// A backup is due when there is user data, it changed since the last
  /// successful backup, that backup is at least [interval] old, and no
  /// attempt failed in the last [retryDelay].
  static bool isDue({
    required DateTime now,
    required DateTime? lastSuccess,
    required String? lastFingerprint,
    required String currentFingerprint,
    required bool hasUserData,
    DateTime? lastFailure,
  }) {
    if (!hasUserData) return false;
    if (lastFingerprint == currentFingerprint) return false;
    if (lastSuccess != null && now.difference(lastSuccess) < interval) return false;
    if (lastFailure != null &&
        (lastSuccess == null || lastFailure.isAfter(lastSuccess)) &&
        now.difference(lastFailure) < retryDelay) {
      return false;
    }
    return true;
  }
}

/// Which backups to delete so only the newest [keep] stay (D22).
abstract final class BackupRetention {
  static const int keepOnDrive = 10;
  static const int keepSafety = 3;

  /// The items beyond the newest [keep], by [createdAt].
  static List<T> toDelete<T>(List<T> items, DateTime Function(T) createdAt, {required int keep}) {
    final sorted = [...items]..sort((a, b) => createdAt(b).compareTo(createdAt(a)));
    return sorted.length <= keep ? const [] : sorted.sublist(keep);
  }
}
