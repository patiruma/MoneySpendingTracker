import '../../core/bucketing.dart';

/// One point on the analytics line chart: the total spent within a single
/// bucket (§2.8.2). Buckets are *per-period* totals, never a running sum —
/// the view answers "how am I trending", not "how much have I spent so far".
class BucketPoint {
  const BucketPoint({required this.start, required this.totalCents});

  /// Local start-of-bucket. The exclusive end is [bucketEnd] of this instant.
  final DateTime start;

  final int totalCents;
}

/// One bar on the by-category breakdown (§2.8.3). Only produced for Combined
/// scope — a single-category view has nothing to break down.
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.categoryName,
    required this.totalCents,
  });

  final String categoryId;
  final String categoryName;
  final int totalCents;
}

/// Everything the Analytics view renders for one filter + bucket combination
/// (§2.8): the headline total, the time series, and the category breakdown.
///
/// All three are derived from the *same* [TransactionFilter] that drives the
/// reused transaction list below the charts, so the numbers and the list can
/// never disagree.
class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalCents,
    required this.series,
    required this.byCategory,
  });

  static const AnalyticsSummary empty = AnalyticsSummary(
    totalCents: 0,
    series: <BucketPoint>[],
    byCategory: <CategoryTotal>[],
  );

  /// Total for the scope and range (§2.8.1). For a parent category this
  /// already includes every descendant's spending — rollup happens in the
  /// filter, not here.
  final int totalCents;

  /// Per-period totals, oldest first, with empty buckets present at zero so
  /// the line doesn't imply spending it doesn't have.
  final List<BucketPoint> series;

  /// Descending by total. Empty for single-category scope.
  final List<CategoryTotal> byCategory;
}
