@Tags(['perf'])
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/core/bucketing.dart';
import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/core/date_range.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/models/analytics_series.dart';
import 'package:money_spending_tracker/data/models/transaction_filter.dart';
import 'package:money_spending_tracker/data/models/transaction_with_labels.dart';

import 'seed_dataset.dart';

/// Phase 8 perf check against ~5k seeded rows.
///
/// These are regression guards, not targets. Their real value has already been
/// proven: this file is what surfaced the DST bucketing hang, which presented
/// as a query that never returned.
///
/// **Assertions are relative, not absolute wall-clock.** An earlier version
/// asserted fixed millisecond budgets and failed spuriously when the suite ran
/// alongside `flutter analyze` — the same query measured 818ms contended and
/// 524ms idle. A timing test that fails under CPU load is a false alarm, and
/// false alarms get suites ignored.
///
/// So each heavy query is expressed as a multiple of `baselineMicros()` — a
/// bare 5000-row `SELECT` measured on the same machine in the same run. Because
/// both sides read the same number of rows, contention scales them together and
/// the ratio holds; measured across idle and doubly-loaded runs, history stayed
/// at 3.8–4.1x and rollup/day at 2.3–2.8x. The guards sit well above the worst
/// observed value, so they catch an algorithmic regression (or an outright
/// hang, which never returns at all) without policing normal variance.
///
/// Tagged `perf` so it can be skipped in a fast loop:
///   flutter test --exclude-tags perf
///
/// [TransactionFilter] has no "all time" option by design (§2.7 — a range is
/// always present), so the benchmark widens the range explicitly to cover the
/// whole seeded span rather than adding a factory the app doesn't use.
final DateRange _fullSpan = DateRange(
  start: DateTime.now().subtract(const Duration(days: 400)),
  end: DateTime.now().add(const Duration(days: 1)),
);

void main() {
  late AppDatabase db;
  late SeededDataset data;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    data = await seedLargeDataset(db, count: 5000);
  });

  tearDown(() async {
    await db.close();
  });

  /// Median of [runs] wall-clock timings, so one unlucky GC pause doesn't
  /// decide the result.
  Future<Duration> median(int runs, Future<void> Function() body) async {
    final List<int> micros = <int>[];
    for (int i = 0; i < runs; i++) {
      final Stopwatch sw = Stopwatch()..start();
      await body();
      sw.stop();
      micros.add(sw.elapsedMicroseconds);
    }
    micros.sort();
    return Duration(microseconds: micros[micros.length ~/ 2]);
  }

  /// Calibration for the ratio guards: the cost of reading the same 5000 rows
  /// through the plainest path available — a bare `SELECT` over `transactions`
  /// with no joins, filters, CTE, or aggregation.
  ///
  /// It must do work of the *same shape and magnitude* as what it calibrates.
  /// An earlier attempt used a single-row lookup, which was wrong: a query
  /// returning no rows doesn't slow down proportionally under CPU contention,
  /// so the ratio swung from ~400x to ~1450x on a loaded machine and failed
  /// exactly the way absolute budgets did. Reading the same row count makes
  /// contention scale both sides together, which is what the ratio needs to
  /// stay stable.
  Future<int> baselineMicros() async {
    final Duration d = await median(5, () async {
      await db.select(db.transactions).get();
    });
    // Floor it so a fast idle run can't divide by a near-zero baseline.
    return d.inMicroseconds < 1000 ? 1000 : d.inMicroseconds;
  }

  /// Asserts [elapsed] is within [maxRatio] × the machine's baseline, and
  /// reports the numbers either way so a run is diagnosable from its log.
  void expectWithinBaseline(
    String label,
    Duration elapsed,
    int baseline,
    double maxRatio,
  ) {
    final double ratio = elapsed.inMicroseconds / baseline;
    // ignore: avoid_print
    print(
      '$label: ${elapsed.inMilliseconds}ms '
      '(${ratio.toStringAsFixed(1)}x baseline of ${(baseline / 1000).toStringAsFixed(1)}ms)',
    );
    expect(
      ratio,
      lessThan(maxRatio),
      reason:
          '$label took ${ratio.toStringAsFixed(1)}x the baseline bare 5000-row '
          'SELECT, over the ${maxRatio}x guard. Both sides read the same rows, '
          'so contention scales them together — this points at a real '
          'regression rather than a busy machine.',
    );
  }

  test('seeds the expected row count', () async {
    final int count = await db.transactionDao
        .getFiltered(TransactionFilter.initial().copyWith(range: _fullSpan))
        .then((List<TransactionWithLabels> r) => r.length);
    expect(count, 5000);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('filtered history query over a full year stays responsive', () async {
    final TransactionFilter filter = TransactionFilter.initial().copyWith(
      range: _fullSpan,
    );

    final int baseline = await baselineMicros();
    final Duration elapsed = await median(5, () async {
      await db.transactionDao.getFiltered(filter);
    });

    expectWithinBaseline('history getFiltered (5000 rows)', elapsed, baseline, 25);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('analytics summary over a full year stays responsive', () async {
    final TransactionFilter filter = TransactionFilter.initial().copyWith(
      range: _fullSpan,
    );

    final int baseline = await baselineMicros();
    final Duration elapsed = await median(5, () async {
      await db.transactionDao.watchSummary(filter, Bucket.month).first;
    });

    // Summary = the same filtered query plus a Dart fold over 5000 rows, so it
    // is legitimately the heaviest path here.
    expectWithinBaseline(
      'analytics watchSummary combined/month (5000 rows)',
      elapsed,
      baseline,
      60,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('analytics rollup over a parent category stays responsive', () async {
    // The heaviest analytics shape: recursive CTE for the subtree, an `IN`
    // over its ids, then the Dart fold.
    final TransactionFilter filter = TransactionFilter.initial().copyWith(
      range: _fullSpan,
      categoryId: () => data.topLevelCategoryId,
    );

    final int baseline = await baselineMicros();
    final Duration elapsed = await median(5, () async {
      await db.transactionDao.watchSummary(filter, Bucket.day).first;
    });

    // Day buckets over a 400-day span: this is the exact shape that used to
    // hang outright on a DST fall-back date. A ratio guard also catches the
    // hang, since an infinite loop never returns at all.
    expectWithinBaseline(
      'analytics watchSummary rollup/day (5000 rows)',
      elapsed,
      baseline,
      60,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('text search across note and extraNotes stays responsive', () async {
    // The `LIKE '%...%'` scan the plan flagged as the escape-hatch candidate
    // if it ever got slow.
    final TransactionFilter filter = TransactionFilter.initial().copyWith(
      range: _fullSpan,
      query: 'lunch',
    );

    final int baseline = await baselineMicros();
    final Duration elapsed = await median(5, () async {
      await db.transactionDao.getFiltered(filter);
    });

    expectWithinBaseline('history search LIKE (5000 rows)', elapsed, baseline, 25);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('needs-attention filter stays responsive', () async {
    final TransactionFilter filter = TransactionFilter.initial().copyWith(
      range: _fullSpan,
      categoryId: () => kNoCategoryId,
    );

    final int baseline = await baselineMicros();
    final Duration elapsed = await median(5, () async {
      await db.transactionDao.getFiltered(filter);
    });

    expectWithinBaseline(
      'history needs-attention filter (5000 rows)',
      elapsed,
      baseline,
      25,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('rollup total equals the sum of its subtree at scale', () async {
    // Correctness at 5k rows, not just in the small fixtures — a scale-only
    // bug in the CTE would otherwise hide behind a green unit suite.
    final TransactionFilter scoped = TransactionFilter.initial().copyWith(
      range: _fullSpan,
      categoryId: () => data.topLevelCategoryId,
    );

    final AnalyticsSummary summary =
        await db.transactionDao.watchSummary(scoped, Bucket.month).first;
    final List<TransactionWithLabels> rows = await db.transactionDao.getFiltered(scoped);

    final int sum = rows.fold(
      0,
      (int acc, TransactionWithLabels e) => acc + e.transaction.amountCents,
    );
    expect(summary.totalCents, sum);
    expect(rows, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
