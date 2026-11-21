import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/week_start.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../domain/app_settings.dart';
import 'settings_providers.dart';

/// A known date for each week start, used only to get its localized name.
final _sampleDay = {
  WeekStart.saturday: DateTime(2026, 11, 21),
  WeekStart.sunday: DateTime(2026, 11, 22),
  WeekStart.monday: DateTime(2026, 11, 23),
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repo = ref.read(settingsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moreSettings)),
      body: AsyncValueView(
        value: ref.watch(appSettingsProvider),
        onRetry: () => ref.invalidate(appSettingsProvider),
        data: (settings) => ListView(
          children: [
            _SectionHeader(l10n.settingsLanguage),
            RadioGroup<AppLanguage>(
              groupValue: settings.language,
              onChanged: (v) => v == null ? null : repo.setLanguage(v),
              child: Column(
                children: [
                  RadioListTile(value: AppLanguage.bangla, title: Text(l10n.languageBangla)),
                  RadioListTile(value: AppLanguage.english, title: Text(l10n.languageEnglish)),
                ],
              ),
            ),
            SwitchListTile(
              value: settings.banglaDigits,
              onChanged: settings.language == AppLanguage.bangla
                  ? repo.setBanglaDigits
                  : null,
              title: Text(l10n.settingsBanglaDigits),
              subtitle: Text(l10n.settingsBanglaDigitsHint),
            ),
            const Divider(),
            _SectionHeader(l10n.settingsWeekStart),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<WeekStart>(
                showSelectedIcon: false,
                segments: [
                  for (final w in WeekStart.values)
                    ButtonSegment(
                      value: w,
                      label: Text(DateFormat.EEEE(settings.language.code).format(_sampleDay[w]!)),
                    ),
                ],
                selected: {settings.weekStart},
                onSelectionChanged: (s) => repo.setWeekStart(s.first),
              ),
            ),
            const Divider(),
            _SectionHeader(l10n.settingsTheme),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<AppThemePreference>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: AppThemePreference.system,
                    label: Text(l10n.themeSystem),
                    icon: const Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment(
                    value: AppThemePreference.light,
                    label: Text(l10n.themeLight),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemePreference.dark,
                    label: Text(l10n.themeDark),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {settings.theme},
                onSelectionChanged: (s) => repo.setTheme(s.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.secondary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
