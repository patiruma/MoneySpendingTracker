import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/core/bucketing.dart';
import 'package:money_spending_tracker/data/models/analytics_series.dart';
import 'package:money_spending_tracker/features/analytics/widgets/spending_line_chart.dart';

/// Scale correctness for the Analytics line chart.
///
/// These assert the `LineChartData` fl_chart actually receives, because the bug
/// these guard against was invisible to "does the widget exist" tests: the axis
/// was computed in **cents** while the spots were plotted in **dollars**, so a
/// $25 point rendered flat on the baseline of a 0–2500 axis whose ticks read
/// "$0"…"$20". Everything below is really one invariant — **every value handed
/// to fl_chart is in dollars** — checked from a few directions.
void main() {
  List<BucketPoint> seriesOf(List<int> cents) {
    final DateTime start = DateTime(2026, 7, 13);
    return <BucketPoint>[
      for (int i = 0; i < cents.length; i++)
        BucketPoint(start: DateTime(start.year, start.month, start.day + i), totalCents: cents[i]),
    ];
  }

  /// Renders the chart and returns the data fl_chart was configured with.
  Future<LineChartData> dataFor(
    WidgetTester tester,
    List<int> cents, {
    Bucket bucket = Bucket.day,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 300,
            child: SpendingLineChart(series: seriesOf(cents), bucket: bucket),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<LineChart>(find.byType(LineChart)).data;
  }

  double highestSpot(LineChartData data) => data.lineBarsData.single.spots
      .map((FlSpot s) => s.y)
      .reduce((double a, double b) => a > b ? a : b);

  group('vertical scale', () {
    testWidgets('the axis top covers the largest point', (tester) async {
      // The reported case: one $25.00 entry. maxY must be >= 25, not 2500.
      final LineChartData data = await dataFor(tester, <int>[0, 0, 2500]);

      expect(highestSpot(data), 25.0);
      expect(data.maxY, greaterThanOrEqualTo(25.0));
      expect(data.minY, 0);
    });

    testWidgets('the largest point is not pinned to the baseline', (tester) async {
      final LineChartData data = await dataFor(tester, <int>[0, 0, 2500]);

      // The real symptom: the peak sat at ~1% of the axis, visually flat. It
      // should occupy a healthy share of the vertical space.
      expect(highestSpot(data) / data.maxY, greaterThan(0.5));
    });

    testWidgets('the axis top is never wildly larger than the data', (tester) async {
      for (final List<int> cents in <List<int>>[
        <int>[2500],
        <int>[100, 5000, 250],
        <int>[123456],
        <int>[1, 2, 3],
        <int>[99],
      ]) {
        final LineChartData data = await dataFor(tester, cents);
        final double peak = highestSpot(data);
        expect(
          data.maxY,
          greaterThanOrEqualTo(peak),
          reason: 'axis must contain the data for $cents',
        );
        // "Nice" rounding can overshoot, but never by an order of magnitude —
        // that is precisely what the cents/dollars mixup looked like.
        expect(
          data.maxY,
          lessThanOrEqualTo(peak * 2.5),
          reason: 'axis top is disproportionate for $cents',
        );
      }
    });

    testWidgets('an all-zero series still renders a sane axis', (tester) async {
      final LineChartData data = await dataFor(tester, <int>[0, 0, 0]);

      expect(highestSpot(data), 0);
      expect(data.maxY, greaterThan(0));
      expect(data.maxY, lessThanOrEqualTo(10));
    });

    testWidgets('gridline interval divides the axis into a few clean steps', (tester) async {
      final LineChartData data = await dataFor(tester, <int>[2500]);
      final double interval = data.gridData.horizontalInterval!;

      expect(interval, greaterThan(0));
      final double steps = data.maxY / interval;
      expect(steps, greaterThanOrEqualTo(2));
      expect(steps, lessThanOrEqualTo(8));
      expect(data.titlesData.leftTitles.sideTitles.interval, interval);
    });
  });

  group('axis labels', () {
    /// The y-axis tick strings, in bottom-to-top order.
    List<String> yTicks(WidgetTester tester, LineChartData data) {
      final SideTitles side = data.titlesData.leftTitles.sideTitles;
      final List<String> out = <String>[];
      for (double v = 0; v <= data.maxY; v += side.interval!) {
        final Widget w = side.getTitlesWidget(v, TitleMeta(
          min: 0,
          max: data.maxY,
          parentAxisSize: 300,
          axisPosition: 0,
          appliedInterval: side.interval!,
          sideTitles: side,
          formattedValue: '$v',
          axisSide: AxisSide.left,
          rotationQuarterTurns: 0,
        ));
        if (w is Padding && w.child is Text) {
          out.add((w.child! as Text).data!);
        }
      }
      return out;
    }

    testWidgets('tick labels describe dollars, matching the tooltip', (tester) async {
      final LineChartData data = await dataFor(tester, <int>[2500]);
      final List<String> ticks = yTicks(tester, data);

      // With a $25 peak the axis must actually mention ~$25 — the bug produced
      // a top tick of "$20" for the very same data.
      expect(ticks.first, r'$0');
      expect(ticks.join(','), contains(r'$2'));
      expect(ticks.any((String t) => t.contains('K')), isFalse);
    });

    testWidgets('large amounts compact rather than overflowing the gutter', (tester) async {
      final LineChartData data = await dataFor(tester, <int>[500000]); // $5,000
      final List<String> ticks = yTicks(tester, data);

      expect(ticks.any((String t) => t.contains('K')), isTrue);
      for (final String t in ticks) {
        expect(t.length, lessThanOrEqualTo(7), reason: 'tick "$t" is too wide for the gutter');
      }
    });

    testWidgets('sub-dollar ranges do not collapse every tick to \$0', (tester) async {
      final LineChartData data = await dataFor(tester, <int>[40]); // $0.40
      final List<String> ticks = yTicks(tester, data);

      expect(ticks.toSet().length, greaterThan(1), reason: 'ticks were all identical: $ticks');
    });
  });

  group('date label density', () {
    /// How many bottom-axis labels actually render at a given plot width.
    Future<int> labelCountAt(WidgetTester tester, int buckets, double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 220,
              child: SpendingLineChart(
                series: seriesOf(<int>[for (int i = 0; i < buckets; i++) 100 * i]),
                bucket: Bucket.day,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final LineChartData data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final SideTitles side = data.titlesData.bottomTitles.sideTitles;
      final int interval = side.interval!.round();
      int shown = 0;
      for (int i = 0; i < buckets; i += interval) {
        if (i % interval == 0) shown++;
      }
      return shown;
    }

    testWidgets('a narrow chart shows fewer labels than a wide one', (tester) async {
      // The collision the goldens caught: a fixed ~6 labels fits a tablet and
      // smears into one solid run at phone width.
      final int narrow = await labelCountAt(tester, 30, 360);
      final int wide = await labelCountAt(tester, 30, 900);

      expect(narrow, lessThan(wide));
    });

    testWidgets('labels stay far enough apart to be readable', (tester) async {
      for (final double width in <double>[320, 360, 480, 800, 1200]) {
        for (final int buckets in <int>[7, 30, 90, 365]) {
          final int shown = await labelCountAt(tester, buckets, width);
          final double plotWidth = width - 52; // the y-axis gutter
          expect(
            plotWidth / shown,
            greaterThanOrEqualTo(40),
            reason: '$shown labels in ${plotWidth}px is too dense '
                '($buckets buckets at ${width}px)',
          );
        }
      }
    });

    testWidgets('a short series labels every bucket', (tester) async {
      expect(await labelCountAt(tester, 5, 800), 5);
    });
  });

  group('series', () {
    testWidgets('plots per-period totals, never a cumulative sum', (tester) async {
      final LineChartData data = await dataFor(tester, <int>[1000, 1000, 1000]);
      final List<double> ys =
          data.lineBarsData.single.spots.map((FlSpot s) => s.y).toList();

      // Cumulative would be [10, 20, 30]; §2.8 wants the flat per-period read.
      expect(ys, <double>[10.0, 10.0, 10.0]);
    });

    testWidgets('x positions are bucket indices, one spot per bucket', (tester) async {
      final LineChartData data = await dataFor(tester, <int>[100, 200, 300, 400]);
      final List<FlSpot> spots = data.lineBarsData.single.spots;

      expect(spots, hasLength(4));
      expect(spots.map((FlSpot s) => s.x).toList(), <double>[0, 1, 2, 3]);
      expect(spots.map((FlSpot s) => s.y).toList(), <double>[1, 2, 3, 4]);
    });
  });
}
