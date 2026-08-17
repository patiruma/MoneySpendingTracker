import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/bucketing.dart';
import '../../../core/money.dart';
import '../../../data/models/analytics_series.dart';
import 'chart_palette.dart';

/// Spending over time (§2.8.2) — **per-period totals, never a cumulative sum**.
/// The question this answers is "how am I trending", so each point is what was
/// spent in that bucket alone.
///
/// One series, so no legend box: the section title above already names what is
/// plotted. Identity is carried by the single hue and the axis.
class SpendingLineChart extends StatelessWidget {
  const SpendingLineChart({super.key, required this.series, required this.bucket});

  final List<BucketPoint> series;
  final Bucket bucket;

  @override
  Widget build(BuildContext context) {
    final ChartPalette palette = ChartPalette.of(context);
    final TextStyle tickStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.mutedInk) ??
        TextStyle(color: palette.mutedInk, fontSize: 12);

    // The chart's vertical scale is in **dollars**, because that is the unit
    // the spots below are plotted in (`totalCents / 100`). Every value that
    // meets fl_chart — maxY, the gridline interval, the tick values handed to
    // the label formatter — has to be in that same unit. Mixing the two (axis
    // in cents, spots in dollars) puts a $25 point on a 0–2500 axis, pinning it
    // flat to the baseline while the ticks read $0–$20.
    final double maxDollars = series.fold<double>(
      0,
      (double acc, BucketPoint p) => p.totalCents / 100 > acc ? p.totalCents / 100 : acc,
    );
    // Round the axis top up to a clean tick so labels read as round numbers
    // ($0 / $500 / $1,000) instead of arbitrary fractions of the maximum —
    // which is also what stops adjacent ticks rendering as near-identical
    // compact strings ("$1.2K" above "$1.3K").
    final double horizontalInterval = _niceInterval(maxDollars);
    final double maxY = maxDollars == 0
        // A flat-zero range would collapse the vertical scale; give it a
        // nominal head so the baseline still renders as a chart.
        ? horizontalInterval * 4
        : (maxDollars / horizontalInterval).ceil() * horizontalInterval;

    // Date labels are thinned against the *actual* plot width, not a fixed
    // count: six labels fit comfortably on a tablet and collide into a solid
    // run of text on a phone. Measured, because the palette validator checks
    // color and only a picture catches a collision.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double plotWidth = constraints.maxWidth - _yAxisGutter;
        final int labelInterval = _labelIntervalFor(plotWidth);

        return _build(context, palette, tickStyle, horizontalInterval, maxY, labelInterval);
      },
    );
  }

  Widget _build(
    BuildContext context,
    ChartPalette palette,
    TextStyle tickStyle,
    double horizontalInterval,
    double maxY,
    int labelInterval,
  ) {
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.none(),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: horizontalInterval,
          getDrawingHorizontalLine: (double value) =>
              FlLine(color: palette.gridline, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: palette.axis, width: 1)),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _yAxisGutter,
              interval: horizontalInterval,
              getTitlesWidget: (double value, TitleMeta meta) {
                // Ticks now land on round values, so every one is worth
                // showing — but the topmost would collide with the chart's
                // upper edge.
                if (value > maxY - horizontalInterval / 2 && value > 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    _compactDollars(value),
                    style: tickStyle,
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Thin the ticks so labels never collide on a long range;
              // the tooltip carries every point's exact date.
              interval: labelInterval.toDouble(),
              getTitlesWidget: (double value, TitleMeta meta) {
                final int index = value.round();
                if (index < 0 || index >= series.length) {
                  return const SizedBox.shrink();
                }
                if (index % labelInterval != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_axisLabel(series[index].start), style: tickStyle),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => palette.primaryInk,
            getTooltipItems: (List<LineBarSpot> spots) {
              return spots.map((LineBarSpot spot) {
                final BucketPoint point = series[spot.x.round()];
                return LineTooltipItem(
                  '${_tooltipLabel(point.start)}\n${Money.format(point.totalCents)}',
                  TextStyle(color: palette.surface, fontWeight: FontWeight.w600),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < series.length; i++)
                FlSpot(i.toDouble(), series[i].totalCents / 100),
            ],
            isCurved: false,
            color: palette.series,
            barWidth: 2,
            isStrokeCapRound: true,
            isStrokeJoinRound: true,
            belowBarData: BarAreaData(show: true, color: palette.areaFill),
            // Dots only on a short series; past that they crowd the line and
            // the tooltip is the better read. The final point always keeps its
            // marker as the "you are here" anchor.
            dotData: FlDotData(
              show: true,
              checkToShowDot: (FlSpot spot, LineChartBarData bar) =>
                  series.length <= 14 || spot.x.round() == series.length - 1,
              getDotPainter: (FlSpot spot, double percent, LineChartBarData bar, int index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: palette.series,
                  // 2px surface ring, so markers stay legible where they
                  // overlap the line or each other.
                  strokeWidth: 2,
                  strokeColor: palette.surface,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Picks a round gridline step (1/2/5 × a power of ten) targeting ~4 ticks,
  /// so the y-axis reads as clean numbers rather than fractions of the data's
  /// maximum. Works in **dollars**, the same unit as the plotted spots.
  static double _niceInterval(double maxDollars) {
    if (maxDollars <= 0) return 1;
    final double rough = maxDollars / 4;
    final double magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    for (final double step in <double>[1, 2, 5, 10]) {
      final double candidate = step * magnitude;
      if (candidate >= rough) return candidate;
    }
    return 10 * magnitude;
  }

  /// Width reserved for the y-axis labels — mirrors `reservedSize` below.
  static const double _yAxisGutter = 52;

  /// Roughly the widest a date tick gets ("12/31"), plus breathing room. Two
  /// labels closer than this read as one smear.
  static const double _minLabelSpacing = 56;

  /// Keeps every date label at least [_minLabelSpacing] apart by dropping every
  /// nth bucket, so a 30-day range on a phone shows ~5 labels instead of six
  /// overlapping ones. The tooltip still carries every point's exact date, so
  /// thinning costs nothing.
  int _labelIntervalFor(double plotWidth) {
    if (series.length <= 1 || plotWidth <= 0) return 1;
    final int maxLabels = math.max(2, plotWidth ~/ _minLabelSpacing);
    if (series.length <= maxLabels) return 1;
    return (series.length / maxLabels).ceil();
  }

  String _axisLabel(DateTime start) {
    switch (bucket) {
      case Bucket.day:
      case Bucket.week:
        return DateFormat.Md().format(start);
      case Bucket.month:
        return DateFormat.MMM().format(start);
    }
  }

  String _tooltipLabel(DateTime start) {
    switch (bucket) {
      case Bucket.day:
        return DateFormat.yMMMd().format(start);
      case Bucket.week:
        final DateTime end = bucketEnd(start, bucket).subtract(const Duration(days: 1));
        return '${DateFormat.MMMd().format(start)} – ${DateFormat.MMMd().format(end)}';
      case Bucket.month:
        return DateFormat.yMMM().format(start);
    }
  }

  /// Axis ticks are compact so they stay short: $1.2K rather than $1,234.00.
  /// Takes **dollars** — the axis unit.
  ///
  /// Sub-dollar steps keep their cents, so a tiny range doesn't render every
  /// tick as an identical "$0".
  static String _compactDollars(double dollars) {
    if (dollars >= 1000) {
      return NumberFormat.compactSimpleCurrency().format(dollars);
    }
    final int decimals = dollars > 0 && dollars < 1 ? 2 : 0;
    return NumberFormat.simpleCurrency(decimalDigits: decimals).format(dollars);
  }
}
