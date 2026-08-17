import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bucketing.dart';
import '../data/database.dart';
import '../data/models/analytics_series.dart';
import '../data/models/label_node.dart';
import '../data/models/transaction_filter.dart';
import '../data/models/transaction_with_labels.dart';
import '../data/repositories/label_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/tables.dart';

/// The single database instance. Overridden with an in-memory DB in tests —
/// repository tests run against real SQL, since cascade/rollup/move
/// correctness *is* SQL behavior.
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>((ref) {
  final AppDatabase db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final Provider<LabelRepository> labelRepositoryProvider = Provider<LabelRepository>((ref) {
  return LabelRepository(ref.watch(databaseProvider).labelDao);
});

final Provider<TransactionRepository> transactionRepositoryProvider =
    Provider<TransactionRepository>((ref) {
      final AppDatabase db = ref.watch(databaseProvider);
      return TransactionRepository(db.transactionDao, db.importDao);
    });

/// The label tree for one kind, live. Backed by drift's `watch()`, so writes
/// re-emit without manual invalidation.
final StreamProviderFamily<List<LabelNode>, LabelKind> labelTreeProvider =
    StreamProvider.family<List<LabelNode>, LabelKind>((ref, LabelKind kind) {
      return ref.watch(labelRepositoryProvider).watchTree(kind);
    });

/// The History screen's active filter (§2.7). Defaults to last 30 days, no
/// other narrowing.
final StateProvider<TransactionFilter> historyFilterProvider =
    StateProvider<TransactionFilter>((ref) => TransactionFilter.initial());

/// The History list, live and filtered. Re-emits on every write to
/// transactions or labels (a rename updates display names in place).
final StreamProvider<List<TransactionWithLabels>> historyTransactionsProvider =
    StreamProvider<List<TransactionWithLabels>>((ref) {
      final TransactionFilter filter = ref.watch(historyFilterProvider);
      return ref.watch(transactionRepositoryProvider).watchFiltered(filter);
    });

/// The raw set of selected transaction ids in the History list's selection
/// mode (§2.5). Entered via long-press on a row, in-place — no separate
/// screen. Cleared after a successful bulk reassign or when selection mode
/// exits.
///
/// Prefer [historyVisibleSelectionProvider] when acting on the selection: this
/// set can outlive the filter that produced it.
final StateProvider<Set<String>> historySelectionProvider =
    StateProvider<Set<String>>((ref) => <String>{});

/// The selection intersected with what the filter currently shows.
///
/// Selecting entries and *then* narrowing the filter would otherwise leave
/// ids selected that the user can no longer see — and a bulk reassign would
/// silently rewrite those invisible entries while the count claimed otherwise.
/// Scoping the selection to the visible list keeps §2.5's "select all in the
/// current filter" honest as the filter changes.
final Provider<Set<String>> historyVisibleSelectionProvider = Provider<Set<String>>((ref) {
  final Set<String> selected = ref.watch(historySelectionProvider);
  if (selected.isEmpty) return const <String>{};

  final List<TransactionWithLabels> visible =
      ref.watch(historyTransactionsProvider).value ?? const <TransactionWithLabels>[];
  final Set<String> visibleIds = visible
      .map((TransactionWithLabels e) => e.transaction.id)
      .toSet();
  return selected.intersection(visibleIds);
});

/// The Analytics view's active filter (§2.8). Independent of
/// [historyFilterProvider] — the two views hold their own scope and range, so
/// narrowing History doesn't silently retarget the charts.
///
/// `categoryId == null` is the **Combined** scope; any other value is
/// single-category, and [TransactionFilter.rollupCategory] defaults to true so
/// selecting a parent includes its whole subtree (§2.8 rollup).
final StateProvider<TransactionFilter> analyticsFilterProvider =
    StateProvider<TransactionFilter>((ref) => TransactionFilter.initial());

/// The user's explicit Day/Week/Month choice, or null to follow the range.
///
/// Kept separate from the resolved [analyticsBucketProvider] so the two rules
/// can coexist: the default tracks the range as it changes, but once the user
/// toggles, that choice always wins and stops being overridden.
final StateProvider<Bucket?> analyticsBucketOverrideProvider =
    StateProvider<Bucket?>((ref) => null);

/// The bucket actually charted: the manual override when set, otherwise the
/// range-derived default (Week, falling back to Day under 14 days).
final Provider<Bucket> analyticsBucketProvider = Provider<Bucket>((ref) {
  final Bucket? override = ref.watch(analyticsBucketOverrideProvider);
  if (override != null) return override;
  return defaultBucketFor(ref.watch(analyticsFilterProvider).range);
});

/// Total, time series, and category breakdown, live (§2.8). Re-emits on every
/// write and on any filter or bucket change.
final StreamProvider<AnalyticsSummary> analyticsSummaryProvider =
    StreamProvider<AnalyticsSummary>((ref) {
      final TransactionFilter filter = ref.watch(analyticsFilterProvider);
      final Bucket bucket = ref.watch(analyticsBucketProvider);
      return ref.watch(transactionRepositoryProvider).watchSummary(filter, bucket);
    });

/// The transaction list rendered beneath the charts (§2.8.4) — the same
/// filtered list behavior as History, reused rather than duplicated.
final StreamProvider<List<TransactionWithLabels>> analyticsTransactionsProvider =
    StreamProvider<List<TransactionWithLabels>>((ref) {
      final TransactionFilter filter = ref.watch(analyticsFilterProvider);
      return ref.watch(transactionRepositoryProvider).watchFiltered(filter);
    });
