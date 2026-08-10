import 'package:flutter/material.dart';

import '../../../core/bucketing.dart';
import '../../../core/date_range.dart';
import '../../../data/models/transaction_filter.dart';
import '../../../data/tables.dart';
import '../../../shared/widgets/date_range_picker.dart';
import '../../../shared/widgets/label_picker.dart';

/// The §2.8 scope controls: a single category at any level (or Combined) plus
/// a date range, and the Day/Week/Month bucket toggle for the line chart.
class AnalyticsScopeBar extends StatelessWidget {
  const AnalyticsScopeBar({
    super.key,
    required this.filter,
    required this.bucket,
    required this.onFilterChanged,
    required this.onBucketChanged,
  });

  final TransactionFilter filter;

  /// The bucket actually in effect — either the user's override or the
  /// range-derived default. The toggle shows it as selected either way, so the
  /// control never disagrees with the chart.
  final Bucket bucket;

  final ValueChanged<TransactionFilter> onFilterChanged;
  final ValueChanged<Bucket> onBucketChanged;

  @override
  Widget build(BuildContext context) {
    final bool combined = filter.categoryId == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DateRangePickerField(
            value: filter.range,
            onChanged: (DateRange range) => onFilterChanged(filter.copyWith(range: range)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LabelPicker(
                  kind: LabelKind.category,
                  labelText: combined ? 'Category (Combined)' : 'Category',
                  selectedId: filter.categoryId,
                  onChanged: (String? id) =>
                      onFilterChanged(filter.copyWith(categoryId: () => id)),
                ),
              ),
              if (!combined)
                IconButton(
                  tooltip: 'Show combined',
                  icon: const Icon(Icons.close),
                  onPressed: () => onFilterChanged(filter.copyWith(categoryId: () => null)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<Bucket>(
              segments: const [
                ButtonSegment<Bucket>(value: Bucket.day, label: Text('Day')),
                ButtonSegment<Bucket>(value: Bucket.week, label: Text('Week')),
                ButtonSegment<Bucket>(value: Bucket.month, label: Text('Month')),
              ],
              selected: <Bucket>{bucket},
              showSelectedIcon: false,
              onSelectionChanged: (Set<Bucket> selection) =>
                  onBucketChanged(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}
