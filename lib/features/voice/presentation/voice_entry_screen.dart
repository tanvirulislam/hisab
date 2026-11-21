import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/providers.dart';
import '../../../core/services/local_prefs.dart';
import '../../../l10n/l10n.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/speech_input.dart';
import 'voice_providers.dart';

/// Voice entry (§9.1 steps 1–4): pick a language, speak, see the text.
/// The text stays editable, so the user can correct it or type instead
/// when speech recognition is not available.
class VoiceEntryScreen extends ConsumerStatefulWidget {
  const VoiceEntryScreen({super.key});

  @override
  ConsumerState<VoiceEntryScreen> createState() => _VoiceEntryScreenState();
}

enum _MicState { idle, starting, listening }

class _VoiceEntryScreenState extends ConsumerState<VoiceEntryScreen> {
  final _text = TextEditingController();
  late String _language;
  _MicState _mic = _MicState.idle;
  bool _initialized = false;
  SpeechFailure? _failure;

  SpeechInput get _speech => ref.read(speechInputProvider);

  @override
  void initState() {
    super.initState();
    final saved = ref.read(localPrefsProvider).getString(LocalPrefKeys.voiceLanguage);
    _language = saved == 'en' || saved == 'bn'
        ? saved!
        : (ref.read(appSettingsProvider).value ?? const AppSettings()).language.code;
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (_mic != _MicState.idle) _speech.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    if (_mic == _MicState.listening) {
      await _speech.stop();
      return;
    }
    if (_mic != _MicState.idle) return;
    setState(() {
      _mic = _MicState.starting;
      _failure = null;
    });
    if (!_initialized) {
      final failure = await _speech.initialize();
      if (!mounted) return;
      if (failure != null) {
        setState(() {
          _mic = _MicState.idle;
          _failure = failure;
        });
        return;
      }
      _initialized = true;
    }
    final locale = await _speech.localeFor(_language);
    if (!mounted) return;
    final before = _text.text.trim();
    setState(() => _mic = _MicState.listening);
    await _speech.listen(
      localeId: locale,
      onText: (words, _) {
        if (!mounted) return;
        // New speech is appended to what is already there.
        _text.text = before.isEmpty ? words : '$before $words';
        _text.selection = TextSelection.collapsed(offset: _text.text.length);
      },
      onDone: (failure) {
        if (!mounted) return;
        setState(() {
          _mic = _MicState.idle;
          if (failure != null && !(failure == SpeechFailure.noMatch && _text.text.trim().isNotEmpty)) {
            _failure = failure;
          }
        });
      },
    );
  }

  void _setLanguage(String code) {
    setState(() => _language = code);
    ref.read(localPrefsProvider).setString(LocalPrefKeys.voiceLanguage, code);
  }

  void _continue() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    if (_mic != _MicState.idle) _speech.stop();
    context.push(Routes.voiceConfirm, extra: text);
  }

  String _failureText(AppLocalizations l, SpeechFailure f) => switch (f) {
    SpeechFailure.permissionDenied => l.voicePermissionDenied,
    SpeechFailure.unavailable => l.voiceUnavailable,
    SpeechFailure.noMatch => l.voiceNoMatch,
    SpeechFailure.other => l.voiceFailed,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final listening = _mic == _MicState.listening;
    return Scaffold(
      appBar: AppBar(leading: const CloseButton(), title: Text(l.voiceTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'bn', label: Text(l.languageBangla)),
              ButtonSegment(value: 'en', label: Text(l.languageEnglish)),
            ],
            selected: {_language},
            onSelectionChanged: listening ? null : (s) => _setLanguage(s.first),
          ),
          const SizedBox(height: 32),
          Center(
            child: SizedBox.square(
              dimension: 96,
              child: FilledButton(
                key: const ValueKey('voice-mic'),
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: listening ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
                onPressed: _mic == _MicState.starting ? null : _toggleMic,
                child: _mic == _MicState.starting
                    ? const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3))
                    : Icon(listening ? Icons.stop : Icons.mic, size: 44, semanticLabel: listening ? l.voiceStop : l.voiceStart),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            listening ? l.voiceListening : l.voiceTapToSpeak,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            _language == 'bn' ? l.voiceExampleBn : l.voiceExampleEn,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (_failure != null) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_failureText(l, _failure!),
                          style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            key: const ValueKey('voice-text'),
            controller: _text,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.voiceRecognized,
              hintText: l.voiceTypeHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _text.text.trim().isEmpty ? null : _continue,
            icon: const Icon(Icons.arrow_forward),
            label: Text(l.voiceContinue),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.pushReplacement(Routes.add),
            child: Text(l.voiceManualInstead),
          ),
        ],
      ),
    );
  }
}
