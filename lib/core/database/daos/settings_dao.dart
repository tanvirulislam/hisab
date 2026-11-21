import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [AppSettingsTable])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  Stream<Map<String, String>> watchAll() => select(appSettingsTable)
      .watch()
      .map((rows) => {for (final r in rows) r.key: r.value});

  Future<Map<String, String>> getAll() async {
    final rows = await select(appSettingsTable).get();
    return {for (final r in rows) r.key: r.value};
  }

  Future<void> put(String key, String value, int nowMillis) =>
      into(appSettingsTable).insertOnConflictUpdate(
        AppSettingsTableCompanion.insert(key: key, value: value, updatedAt: nowMillis),
      );
}
