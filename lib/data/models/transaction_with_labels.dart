import '../database.dart';

/// A transaction plus the current display names of its Category and Payment
/// Method — what the history list and export actually render. Resolved via a
/// join rather than stored, so a rename is reflected everywhere for free
/// (§2.4's rename cascade).
class TransactionWithLabels {
  const TransactionWithLabels({
    required this.transaction,
    required this.categoryId,
    required this.categoryName,
    required this.categoryIsPlaceholder,
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.paymentMethodIsPlaceholder,
  });

  final Transaction transaction;
  final String categoryId;
  final String categoryName;
  final bool categoryIsPlaceholder;
  final String paymentMethodId;
  final String paymentMethodName;
  final bool paymentMethodIsPlaceholder;

  /// Derived, never stored (§2.6): flagged iff either label is the
  /// placeholder it fell back to.
  bool get needsAttention => categoryIsPlaceholder || paymentMethodIsPlaceholder;
}
