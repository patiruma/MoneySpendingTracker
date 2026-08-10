import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/date_range.dart';

/// Date range filter control (§2.7, §2.8): a few sensible presets plus a
/// custom range, always available.
class DateRangePickerField extends StatelessWidget {
  const DateRangePickerField({super.key, required this.value, required this.onChanged});

  final DateRange value;
  final ValueChanged<DateRange> onChanged;

  Future<void> _pickCustom(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: value.start, end: value.end),
    );
    if (picked == null) return;
    onChanged(
      DateRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat format = DateFormat.yMMMd();
    final String label = '${format.format(value.start)} – ${format.format(value.end)}';

    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Date range', border: OutlineInputBorder()),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _pickCustom(context),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  const Icon(Icons.date_range),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: PopupMenuButton<_Preset>(
              tooltip: 'Presets',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.arrow_drop_down),
              onSelected: (_Preset preset) => onChanged(preset.toRange()),
              itemBuilder: (BuildContext context) => _Preset.values
                  .map((_Preset p) => PopupMenuItem(value: p, child: Text(p.label)))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Preset {
  last7Days('Last 7 days'),
  last30Days('Last 30 days'),
  thisMonth('This month');

  const _Preset(this.label);
  final String label;

  DateRange toRange() {
    switch (this) {
      case _Preset.last7Days:
        final DateTime today = DateTime.now();
        final DateTime start = DateTime(today.year, today.month, today.day)
            .subtract(const Duration(days: 6));
        return DateRange(
          start: start,
          end: DateTime(today.year, today.month, today.day, 23, 59, 59, 999),
        );
      case _Preset.last30Days:
        return DateRange.last30Days();
      case _Preset.thisMonth:
        return DateRange.thisMonth();
    }
  }
}
