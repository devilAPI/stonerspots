/// German time for the pedestrian-zone rule (consumption forbidden 7-20 h).
///
/// The rule follows the clock in Germany, not the device's: someone with a
/// phone set to another zone still gets German hours. Germany keeps the EU
/// rule: CET (UTC+1), and CEST (UTC+2) from the last Sunday of March,
/// 01:00 UTC, to the last Sunday of October, 01:00 UTC. Computed here from
/// UTC, so no time zone database is needed.
library;

/// First and last hour (exclusive) of the pedestrian-zone ban.
const int kPedestrianBanFrom = 7;
const int kPedestrianBanUntil = 20;

DateTime _lastSunday(int year, int month) {
  final last = DateTime.utc(year, month + 1, 0); // last day of month
  return last.subtract(Duration(days: last.weekday % 7));
}

/// Whether summer time is in force in Germany at [instant].
bool isGermanSummerTime(DateTime instant) {
  final u = instant.toUtc();
  final start = _lastSunday(u.year, 3).add(const Duration(hours: 1));
  final end = _lastSunday(u.year, 10).add(const Duration(hours: 1));
  return !u.isBefore(start) && u.isBefore(end);
}

/// Wall-clock time in Germany at [instant], as a UTC [DateTime] whose
/// fields read as German local time.
DateTime germanTime(DateTime instant) {
  final u = instant.toUtc();
  return u.add(Duration(hours: isGermanSummerTime(u) ? 2 : 1));
}

/// Whether consuming in a pedestrian zone is forbidden at [instant].
bool pedestrianBanActive(DateTime instant) {
  final h = germanTime(instant).hour;
  return h >= kPedestrianBanFrom && h < kPedestrianBanUntil;
}

/// The next instant after [instant] at which [pedestrianBanActive] may
/// change (the next full hour of 7 or 20 German time), for a timer.
DateTime nextPedestrianChange(DateTime instant) {
  final local = germanTime(instant);
  final offset = local.difference(instant.toUtc());
  final hour = local.hour < kPedestrianBanFrom
      ? kPedestrianBanFrom
      : local.hour < kPedestrianBanUntil
      ? kPedestrianBanUntil
      : kPedestrianBanFrom + 24;
  final next = DateTime.utc(local.year, local.month, local.day, hour);
  // back to a real instant, with the offset in force then (a DST switch
  // may lie in between)
  final guess = next.subtract(offset);
  return next.subtract(germanTime(guess).difference(guess));
}
