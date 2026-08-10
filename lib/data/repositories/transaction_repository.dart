import '../../core/bucketing.dart';
import '../daos/transaction_dao.dart';
import '../database.dart';
import '../models/analytics_series.dart';
import '../models/transaction_draft.dart';
import '../models/transaction_filter.dart';
import '../models/transaction_with_labels.dart';

/// Transaction reads/writes (§2.2, §2.3, §2.7) and analytics aggregation
/// (§2.8). Export lands in Phase 7.
class TransactionRepository {
  TransactionRepository(this._dao);

  final TransactionDao _dao;

  Future<Transaction?> findById(String id) => _dao.findById(id);

  Future<void> upsert(TransactionDraft d) => _dao.upsert(d);

  Future<void> delete(String id) => _dao.softDelete(id);

  /// Newest-first, live, filtered view backing History (§2.7) and reused by
  /// Analytics (§2.8.4). Re-emits on every write; never invalidated manually.
  Stream<List<TransactionWithLabels>> watchFiltered(TransactionFilter f) =>
      _dao.watchFiltered(f);

  /// One-shot version of [watchFiltered], for CSV export (§2.9).
  Future<List<TransactionWithLabels>> listFiltered(TransactionFilter f) =>
      _dao.getFiltered(f);

  /// Live total + time series + category breakdown for the Analytics view
  /// (§2.8). Takes the same [TransactionFilter] as [watchFiltered], so the
  /// charts and the list beneath them describe the same set of entries.
  Stream<AnalyticsSummary> watchSummary(TransactionFilter f, Bucket bucket) =>
      _dao.watchSummary(f, bucket);

  /// Reassigns [ids] to [categoryId] and/or [paymentMethodId] in one atomic
  /// write (§2.5). Behind a confirmation in the UI, never wired directly to
  /// a selection action.
  Future<void> bulkReassign({
    required Set<String> ids,
    String? categoryId,
    String? paymentMethodId,
  }) => _dao.bulkReassign(ids: ids, categoryId: categoryId, paymentMethodId: paymentMethodId);
}
