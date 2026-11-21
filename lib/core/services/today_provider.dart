import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers.dart';
import '../utils/local_date.dart';
import 'clock.dart';

part 'today_provider.g.dart';

/// Today's calendar date. Emits again just after local midnight, so the
/// dashboard's "today" and "this month" roll over while the app is open.
@Riverpod(keepAlive: true)
Stream<LocalDate> today(Ref ref) {
  final clock = ref.watch(clockProvider);
  Timer? timer;
  late final StreamController<LocalDate> controller;

  void emitAndSchedule() {
    final now = clock.now();
    controller.add(LocalDate.fromDateTime(now));
    final midnight = DateTime(now.year, now.month, now.day + 1);
    timer = Timer(midnight.difference(now) + const Duration(seconds: 1), emitAndSchedule);
  }

  controller = StreamController<LocalDate>(
    onListen: emitAndSchedule,
    // Cancelling the timer leaves nothing pending after dispose.
    onCancel: () => timer?.cancel(),
  );
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
}

/// Synchronous convenience: the latest date from [todayProvider], or the
/// clock's date before the stream emits.
extension TodayX on Ref {
  LocalDate currentDate() => watch(todayProvider).value ?? watch(clockProvider).today();
}
