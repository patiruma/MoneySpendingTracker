import 'package:flutter_test/flutter_test.dart';
import 'package:money_spending_tracker/core/bucketing.dart';
import 'package:money_spending_tracker/core/date_range.dart';

void main() {
  group('defaultBucketFor', () {
    test('defaults to Week for a 30-day range', () {
      final DateRange range = DateRange(
        start: DateTime(2026, 7, 8),
        end: DateTime(2026, 8, 6),
      );
      expect(defaultBucketFor(range), Bucket.week);
    });

    test('falls back to Day for a range under 14 days', () {
      final DateRange range = DateRange(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 5),
      );
      expect(defaultBucketFor(range), Bucket.day);
    });

    test('uses Week at exactly 14 days', () {
      final DateRange range = DateRange(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 14),
      );
      expect(defaultBucketFor(range), Bucket.week);
    });
  });

  group('bucketStart', () {
    test('day bucket truncates to midnight', () {
      expect(bucketStart(DateTime(2026, 8, 6, 15, 30), Bucket.day), DateTime(2026, 8, 6));
    });

    test('week bucket starts on Monday', () {
      // 2026-08-06 is a Thursday.
      expect(bucketStart(DateTime(2026, 8, 6), Bucket.week), DateTime(2026, 8, 3));
    });

    test('week bucket on Monday itself stays put', () {
      expect(bucketStart(DateTime(2026, 8, 3), Bucket.week), DateTime(2026, 8, 3));
    });

    test('month bucket truncates to first of month', () {
      expect(bucketStart(DateTime(2026, 8, 6), Bucket.month), DateTime(2026, 8, 1));
    });
  });

  group('bucketEnd', () {
    test('week bucket end is exactly 7 days after start', () {
      final DateTime start = bucketStart(DateTime(2026, 8, 6), Bucket.week);
      final DateTime end = bucketEnd(DateTime(2026, 8, 6), Bucket.week);
      expect(end.difference(start).inDays, 7);
    });

    test('month bucket end rolls to next month', () {
      expect(bucketEnd(DateTime(2026, 8, 6), Bucket.month), DateTime(2026, 9, 1));
    });
  });

  // Regression: `bucketEnd` used to advance with `start.add(Duration(days: 1))`.
  // On a DST fall-back date the local day is 25 hours long, so that landed at
  // 23:00 on the *same* date; `bucketStart` then floored it back to the same
  // midnight. `_fillGaps` steps `cursor = bucketStart(bucketEnd(cursor))`, so
  // the cursor stopped advancing and Analytics hung the app — an unkillable
  // spin, not a slow query. Found by the Phase 8 5k-row perf check.
  group('DST safety', () {
    /// The invariant that actually matters, and the one `_fillGaps` depends on:
    /// a bucket step must always move strictly forward. True in every timezone,
    /// so this asserts real coverage even where the runner has no DST.
    void expectAlwaysAdvances(Bucket bucket, DateTime from, DateTime to) {
      DateTime cursor = bucketStart(from, bucket);
      final DateTime last = bucketStart(to, bucket);
      int guard = 0;
      while (!cursor.isAfter(last)) {
        final DateTime next = bucketStart(bucketEnd(cursor, bucket), bucket);
        expect(
          next.isAfter(cursor),
          isTrue,
          reason: '$bucket bucket failed to advance past $cursor',
        );
        cursor = next;
        expect(++guard, lessThan(5000), reason: 'runaway loop for $bucket');
      }
    }

    for (final Bucket bucket in Bucket.values) {
      test('$bucket buckets always advance across a full year', () {
        expectAlwaysAdvances(bucket, DateTime(2025, 1, 1), DateTime(2026, 1, 1));
      });
    }

    test('day buckets advance across both US DST transitions', () {
      // 2025-03-09 spring forward (23h day), 2025-11-02 fall back (25h day).
      for (final DateTime d in [DateTime(2025, 3, 9), DateTime(2025, 11, 2)]) {
        final DateTime next = bucketStart(bucketEnd(d, Bucket.day), Bucket.day);
        expect(next, DateTime(d.year, d.month, d.day + 1));
      }
    });

    test('a day-bucketed year yields exactly 365 points', () {
      // The concrete symptom: the series length was unbounded before the fix.
      final List<DateTime> points = <DateTime>[];
      DateTime cursor = bucketStart(DateTime(2025, 1, 1), Bucket.day);
      final DateTime last = bucketStart(DateTime(2025, 12, 31), Bucket.day);
      while (!cursor.isAfter(last) && points.length < 5000) {
        points.add(cursor);
        cursor = bucketStart(bucketEnd(cursor, Bucket.day), Bucket.day);
      }
      expect(points, hasLength(365));
      expect(points.toSet(), hasLength(365), reason: 'no repeated bucket starts');
    });

    test('week buckets stay 7 calendar days apart across a DST boundary', () {
      final DateTime start = bucketStart(DateTime(2025, 10, 29), Bucket.week);
      final DateTime next = bucketEnd(start, Bucket.week);
      expect(next, DateTime(start.year, start.month, start.day + 7));
      // Still a local midnight, even though the span isn't 7*24 hours.
      expect(next.hour, 0);
    });
  });
}
