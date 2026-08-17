import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/csv_import.dart';
import '../../data/models/import_plan.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'duplicate_dialog.dart';
import 'import_service.dart';

/// Imports a CSV of the shape `CsvExport.serialize` produces.
///
/// The whole flow is preview-then-commit: the file is parsed and resolved
/// against the database first, so the §3.1 confirmation can state real counts
/// (rows, new labels, duplicates) and every duplicate is answered *before*
/// anything is written. The commit itself is one atomic transaction.
///
/// Unlike export, import takes **no** `TransactionFilter` — a filter narrows
/// what leaves the app, but there's nothing to narrow on the way in. Import is
/// therefore a global action in the overflow menu, not a per-view one.
Future<void> importTransactions(BuildContext context, WidgetRef ref) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  final ImportedFile? file;
  try {
    file = await ImportService.pick();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open that file: $e')));
    return;
  }
  if (file == null) return;

  final ImportParseResult parsed;
  try {
    parsed = CsvImport.parse(file.contents);
  } on ImportFormatException catch (e) {
    if (!context.mounted) return;
    await blockedDialog(context, title: "Can't import that file", message: e.message);
    return;
  } catch (e) {
    // The CSV package can throw on badly malformed quoting, which is a broken
    // file rather than a bug — report it the same way as a bad header.
    if (!context.mounted) return;
    await blockedDialog(
      context,
      title: "Can't import that file",
      message: "That file couldn't be read as CSV.\n\n$e",
    );
    return;
  }

  final ImportPlan plan =
      await ref.read(transactionRepositoryProvider).planImport(parsed);

  if (!context.mounted) return;

  if (plan.hasNothingToDo) {
    await blockedDialog(
      context,
      title: 'Nothing to import',
      message: plan.errors.isEmpty
          ? '${file.name} has no transaction rows.'
          : 'None of the ${plan.errors.length} rows in ${file.name} could be '
                'read.\n\n${_errorPreview(plan.errors)}',
    );
    return;
  }

  final bool proceed = await confirmDialog(
    context,
    title: 'Import ${plan.totalImportable} '
        '${plan.totalImportable == 1 ? 'entry' : 'entries'}?',
    message: _confirmMessage(file.name, plan),
    confirmLabel: 'Import',
  );
  if (!proceed) return;

  // Answer every duplicate up front. Collected here rather than inside the
  // commit so the write stays one uninterrupted transaction — a dialog awaited
  // mid-transaction would hold the database open across user think-time.
  final Map<int, DuplicateChoice> choices = <int, DuplicateChoice>{};
  DuplicateChoice? applyToAll;

  for (int i = 0; i < plan.duplicates.length; i++) {
    final DuplicateCandidate candidate = plan.duplicates[i];

    if (applyToAll != null) {
      choices[candidate.row.lineNumber] = applyToAll;
      continue;
    }

    if (!context.mounted) return;
    final DuplicateResolution resolution = await duplicateDialog(
      context,
      candidate: candidate,
      remaining: plan.duplicates.length - i - 1,
    );

    final DuplicateChoice? choice = resolution.choice;
    // Cancelling any prompt abandons the whole import — nothing has been
    // written yet, so this is a clean exit rather than a partial one.
    if (choice == null) return;

    choices[candidate.row.lineNumber] = choice;
    if (resolution.applyToRest) applyToAll = choice;
  }

  final ImportResult result;
  try {
    result = await ref
        .read(transactionRepositoryProvider)
        .commitImport(plan, choices);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    return;
  }

  messenger.showSnackBar(SnackBar(content: Text(_resultMessage(result))));
}

String _confirmMessage(String fileName, ImportPlan plan) {
  final List<String> lines = ['From $fileName.'];

  if (plan.newRows.isNotEmpty) {
    lines.add('${plan.newRows.length} new '
        '${plan.newRows.length == 1 ? 'entry' : 'entries'}.');
  }
  if (plan.duplicates.isNotEmpty) {
    lines.add('${plan.duplicates.length} '
        '${plan.duplicates.length == 1 ? 'entry' : 'entries'} already '
        "${plan.duplicates.length == 1 ? 'exists' : 'exist'} — you'll be asked "
        'about each one.');
  }
  if (plan.newLabelCount > 0) {
    final List<String> parts = [];
    if (plan.newCategoryNames.isNotEmpty) {
      parts.add('${plan.newCategoryNames.length} '
          '${plan.newCategoryNames.length == 1 ? 'category' : 'categories'}');
    }
    if (plan.newPaymentMethodNames.isNotEmpty) {
      parts.add('${plan.newPaymentMethodNames.length} payment '
          '${plan.newPaymentMethodNames.length == 1 ? 'method' : 'methods'}');
    }
    // Stated because creating a label is a structural change, and because the
    // export format carries no nesting — these land at the top level and may
    // need moving afterwards.
    lines.add('Creates ${parts.join(' and ')}, at the top level.');
  }
  if (plan.errors.isNotEmpty) {
    lines.add('${plan.errors.length} '
        '${plan.errors.length == 1 ? 'row' : 'rows'} will be skipped:\n'
        '${_errorPreview(plan.errors)}');
  }

  return lines.join('\n\n');
}

String _errorPreview(List<ImportRowError> errors, {int limit = 3}) {
  final Iterable<String> shown =
      errors.take(limit).map((ImportRowError e) => '• $e');
  final int rest = errors.length - limit;
  return [
    ...shown,
    if (rest > 0) '• …and $rest more',
  ].join('\n');
}

String _resultMessage(ImportResult result) {
  final List<String> parts = [];
  if (result.inserted > 0) parts.add('${result.inserted} imported');
  if (result.replaced > 0) parts.add('${result.replaced} replaced');
  if (result.skipped > 0) parts.add('${result.skipped} skipped');
  if (result.labelsCreated > 0) {
    parts.add('${result.labelsCreated} new '
        '${result.labelsCreated == 1 ? 'label' : 'labels'}');
  }
  if (result.errors.isNotEmpty) {
    parts.add('${result.errors.length} '
        '${result.errors.length == 1 ? 'row' : 'rows'} skipped as unreadable');
  }
  return parts.isEmpty ? 'Nothing was imported.' : parts.join(' · ');
}
