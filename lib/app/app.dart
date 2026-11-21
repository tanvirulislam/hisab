import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/domain/app_settings.dart';
import '../features/settings/presentation/settings_providers.dart';
import '../l10n/l10n.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class HisabApp extends ConsumerWidget {
  const HisabApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);

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
