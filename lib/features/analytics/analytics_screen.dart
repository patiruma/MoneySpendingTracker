import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/bucketing.dart';
import '../../core/money.dart';
import '../../data/models/analytics_series.dart';
import '../../data/models/transaction_filter.dart';
import '../../data/models/transaction_with_labels.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/transaction_list.dart';
import 'widgets/analytics_scope_bar.dart';
import 'widgets/category_bar_chart.dart';
import 'widgets/spending_line_chart.dart';

/// How many transaction rows Analytics renders before truncating. Enough to
/// scroll through a representative sample; far below the point where building
/// every tile eagerly costs a visible frame.
const int _kAnalyticsListCap = 50;

/// Spending analytics (§2.8) — "how am I trending", kept distinct from
/// History's "what did I buy".
///
/// Top to bottom: total → line chart → by-category bars (Combined only) →
/// the reused [TransactionList]. Every section is driven by one
/// [TransactionFilter], so the headline, the charts, and the list can never
/// describe different sets of entries.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TransactionFilter filter = ref.watch(analyticsFilterProvider);
    final Bucket bucket = ref.watch(analyticsBucketProvider);
    final AsyncValue<AnalyticsSummary> summary = ref.watch(analyticsSummaryProvider);
    final AsyncValue<List<TransactionWithLabels>> entries = ref.watch(
      analyticsTransactionsProvider,
    );
    final bool combined = filter.categoryId == null;

    return ListView(
      children: [
        AnalyticsScopeBar(
          filter: filter,
          bucket: bucket,
          onFilterChanged: (TransactionFilter next) =>
              ref.read(analyticsFilterProvider.notifier).state = next,
          // An explicit toggle always wins from here on, even if the range
          // later changes to one whose default would differ.
          onBucketChanged: (Bucket next) =>
              ref.read(analyticsBucketOverrideProvider.notifier).state = next,
        ),
        summary.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load analytics: $e'),
          ),
          data: (AnalyticsSummary data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TotalHeadline(totalCents: data.totalCents),
              const _SectionTitle('Spending over time'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 24, 8),
                child: SizedBox(
                  height: 220,
                  child: SpendingLineChart(series: data.series, bucket: bucket),
                ),
              ),
              // §2.8.3: breakdown only for Combined scope.
              if (combined && data.byCategory.isNotEmpty) ...[
                const _SectionTitle('By category'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: CategoryBarChart(totals: data.byCategory),
                ),
              ],
            ],
          ),
        ),
        const _SectionTitle('Transactions'),
        entries.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load transactions: $e'),
          ),
          data: (List<TransactionWithLabels> list) => TransactionList(
            entries: list,
            // Nested inside this scrolling ListView, so the list itself must
            // not scroll independently.
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Because it can't virtualize (see above), every row here is built
            // eagerly — a wide range over a large dataset would build thousands
            // of tiles to render the handful actually on screen. Analytics is
            // the "how am I trending" view; the exhaustive list is History's
            // job, so cap it and say so rather than un-nesting the scroll view.
            // The total, charts, and CSV export are unaffected — they read the
            // full filtered set.
            maxItems: _kAnalyticsListCap,
            overflowFooterBuilder: (int shown, int total) =>
                _ListOverflowFooter(shown: shown, total: total),
            onTap: (TransactionWithLabels entry) =>
                context.push('/entry/edit', extra: entry.transaction),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The one hero figure on the view (§2.8.1). Proportional figures, app sans.
class _TotalHeadline extends StatelessWidget {
  const _TotalHeadline({required this.totalCents});

  final int totalCents;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total spending',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            Money.format(totalCents),
            style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Shown when the analytics list is capped, so a truncated list never reads as
/// the complete set. The totals and charts above still cover every matching
/// entry — only this list is trimmed.
class _ListOverflowFooter extends StatelessWidget {
  const _ListOverflowFooter({required this.shown, required this.total});

  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        'Showing the $shown most recent of $total matching entries. '
        'The total and charts above cover all $total — open History to browse them all.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
