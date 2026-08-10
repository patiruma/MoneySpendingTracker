import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../data/models/analytics_series.dart';
import 'chart_palette.dart';

/// Spending by category (§2.8.3) — **Combined scope only**. With a single
/// category selected there is nothing to break down, so the Analytics screen
/// omits this section entirely rather than rendering a one-bar chart.
///
/// Categories here are **nominal**, not ordinal: reordering them changes no
/// meaning. So every bar wears the same slot-1 hue rather than one hue each —
/// coloring by value would spend the identity channel re-encoding what bar
/// length already shows, and would break past 8 categories.
///
/// Drawn as laid-out widgets rather than a chart library: horizontal bars with
/// a leading name and a trailing value are exactly a row per category, and
/// category names are long enough that the label handling matters more than
/// the plotting does.
class CategoryBarChart extends StatelessWidget {
  const CategoryBarChart({super.key, required this.totals, this.maxBars = 8});

  final List<CategoryTotal> totals;

  /// Past this, the tail folds into a single "Other" row — a long tail of
  /// hairline bars is noise, and the list below the charts carries the detail.
  final int maxBars;

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();

    final ChartPalette palette = ChartPalette.of(context);
    final List<CategoryTotal> rows = _foldTail();
    final int max = rows.fold<int>(
      0,
      (int acc, CategoryTotal t) => t.totalCents > acc ? t.totalCents : acc,
    );

    return Column(
      children: [
        for (final CategoryTotal row in rows)
          Padding(
            // 2px of surface between touching bars, doing the separating.
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: _Bar(
              label: row.categoryName,
              totalCents: row.totalCents,
              fraction: max == 0 ? 0 : row.totalCents / max,
              palette: palette,
            ),
          ),
      ],
    );
  }

  List<CategoryTotal> _foldTail() {
    if (totals.length <= maxBars) return totals;
    final List<CategoryTotal> head = totals.take(maxBars - 1).toList();
    final int tailCents = totals
        .skip(maxBars - 1)
        .fold<int>(0, (int acc, CategoryTotal t) => acc + t.totalCents);
    return [
      ...head,
      CategoryTotal(
        categoryId: '',
        categoryName: 'Other (${totals.length - head.length})',
        totalCents: tailCents,
      ),
    ];
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.totalCents,
    required this.fraction,
    required this.palette,
  });

  final String label;
  final int totalCents;
  final double fraction;
  final ChartPalette palette;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      label: '$label, ${Money.format(totalCents)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Direct value label, always visible — never placed inside the
              // bar, where a short bar would clip it. This is also the relief
              // channel the palette's contrast rule asks for.
              Text(
                Money.format(totalCents),
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // A 10px track: thin marks, capped well under the 24px ceiling.
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return Stack(
                  children: [
                    Container(height: 10, color: palette.gridline),
                    Container(
                      height: 10,
                      // Grows from a single baseline at the left edge.
                      width: (constraints.maxWidth * fraction).clamp(
                        fraction > 0 ? 2.0 : 0.0,
                        constraints.maxWidth,
                      ),
                      color: palette.series,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
