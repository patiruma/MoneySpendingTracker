import '../../core/date_range.dart';

/// The single filtering vocabulary (§2.7, §2.8, §2.9). History, Analytics, and
/// CSV export all take one of these — export has no filter logic of its own,
/// which is what makes "export respects active filters" true by construction.
class TransactionFilter {
  const TransactionFilter({
    required this.range,
    this.categoryId,
    this.rollupCategory = true,
    this.paymentMethodId,
    this.query = '',
  });

  /// Default filter: last 30 days, no category/payment-method/text narrowing.
  factory TransactionFilter.initial() => TransactionFilter(range: DateRange.last30Days());

  /// Date range to include. Always present — there is no "all time" option,
  /// per the spec's "sensible default, custom always available" (§2.7/§2.8).
  final DateRange range;

  /// null = all categories. The placeholder id ("No Category") is a normal
  /// value here — no special-casing (§2.6).
  final String? categoryId;

  /// When [categoryId] is set, whether to include spending from its
  /// descendants too (§2.8 category rollup). Ignored when [categoryId] is null.
  final bool rollupCategory;

  /// null = all payment methods. Same placeholder-as-normal-value rule as
  /// [categoryId].
  final String? paymentMethodId;

  /// Matches against `note` and `extraNotes`, case-insensitive. Empty = no
  /// text filter.
  final String query;

  TransactionFilter copyWith({
    DateRange? range,
    String? Function()? categoryId,
    bool? rollupCategory,
    String? Function()? paymentMethodId,
    String? query,
  }) {
    return TransactionFilter(
      range: range ?? this.range,
      categoryId: categoryId != null ? categoryId() : this.categoryId,
      rollupCategory: rollupCategory ?? this.rollupCategory,
      paymentMethodId: paymentMethodId != null ? paymentMethodId() : this.paymentMethodId,
      query: query ?? this.query,
    );
  }
}
