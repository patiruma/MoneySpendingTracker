/// An inclusive date range in local time, used for filtering and analytics.
class DateRange {
  const DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// Last 30 days, ending today (inclusive), the app-wide default (§7).
  factory DateRange.last30Days({DateTime? now}) {
    final DateTime today = _startOfDay(now ?? DateTime.now());
    return DateRange(start: today.subtract(const Duration(days: 29)), end: _endOfDay(today));
  }

  factory DateRange.thisMonth({DateTime? now}) {
    final DateTime n = now ?? DateTime.now();
    final DateTime start = DateTime(n.year, n.month);
    final DateTime end = DateTime(n.year, n.month + 1).subtract(const Duration(milliseconds: 1));
    return DateRange(start: start, end: end);
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  /// Number of calendar days spanned by this range, inclusive.
  int get spanInDays => end.difference(start).inDays + 1;

  bool contains(DateTime dateTime) =>
      !dateTime.isBefore(start) && !dateTime.isAfter(end);
}
