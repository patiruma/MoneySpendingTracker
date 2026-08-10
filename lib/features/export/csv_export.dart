import 'package:csv/csv.dart';

import '../../core/money.dart';
import '../../data/models/transaction_with_labels.dart';

/// Serializes a filtered transaction list to CSV (§2.9). Takes exactly the
/// list the caller already fetched via `listFiltered` — no filter logic here,
/// which is what makes "export respects the active filter" true by
/// construction.
abstract final class CsvExport {
  static const List<String> _header = [
    'Date',
    'Amount',
    'Category',
    'Payment Method',
    'Note',
    'Additional Notes',
  ];

  /// Amounts as decimal strings ([Money.toDecimalString], never
  /// [Money.format] — that's locale-currency for the UI, not CSV). Dates as
  /// ISO-8601 local time.
  static String serialize(List<TransactionWithLabels> entries) {
    final List<List<String>> rows = [
      _header,
      for (final TransactionWithLabels e in entries)
        [
          DateTime.fromMillisecondsSinceEpoch(e.transaction.occurredAt, isUtc: true)
              .toLocal()
              .toIso8601String(),
          Money.toDecimalString(e.transaction.amountCents),
          e.categoryName,
          e.paymentMethodName,
          e.transaction.note,
          e.transaction.extraNotes ?? '',
        ],
    ];
    return const ListToCsvConverter().convert(rows);
  }
}
