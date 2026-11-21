import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/notification_routing.dart';
import 'core/notifications/notification_providers.dart';
import 'core/providers.dart';
import 'core/services/local_prefs.dart';
import 'features/settings/presentation/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedLocalPrefs.create();
  final container = ProviderContainer(
    overrides: [localPrefsProvider.overrideWithValue(prefs)],
    // Database errors must surface, not be silently retried.
    retry: (_, _) => null,
  );

  // Open the database, run seeding and load settings before the first frame,
  // so the app starts in the right language and theme with no flicker.
  // Failures are shown by HisabApp's startup error screen.
  //
  // The subscription matters: Riverpod pauses a stream provider that nobody
  // listens to, so a bare `read(...future)` never receives its first value
  // and the app would stay on the launch screen forever.
  final startupSettings = container.listen(appSettingsProvider, (_, _) {});
  try {
    await container.read(appSettingsProvider.future);
  } catch (_) {}

  // Month and weekday names in both languages, also for notification text
  // built outside the widget tree.
  await initializeDateFormatting();

  final notifications = container.read(notificationServiceProvider);
  String? launchPayload;
  try {
    await notifications.initialize(onTap: (p) => openNotificationPayload(container, p));
    launchPayload = await notifications.launchPayload();
  } on Object catch (e) {
    // The app works without notifications.
    debugPrint('Notifications unavailable: $e');
  }

  runApp(UncontrolledProviderScope(container: container, child: const HisabApp()));
  startupSettings.close();
  if (launchPayload != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => openNotificationPayload(container, launchPayload));
  }
}
