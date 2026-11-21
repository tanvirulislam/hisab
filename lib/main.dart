import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
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
  try {
    await container.read(appSettingsProvider.future);
  } catch (_) {}

  runApp(UncontrolledProviderScope(container: container, child: const HisabApp()));
}
