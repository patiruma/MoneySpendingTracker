import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/transaction_filter.dart';
import '../../shared/providers.dart';
import 'csv_export.dart';
import 'export_service.dart';

/// Exports the invoking view's active [filter] to CSV (§2.9). There is no
/// independent export filter — the caller passes whichever
/// `historyFilterProvider` / `analyticsFilterProvider` is live in its view.
Future<void> exportTransactions(
  BuildContext context,
  WidgetRef ref,
  TransactionFilter filter,
) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final entries = await ref.read(transactionRepositoryProvider).listFiltered(filter);
  final String csv = CsvExport.serialize(entries);
  final String fileName =
      'spending_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';

  try {
    await ExportService.save(csv, fileName);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}
