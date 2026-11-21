import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/local_date.dart';
import '../features/reports/domain/report_math.dart';
import '../features/reports/presentation/report_providers.dart';
import 'router.dart';
import 'routes.dart';

/// Opens the screen a tapped notification points to (see `NoticePayload`).
void openNotificationPayload(ProviderContainer container, String? payload) {
  if (payload == null) return;
  final router = container.read(routerProvider);
  if (payload.startsWith('route:')) {
    final path = payload.substring('route:'.length);
    // Add is a full-screen action over the current tab; the rest are tabs.
    path == Routes.add ? router.push(path) : router.go(path);
  } else if (payload.startsWith('summary:')) {
    final ym = int.tryParse(payload.substring('summary:'.length));
    if (ym == null || ym % 100 < 1 || ym % 100 > 12) return;
    container.read(reportFilterProvider.notifier)
      ..setPeriod(ReportPeriod.month)
      ..goTo(LocalDate(ym ~/ 100, ym % 100, 1));
    router.go(Routes.reports);
  }
}
