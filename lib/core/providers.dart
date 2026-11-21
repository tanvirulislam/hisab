import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database/app_database.dart';
import 'services/clock.dart';
import 'services/local_prefs.dart';

part 'providers.g.dart';

/// The single app-wide database. Tests override this with an in-memory DB.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
}

/// Must be overridden at startup with an initialised [LocalPrefs].
@Riverpod(keepAlive: true)
LocalPrefs localPrefs(Ref ref) =>
    throw UnimplementedError('localPrefsProvider must be overridden');

@Riverpod(keepAlive: true)
Clock clock(Ref ref) => ref.watch(appDatabaseProvider).clock;
