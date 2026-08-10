import 'constants.dart';
import 'date_range.dart';

enum Bucket { day, week, month }

/// Chooses the default bucket for a given range: Week, unless the range spans
/// under 14 days, in which case Day (so the chart isn't a single point). The
/// user's manual toggle always overrides this default.
Bucket defaultBucketFor(DateRange range) {
  return range.spanInDays < 14 ? Bucket.day : Bucket.week;
}

/// Returns the start-of-bucket DateTime that [dateTime] falls into for [bucket].
DateTime bucketStart(DateTime dateTime, Bucket bucket) {
  switch (bucket) {
    case Bucket.day:
      return DateTime(dateTime.year, dateTime.month, dateTime.day);
    case Bucket.week:
      final DateTime day = DateTime(dateTime.year, dateTime.month, dateTime.day);
      final int diff = (day.weekday - kWeekStartsOn + 7) % 7;
      // Calendar arithmetic, not `subtract(Duration)`: across a DST boundary an
      // absolute 24h step lands at 23:00 on the neighbouring date rather than
      // local midnight, which would put two different days in different weeks.
      return DateTime(day.year, day.month, day.day - diff);
    case Bucket.month:
      return DateTime(dateTime.year, dateTime.month);
  }
}

/// Returns the exclusive end (start of the next bucket) for the bucket
/// containing [dateTime].
///
/// Advances by **calendar** date, not by an absolute [Duration]. On a DST
/// fall-back day the local day is 25 hours long, so `start.add(Duration(days:
/// 1))` lands at 23:00 on the *same* date — and since [bucketStart] floors that
/// straight back to the same midnight, a caller stepping `cursor =
/// bucketEnd(cursor, ...)` never advances past it. `DateTime(y, m, d + 1)`
/// normalizes overflow (month and year roll over correctly) and always lands on
/// the next local midnight regardless of offset changes.
DateTime bucketEnd(DateTime dateTime, Bucket bucket) {
  final DateTime start = bucketStart(dateTime, bucket);
  switch (bucket) {
    case Bucket.day:
      return DateTime(start.year, start.month, start.day + 1);
    case Bucket.week:
      return DateTime(start.year, start.month, start.day + 7);
    case Bucket.month:
      return DateTime(start.year, start.month + 1);
  }
}
