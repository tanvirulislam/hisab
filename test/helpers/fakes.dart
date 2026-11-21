import 'package:hisab/core/notifications/notification_service.dart';
import 'package:hisab/features/voice/data/speech_input.dart';

typedef Notice = ({int id, String channel, String title, String body, String? payload, DateTime? at});

/// Records notifications instead of showing them.
class RecordingNotifications implements NotificationService {
  bool permitted = true;
  int permissionRequests = 0;
  final List<Notice> shown = [];
  final Map<int, Notice> scheduled = {};

  @override
  Future<void> initialize({required void Function(String? payload) onTap}) async {}

  @override
  Future<String?> launchPayload() async => null;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permitted;
  }

  @override
  Future<void> show({
    required int id,
    required NoticeChannel channel,
    required String title,
    required String body,
    String? payload,
  }) async =>
      shown.add((id: id, channel: channel.id, title: title, body: body, payload: payload, at: null));

  @override
  Future<void> schedule({
    required int id,
    required NoticeChannel channel,
    required DateTime at,
    required String title,
    required String body,
    String? payload,
  }) async =>
      scheduled[id] = (id: id, channel: channel.id, title: title, body: body, payload: payload, at: at);

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
}

/// Speech that "hears" [script] (or fails with [failure]).
class ScriptedSpeech implements SpeechInput {
  ScriptedSpeech({this.script = '', this.failure});

  String script;
  SpeechFailure? failure;
  String? lastLocale;

  @override
  Future<SpeechFailure?> initialize() async => failure;

  @override
  Future<String?> localeFor(String languageCode) async => languageCode == 'bn' ? 'bn_BD' : 'en_US';

  @override
  Future<void> listen({
    required String? localeId,
    required void Function(String text, bool isFinal) onText,
    required void Function(SpeechFailure? failure) onDone,
  }) async {
    lastLocale = localeId;
    onText(script, true);
    onDone(null);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}
