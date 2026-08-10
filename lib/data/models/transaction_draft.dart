/// Input to [TransactionDao.upsert] / the repository's `upsert`. A null [id]
/// inserts; a set [id] updates that row in place — any field on any past
/// entry can be edited freely (§2.3).
class TransactionDraft {
  const TransactionDraft({
    this.id,
    required this.amountCents,
    required this.occurredAt,
    required this.categoryId,
    required this.paymentMethodId,
    required this.note,
    this.extraNotes,
  });

  final String? id;

  /// Strictly greater than 0 (§2.2); enforced by the DB `CHECK` and validated
  /// earlier by `Money.tryParse` at the UI edge.
  final int amountCents;

  /// UTC epoch millis.
  final int occurredAt;
  final String categoryId;
  final String paymentMethodId;
  final String note;
  final String? extraNotes;
}
