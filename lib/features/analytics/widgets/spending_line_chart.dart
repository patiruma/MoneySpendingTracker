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

    final int maxCents = series.fold<int>(
      0,
      (int acc, BucketPoint p) => p.totalCents > acc ? p.totalCents : acc,
    );
    // Round the axis top up to a clean tick so labels read as round numbers
    // ($0 / $500 / $1,000) instead of arbitrary fractions of the maximum —
    // which is also what stops adjacent ticks rendering as near-identical
    // compact strings ("$1.2K" above "$1.3K").
    final double horizontalInterval = _niceInterval(maxCents);
    final double maxY = maxCents == 0
        // A flat-zero range would collapse the vertical scale; give it a
        // nominal head so the baseline still renders as a chart.
        ? horizontalInterval * 4
        : (maxCents / horizontalInterval).ceil() * horizontalInterval;

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
              reservedSize: 52,
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
                    _compactCents(value.round()),
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
              interval: _labelInterval.toDouble(),
              getTitlesWidget: (double value, TitleMeta meta) {
                final int index = value.round();
                if (index < 0 || index >= series.length) {
                  return const SizedBox.shrink();
                }
                if (index % _labelInterval != 0) return const SizedBox.shrink();
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
  /// maximum. Works in cents throughout; the label formatter converts.
  static double _niceInterval(int maxCents) {
    if (maxCents <= 0) return 100;
    final double rough = maxCents / 4;
    final double magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    for (final double step in <double>[1, 2, 5, 10]) {
      final double candidate = step * magnitude;
      if (candidate >= rough) return candidate;
    }
    return 10 * magnitude;
  }

  /// Show at most ~6 date labels regardless of how many buckets there are.
  int get _labelInterval => series.length <= 6 ? 1 : (series.length / 6).ceil();

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
  static String _compactCents(int cents) {
    final double units = cents / 100;
    if (units >= 1000) {
      return NumberFormat.compactSimpleCurrency().format(units);
    }
    return NumberFormat.simpleCurrency(decimalDigits: 0).format(units);
  }
}
