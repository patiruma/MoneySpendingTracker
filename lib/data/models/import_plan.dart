import '../../core/csv_import.dart';
import '../database.dart';

/// What the user chose to do about one duplicate row.
enum DuplicateChoice {
  /// Import it anyway, as a second, separate transaction.
  keepBoth,

  /// Leave the existing transaction alone and drop the incoming row.
  skip,

  /// Overwrite the existing transaction's fields with the incoming row's.
  /// Since a duplicate matches on *every* field, this is a no-op in practice —
  /// it exists so the dialog reads the way a file-copy conflict does, and so
  /// the meaning stays right if the match rule is ever loosened.
  replace,
}

/// One incoming row that exactly matches an existing live transaction.
///
/// "Exactly" means every field the CSV carries: occurred-at millis, amount
/// cents, category name, payment method name, note, and extra notes. Anything
/// looser would silently swallow two genuinely separate purchases — the same
/// coffee bought twice in one day differs in *no* field but time, so time is
/// part of the key.
class DuplicateCandidate {
  const DuplicateCandidate({required this.row, required this.existing});

  final ImportRow row;
  final Transaction existing;
}

/// A resolved, ready-to-commit import.
///
/// Produced by `TransactionRepository.planImport` **before** anything is
/// written, so the confirmation dialog can state real counts and the duplicate
/// prompts can run against a fixed set. Nothing here has touched the database.
class ImportPlan {
  const ImportPlan({
    required this.newRows,
    required this.duplicates,
    required this.errors,
    required this.newCategoryNames,
    required this.newPaymentMethodNames,
  });

  /// Rows with no existing match — imported unconditionally.
  final List<ImportRow> newRows;

  /// Rows that matched an existing transaction field-for-field. Each needs a
  /// [DuplicateChoice] before the commit can run.
  final List<DuplicateCandidate> duplicates;

  /// Rows that never parsed. Reported to the user, then skipped.
  final List<ImportRowError> errors;

  /// Label names in the file that don't exist yet and will be created at the
  /// top level. Stated up front in the confirmation, since creating a label is
  /// a structural change and §3.1 wants those counted before they happen.
  final Set<String> newCategoryNames;
  final Set<String> newPaymentMethodNames;

  int get totalImportable => newRows.length + duplicates.length;
  int get newLabelCount => newCategoryNames.length + newPaymentMethodNames.length;
  bool get hasNothingToDo => totalImportable == 0;
}

/// Outcome of a committed import, for the summary shown afterwards.
class ImportResult {
  const ImportResult({
    required this.inserted,
    required this.replaced,
    required this.skipped,
    required this.labelsCreated,
    required this.errors,
  });

  final int inserted;
  final int replaced;
  final int skipped;
  final int labelsCreated;
  final List<ImportRowError> errors;
}
