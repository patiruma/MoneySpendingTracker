import 'package:flutter/material.dart';

import '../../../core/date_range.dart';
import '../../../data/models/transaction_filter.dart';
import '../../../data/tables.dart';
import '../../../shared/widgets/date_range_picker.dart';
import '../../../shared/widgets/label_picker.dart';

/// The composable filter controls for History (§2.7): date range, category,
/// payment method, and text search. All three narrow the list together
/// (AND), never exclusively.
class HistoryFilterBar extends StatefulWidget {
  const HistoryFilterBar({super.key, required this.filter, required this.onChanged});

  final TransactionFilter filter;
  final ValueChanged<TransactionFilter> onChanged;

  @override
  State<HistoryFilterBar> createState() => _HistoryFilterBarState();
}

class _HistoryFilterBarState extends State<HistoryFilterBar> {
  // A persistent controller, rather than one rebuilt from `filter.query` on
  // every build, so typing keeps cursor position and IME composing state
  // stable across the rebuilds that every keystroke triggers.
  late final TextEditingController _searchController = TextEditingController(
    text: widget.filter.query,
  );

  @override
  void didUpdateWidget(HistoryFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filter.query != _searchController.text) {
      _searchController.text = widget.filter.query;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TransactionFilter filter = widget.filter;
    final ValueChanged<TransactionFilter> onChanged = widget.onChanged;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search notes',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            controller: _searchController,
            onChanged: (String value) => onChanged(filter.copyWith(query: value)),
          ),
          const SizedBox(height: 12),
          DateRangePickerField(
            value: filter.range,
            onChanged: (DateRange range) => onChanged(filter.copyWith(range: range)),
          ),
          const SizedBox(height: 12),
          _ClearableLabelPicker(
            kind: LabelKind.category,
            labelText: 'Category',
            selectedId: filter.categoryId,
            onChanged: (String? id) =>
                onChanged(filter.copyWith(categoryId: () => id)),
          ),
          const SizedBox(height: 12),
          _ClearableLabelPicker(
            kind: LabelKind.paymentMethod,
            labelText: 'Payment method',
            selectedId: filter.paymentMethodId,
            onChanged: (String? id) =>
                onChanged(filter.copyWith(paymentMethodId: () => id)),
          ),
        ],
      ),
    );
  }
}

/// Wraps [LabelPicker] with an "All" clear action — the filter's null state
/// (no category/payment-method narrowing) that [LabelPicker] alone has no way
/// to express, since picking there always selects a specific label.
class _ClearableLabelPicker extends StatelessWidget {
  const _ClearableLabelPicker({
    required this.kind,
    required this.labelText,
    required this.selectedId,
    required this.onChanged,
  });

  final LabelKind kind;
  final String labelText;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LabelPicker(
            kind: kind,
            labelText: selectedId == null ? '$labelText (All)' : labelText,
            selectedId: selectedId,
            onChanged: onChanged,
          ),
        ),
        if (selectedId != null)
          IconButton(
            tooltip: 'Clear $labelText filter',
            icon: const Icon(Icons.close),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }
}
