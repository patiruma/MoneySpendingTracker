import 'package:drift/drift.dart';

import '../../core/bucketing.dart';
import '../../core/ids.dart';
import '../database.dart';
import '../models/analytics_series.dart';
import '../models/transaction_draft.dart';
import '../models/transaction_filter.dart';
import '../models/transaction_with_labels.dart';
import '../tables.dart';

part 'transaction_dao.g.dart';

@DriftAccessor(tables: [Transactions, Labels])
class TransactionDao extends DatabaseAccessor<AppDatabase> with _$TransactionDaoMixin {
  TransactionDao(super.db);

  int get _now => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Ids of [rootId] and every live descendant, via the recursive CTE — the
  /// same query the label DAO uses for rollup/cascade/move. Duplicated here
  /// (rather than reused across DAOs) because drift DAOs don't share a
  /// convenient cross-accessor call surface; both bodies must stay in sync
  /// with `label_dao.dart`'s `subtreeIds`.
  Future<Set<String>> _subtreeIds(String rootId) async {
    final List<QueryRow> rows = await customSelect(
      '''
WITH RECURSIVE subtree(id) AS (
  SELECT id FROM labels WHERE id = ?1 AND deleted_at IS NULL
  UNION ALL
  SELECT l.id FROM labels l JOIN subtree s ON l.parent_id = s.id WHERE l.deleted_at IS NULL
)
SELECT id FROM subtree
''',
      variables: [Variable<String>(rootId)],
      readsFrom: {labels},
    ).get();
    return rows.map((QueryRow r) => r.read<String>('id')).toSet();
  }

  /// Builds the filtered, joined query shared by [watchFiltered] and
  /// [getFiltered], plus the row mapper bound to the same label aliases —
  /// joins in both label rows so the caller gets display names and
  /// placeholder flags without a second round trip per row.
  Future<
    (JoinedSelectStatement<HasResultSet, dynamic> query, TransactionWithLabels Function(TypedResult))
  >
  _filteredQuery(TransactionFilter f) async {
    final $LabelsTable categoryLabels = alias(labels, 'category_labels');
    final $LabelsTable paymentLabels = alias(labels, 'payment_labels');

    final JoinedSelectStatement<HasResultSet, dynamic> q =
        select(transactions).join([
          innerJoin(categoryLabels, categoryLabels.id.equalsExp(transactions.categoryId)),
          innerJoin(paymentLabels, paymentLabels.id.equalsExp(transactions.paymentMethodId)),
        ]);

    q.where(transactions.deletedAt.isNull());
    q.where(
      transactions.occurredAt.isBetweenValues(
        f.range.start.toUtc().millisecondsSinceEpoch,
        f.range.end.toUtc().millisecondsSinceEpoch,
      ),
    );

    final String? categoryId = f.categoryId;
    if (categoryId != null) {
      if (f.rollupCategory) {
        final Set<String> subtree = await _subtreeIds(categoryId);
        q.where(transactions.categoryId.isIn(subtree));
      } else {
        q.where(transactions.categoryId.equals(categoryId));
      }
    }

    final String? paymentMethodId = f.paymentMethodId;
    if (paymentMethodId != null) {
      q.where(transactions.paymentMethodId.equals(paymentMethodId));
    }

    final String trimmedQuery = f.query.trim().toLowerCase();
    if (trimmedQuery.isNotEmpty) {
      q.where(
        transactions.note.lower().like('%$trimmedQuery%') |
            transactions.extraNotes.lower().like('%$trimmedQuery%'),
      );
    }

    q.orderBy([OrderingTerm.desc(transactions.occurredAt)]);

    TransactionWithLabels mapRow(TypedResult row) {
      final Label category = row.readTable(categoryLabels);
      final Label paymentMethod = row.readTable(paymentLabels);
      return TransactionWithLabels(
        transaction: row.readTable(transactions),
        categoryId: category.id,
        categoryName: category.name,
        categoryIsPlaceholder: category.isPlaceholder,
        paymentMethodId: paymentMethod.id,
        paymentMethodName: paymentMethod.name,
        paymentMethodIsPlaceholder: paymentMethod.isPlaceholder,
      );
    }

    return (q, mapRow);
  }

  /// Newest-first, live, filtered view (§2.7). Re-emits on every write to
  /// `transactions` or `labels` (a rename changes the display name here).
  Stream<List<TransactionWithLabels>> watchFiltered(TransactionFilter f) async* {
    final (query, mapRow) = await _filteredQuery(f);
    yield* query.watch().map((rows) => rows.map(mapRow).toList(growable: false));
  }

  /// One-shot version of [watchFiltered], for CSV export.
  Future<List<TransactionWithLabels>> getFiltered(TransactionFilter f) async {
    final (query, mapRow) = await _filteredQuery(f);
    final List<TypedResult> rows = await query.get();
    return rows.map(mapRow).toList(growable: false);
  }

  /// Live analytics summary for [f] at [bucket] (§2.8).
  ///
  /// Deliberately aggregates in Dart over the *same* filtered rows
  /// [watchFiltered] returns, rather than a separate `GROUP BY` in SQL. Two
  /// reasons: bucketing is local-time and calendar-aware (DST, month lengths,
  /// week start), which SQLite's date functions would have to re-derive from
  /// the UTC epoch millis we store; and sharing one query makes it structurally
  /// impossible for the total to disagree with the list rendered beneath it.
  /// A personal dataset is thousands of rows — the sum is not the bottleneck.
  Stream<AnalyticsSummary> watchSummary(TransactionFilter f, Bucket bucket) async* {
    final (query, mapRow) = await _filteredQuery(f);
    yield* query.watch().map((List<TypedResult> rows) {
      return _summarize(rows.map(mapRow).toList(growable: false), f, bucket);
    });
  }

  /// Folds filtered rows into the headline total, the gap-filled time series,
  /// and the by-category breakdown.
  AnalyticsSummary _summarize(
    List<TransactionWithLabels> entries,
    TransactionFilter f,
    Bucket bucket,
  ) {
    int total = 0;
    final Map<DateTime, int> bucketTotals = <DateTime, int>{};
    final Map<String, int> categoryTotals = <String, int>{};
    final Map<String, String> categoryNames = <String, String>{};

    for (final TransactionWithLabels e in entries) {
      final int cents = e.transaction.amountCents;
      total += cents;

      final DateTime occurredLocal =
          DateTime.fromMillisecondsSinceEpoch(e.transaction.occurredAt, isUtc: true).toLocal();
      final DateTime start = bucketStart(occurredLocal, bucket);
      bucketTotals[start] = (bucketTotals[start] ?? 0) + cents;

      categoryTotals[e.categoryId] = (categoryTotals[e.categoryId] ?? 0) + cents;
      categoryNames[e.categoryId] = e.categoryName;
    }

    return AnalyticsSummary(
      totalCents: total,
      series: _fillGaps(bucketTotals, f, bucket),
      // §2.8.3: the breakdown exists only for Combined scope. With a single
      // category selected there is nothing to break down — and with rollup on,
      // a per-category split would silently re-split the very subtree the
      // total just rolled up.
      byCategory: f.categoryId != null
          ? const <CategoryTotal>[]
          : _rankCategories(categoryTotals, categoryNames),
    );
  }

  /// Walks every bucket the range covers, so periods with no spending plot as
  /// zero instead of being skipped — a gap would otherwise draw a straight
  /// line across it and imply spending that didn't happen.
  List<BucketPoint> _fillGaps(
    Map<DateTime, int> totals,
    TransactionFilter f,
    Bucket bucket,
  ) {
    final List<BucketPoint> points = <BucketPoint>[];
    final DateTime last = bucketStart(f.range.end, bucket);
    DateTime cursor = bucketStart(f.range.start, bucket);

    // Bounded by the range, not by the data, so an empty result still yields
    // an axis rather than nothing.
    while (!cursor.isAfter(last)) {
      points.add(BucketPoint(start: cursor, totalCents: totals[cursor] ?? 0));
      final DateTime next = bucketStart(bucketEnd(cursor, bucket), bucket);
      // A bucket step that doesn't advance would spin here forever and hang the
      // app rather than fail loudly. `bucketEnd` guarantees forward movement
      // (see its DST note); this asserts that guarantee at the one call site
      // that depends on it, since the cost of being wrong is an unkillable UI.
      if (!next.isAfter(cursor)) {
        throw StateError(
          'Bucket $bucket failed to advance past $cursor — refusing to loop forever.',
        );
      }
      cursor = next;
    }
    return points;
  }

  List<CategoryTotal> _rankCategories(
    Map<String, int> totals,
    Map<String, String> names,
  ) {
    final List<CategoryTotal> ranked = totals.entries
        .map(
          (MapEntry<String, int> e) => CategoryTotal(
            categoryId: e.key,
            categoryName: names[e.key] ?? '',
            totalCents: e.value,
          ),
        )
        .toList();
    ranked.sort((CategoryTotal a, CategoryTotal b) {
      final int byTotal = b.totalCents.compareTo(a.totalCents);
      return byTotal != 0 ? byTotal : a.categoryName.compareTo(b.categoryName);
    });
    return ranked;
  }

  Future<Transaction?> findById(String id) {
    return (select(transactions)..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// Inserts when [TransactionDraft.id] is unset, updates in place otherwise.
  /// Any field on any past entry can be edited freely (§2.3).
  Future<void> upsert(TransactionDraft d) async {
    final int now = _now;
    if (d.id == null) {
      await into(transactions).insert(
        TransactionsCompanion.insert(
          id: newId(),
          amountCents: d.amountCents,
          occurredAt: d.occurredAt,
          categoryId: d.categoryId,
          paymentMethodId: d.paymentMethodId,
          note: d.note,
          extraNotes: Value(d.extraNotes),
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      await (update(transactions)..where((t) => t.id.equals(d.id!))).write(
        TransactionsCompanion(
          amountCents: Value(d.amountCents),
          occurredAt: Value(d.occurredAt),
          categoryId: Value(d.categoryId),
          paymentMethodId: Value(d.paymentMethodId),
          note: Value(d.note),
          extraNotes: Value(d.extraNotes),
          updatedAt: Value(now),
        ),
      );
    }
  }

  /// Soft-deletes a transaction (§2.3). No audit trail is kept — this is a
  /// tombstone for future sync, not an undo mechanism.
  Future<void> softDelete(String id) async {
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(deletedAt: Value(_now), updatedAt: Value(_now)),
    );
  }

  /// Reassigns [ids] to [categoryId] and/or [paymentMethodId] in one write
  /// (§2.5). Either may be omitted to leave that field untouched, so callers
  /// can bulk-set just a category, just a payment method, or both.
  Future<void> bulkReassign({
    required Set<String> ids,
    String? categoryId,
    String? paymentMethodId,
  }) async {
    if (ids.isEmpty || (categoryId == null && paymentMethodId == null)) return;
    await (update(transactions)..where((t) => t.id.isIn(ids))).write(
      TransactionsCompanion(
        categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
        paymentMethodId: paymentMethodId != null ? Value(paymentMethodId) : const Value.absent(),
        updatedAt: Value(_now),
      ),
    );
  }
}
