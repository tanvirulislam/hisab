import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// An Android notification channel. Users can mute each one separately in
/// system settings.
class NoticeChannel {
  const NoticeChannel(this.id, this.name);

  final String id;

  /// Localized; Android keeps the name it saw first.
  final String name;
}

/// Local notifications (§15). The app never talks to a server; every
/// notification is created on the device.
abstract interface class NotificationService {
  /// [onTap] receives the payload of a notification the user tapped while
  /// the app was running.
  Future<void> initialize({required void Function(String? payload) onTap});

  /// Payload of the notification that launched the app, if any.
  Future<String?> launchPayload();

  /// Asks for the Android 13+ permission. True when notifications may show.
  Future<bool> requestPermission();

  Future<void> show({
    required int id,
    required NoticeChannel channel,
    required String title,
    required String body,
    String? payload,
  });

  /// Shows a notification at [at] (local time). Delivery is inexact (within
  /// minutes), so no exact-alarm permission is needed.
  Future<void> schedule({
    required int id,
    required NoticeChannel channel,
    required DateTime at,
    required String title,
    required String body,
    String? payload,
  });

  Future<void> cancel(int id);
}

class LocalNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  @override
  Future<void> initialize({required void Function(String? payload) onTap}) async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } on Object catch (e) {
      // Unknown zone name: the target audience is in Bangladesh.
      debugPrint('Timezone lookup failed ($e); using Asia/Dhaka');
      tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (r) => onTap(r.payload),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp ?? false ? details!.notificationResponse?.payload : null;
  }

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? await _android?.areNotificationsEnabled() ?? false;

  /// Long bodies wrap instead of being cut off.
  NotificationDetails _details(NoticeChannel c, String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      c.id,
      c.name,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(body),
    ),
  );

  @override
  Future<void> show({
    required int id,
    required NoticeChannel channel,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) return;
    await _plugin.show(id: id, title: title, body: body, notificationDetails: _details(channel, body), payload: payload);
  }

  @override
  Future<void> schedule({
    required int id,
    required NoticeChannel channel,
    required DateTime at,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) return;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _details(channel, body),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }
}
