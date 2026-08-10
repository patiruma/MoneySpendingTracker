import 'package:flutter_test/flutter_test.dart';
import 'package:money_spending_tracker/core/date_range.dart';

void main() {
  group('DateRange.last30Days', () {
    test('spans exactly 30 days including today', () {
      final DateTime now = DateTime(2026, 8, 6);
      final DateRange range = DateRange.last30Days(now: now);
      expect(range.spanInDays, 30);
      expect(range.end.year, 2026);
      expect(range.end.month, 8);
      expect(range.end.day, 6);
      expect(range.start, DateTime(2026, 7, 8));
    });

    test('contains today and excludes day 31 ago', () {
      final DateTime now = DateTime(2026, 8, 6);
      final DateRange range = DateRange.last30Days(now: now);
      expect(range.contains(DateTime(2026, 8, 6, 23, 0)), isTrue);
      expect(range.contains(DateTime(2026, 7, 8, 0, 0)), isTrue);
      expect(range.contains(DateTime(2026, 7, 7, 23, 59)), isFalse);
    });
  });
}
