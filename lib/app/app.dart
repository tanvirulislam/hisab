import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/backup/presentation/backup_providers.dart';
import '../features/notifications/presentation/notification_coordinator.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/presentation/settings_providers.dart';
import '../l10n/l10n.dart';
import 'app_maintenance.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class HisabApp extends ConsumerStatefulWidget {
  const HisabApp({super.key});

  @override
  ConsumerState<HisabApp> createState() => _HisabAppState();
}

class _HisabAppState extends ConsumerState<HisabApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Roll budgets over now and every time the app comes back to the
    // foreground. The Drive backup runs then too, if it is due (D22).
    _lifecycle = AppLifecycleListener(onResume: _onForeground);
    _onForeground();
  }

  void _onForeground() {
    ref.read(appMaintenanceProvider).run();
    ref.read(backupControllerProvider.notifier).autoBackupIfDue();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    // Keeps reminders and budget alerts in line with the data.
    ref.watch(notificationCoordinatorProvider);

    // The database could not be opened: show a safe error screen instead of
    // running with partial state.
    if (settingsAsync.hasError && !settingsAsync.hasValue) {
      return _StartupErrorApp(error: settingsAsync.error!);
    }

    final settings = settingsAsync.value ?? const AppSettings();
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (settings.theme) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      },
      locale: Locale(settings.language.code),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) {
        final l10n = context.l10n;
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 56),
                  const SizedBox(height: 16),
                  Text(l10n.startupErrorTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(l10n.startupErrorMessage, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
