import 'package:uuid/uuid.dart';

import '../utils/local_date.dart';

/// Source of the current time. Inject a fixed clock in tests.
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

class FixedClock implements Clock {
  FixedClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

extension ClockX on Clock {
  int nowMillis() => now().millisecondsSinceEpoch;
  LocalDate today() => LocalDate.fromDateTime(now());
}

/// Generates primary keys. UUIDv7 keys sort by time and can be created
/// offline on several devices without colliding, which future sync needs.
abstract interface class IdGenerator {
  String newId();
}

class UuidV7Generator implements IdGenerator {
  const UuidV7Generator();

  static const _uuid = Uuid();

  @override
  String newId() => _uuid.v7();
}
