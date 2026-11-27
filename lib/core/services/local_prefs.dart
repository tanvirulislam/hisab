import 'package:shared_preferences/shared_preferences.dart';

/// Per-device conveniences that are NOT part of backups (D10): last-used
/// account, and so on.
abstract interface class LocalPrefs {
  String? getString(String key);
  Future<void> setString(String key, String value);
}

abstract final class LocalPrefKeys {
  static const String lastAccountId = 'last_account_id';

  /// Highest alert level already announced per budget (JSON map), so each
  /// threshold notifies once on this device.
  static const String budgetAlertLevels = 'budget_alert_levels';

  /// Last speech language chosen on the voice screen ('bn' / 'en').
  static const String voiceLanguage = 'voice_language';

  // Drive backup (D22). Per-device state, never part of a backup.
  /// Epoch millis of the last successful backup.
  static const String backupLastSuccess = 'backup_last_success';

  /// Data fingerprint at the last successful backup.
  static const String backupFingerprint = 'backup_fingerprint';

  /// Last failure as JSON `{"code": ..., "at": epochMillis}`, or empty.
  static const String backupLastError = 'backup_last_error';

  /// '1' while the user is signed in for backups, so start-up only tries the
  /// silent sign-in for someone who signed in before.
  static const String backupSignedIn = 'backup_signed_in';

  /// Drive ID of the "Hisab Backup" folder.
  static const String backupFolderId = 'backup_folder_id';

  /// '1' once the fresh-install restore offer was answered or is no longer needed.
  static const String backupRestoreOfferDone = 'backup_restore_offer_done';

  static const Set<String> all = {
    lastAccountId,
    budgetAlertLevels,
    voiceLanguage,
    backupLastSuccess,
    backupFingerprint,
    backupLastError,
    backupFolderId,
    backupSignedIn,
    backupRestoreOfferDone,
  };
}

class SharedLocalPrefs implements LocalPrefs {
  SharedLocalPrefs._(this._prefs);

  final SharedPreferencesWithCache _prefs;

  static Future<SharedLocalPrefs> create() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: LocalPrefKeys.all,
      ),
    );
    return SharedLocalPrefs._(prefs);
  }

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
}

class InMemoryLocalPrefs implements LocalPrefs {
  InMemoryLocalPrefs([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;
}
