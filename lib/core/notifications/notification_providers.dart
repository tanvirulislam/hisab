import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'notification_service.dart';

part 'notification_providers.g.dart';

/// Device notifications. Tests override this with a recording fake.
@Riverpod(keepAlive: true)
NotificationService notificationService(Ref ref) => LocalNotificationService();
