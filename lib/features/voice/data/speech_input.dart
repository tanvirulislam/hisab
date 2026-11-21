import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Why listening could not start or stopped early.
enum SpeechFailure {
  /// The user refused the microphone permission.
  permissionDenied,

  /// No speech recognition service on this device.
  unavailable,

  /// Nothing understandable was heard.
  noMatch,

  /// Network or service error (some engines need a connection).
  other,
}

/// Speech-to-text, wrapped so the voice screen can be tested and the
/// engine replaced (§9.2).
abstract interface class SpeechInput {
  /// Prepares the recognizer; asks for the microphone permission on first
  /// use. Returns null when ready, otherwise why it is not.
  Future<SpeechFailure?> initialize();

  /// Recognizer locale for [languageCode] ('bn' / 'en'), or null if the
  /// device does not list one. Listening may still work with a default.
  Future<String?> localeFor(String languageCode);

  /// Streams recognised text to [onText] until [stop] or a pause in speech.
  /// [onDone] runs once when listening ends, with a failure if one occurred.
  Future<void> listen({
    required String? localeId,
    required void Function(String text, bool isFinal) onText,
    required void Function(SpeechFailure? failure) onDone,
  });

  Future<void> stop();

  Future<void> cancel();
}

class DeviceSpeechInput implements SpeechInput {
  final _stt = SpeechToText();
  void Function(SpeechFailure?)? _onDone;

  void _finish(SpeechFailure? failure) {
    final done = _onDone;
    _onDone = null;
    done?.call(failure);
  }

  static SpeechFailure _map(SpeechRecognitionError e) => switch (e.errorMsg) {
    'error_permission' || 'error_insufficient_permissions' => SpeechFailure.permissionDenied,
    'error_no_match' || 'error_speech_timeout' => SpeechFailure.noMatch,
    _ => SpeechFailure.other,
  };

  @override
  Future<SpeechFailure?> initialize() async {
    try {
      final ok = await _stt.initialize(
        onError: (e) => _finish(_map(e)),
        onStatus: (status) {
          if (status == SpeechToText.doneStatus) _finish(null);
        },
      );
      if (ok) return null;
      return await _stt.hasPermission ? SpeechFailure.unavailable : SpeechFailure.permissionDenied;
    } on Object {
      return SpeechFailure.unavailable;
    }
  }

  @override
  Future<String?> localeFor(String languageCode) async {
    final locales = await _stt.locales();
    String norm(String id) => id.replaceAll('-', '_').toLowerCase();
    final preferred = languageCode == 'bn' ? ['bn_bd', 'bn_in'] : ['en_us', 'en_gb', 'en_in'];
    for (final p in preferred) {
      final match = locales.where((l) => norm(l.localeId) == p).firstOrNull;
      if (match != null) return match.localeId;
    }
    return locales.where((l) => norm(l.localeId).startsWith('${languageCode}_')).firstOrNull?.localeId;
  }

  @override
  Future<void> listen({
    required String? localeId,
    required void Function(String text, bool isFinal) onText,
    required void Function(SpeechFailure? failure) onDone,
  }) async {
    _onDone = onDone;
    await _stt.listen(
      onResult: (r) => onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() async {
    _onDone = null;
    await _stt.cancel();
  }
}
