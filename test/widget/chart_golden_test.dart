@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/core/bucketing.dart';
import 'package:money_spending_tracker/data/models/analytics_series.dart';
import 'package:money_spending_tracker/features/analytics/widgets/spending_line_chart.dart';

/// Throwaway geometry check, per CLAUDE.md: the palette validator checks color,
/// not layout — overlapping ticks and clipped labels only show up in a picture.
/// Run with `--update-goldens` and *look at* the PNGs; text renders as boxes
/// without fonts, which is fine for judging geometry.
///
/// Tagged `golden` and excluded from the default run, since it asserts nothing
/// a CI machine should gate on.
void main() {
  List<BucketPoint> seriesOf(List<int> cents) {
    final DateTime start = DateTime(2026, 7, 13);
    return <BucketPoint>[
      for (int i = 0; i < cents.length; i++)
        BucketPoint(start: DateTime(start.year, start.month, start.day + i), totalCents: cents[i]),
    ];
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    List<int> cents, {
    Bucket bucket = Bucket.day,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Mirrors AnalyticsScreen's real geometry — same padding, same 220px
          // height, a phone-width plot area — so what these PNGs show is what
          // ships rather than an artificially roomy harness.
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 24, 8),
            child: SizedBox(
              width: 360,
              height: 220,
              child: SpendingLineChart(series: seriesOf(cents), bucket: bucket),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SpendingLineChart),
      matchesGoldenFile('goldens/line_$name.png'),
    );
  }

  testWidgets(r'reported case: a single $25 entry in a 30-day range', (tester) async {
    final List<int> cents = List<int>.filled(30, 0);
    cents[29] = 2500;
    await shoot(tester, 'single_entry', cents);
  });

  testWidgets('typical spread', (tester) async {
    await shoot(tester, 'typical', <int>[1250, 800, 0, 3400, 1500, 0, 2200, 900, 4100, 1700]);
  });

  testWidgets('large amounts compact on the axis', (tester) async {
    await shoot(tester, 'large', <int>[125000, 80000, 340000, 150000, 220000]);
  });

  testWidgets('flat zero range', (tester) async {
    await shoot(tester, 'zero', <int>[0, 0, 0, 0, 0]);
  });

  testWidgets('dense daily range — the label-collision stress case', (tester) async {
    await shoot(
      tester,
      'dense',
      <int>[for (int i = 0; i < 90; i++) (i * 137) % 4000],
    );
  });
}
