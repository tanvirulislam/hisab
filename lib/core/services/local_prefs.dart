import 'package:shared_preferences/shared_preferences.dart';

/// Per-device conveniences that are NOT part of backups (D10): last-used
/// workspace scope, last-used account, and so on.
abstract interface class LocalPrefs {
  String? getString(String key);
  Future<void> setString(String key, String value);
}

abstract final class LocalPrefKeys {
  static const String workspaceScope = 'workspace_scope';
  static const String lastAccountId = 'last_account_id';
  static const String lastEntryWorkspaceId = 'last_entry_workspace_id';

  /// Highest alert level already announced per budget (JSON map), so each
  /// threshold notifies once on this device.
  static const String budgetAlertLevels = 'budget_alert_levels';

  /// Last speech language chosen on the voice screen ('bn' / 'en').
  static const String voiceLanguage = 'voice_language';

  static const Set<String> all = {
    workspaceScope,
    lastAccountId,
    lastEntryWorkspaceId,
    budgetAlertLevels,
    voiceLanguage,
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
