import 'package:csv/csv.dart';

import 'money.dart';

/// One successfully parsed CSV row, before any database work.
///
/// Labels are still **names** here, not ids — the export format carries no ids
/// (see [CsvImport]), so resolving a name to a label row is a separate,
/// database-aware step. Keeping that out of the parser is what lets the whole
/// of this file be tested as pure Dart.
class ImportRow {
  const ImportRow({
    required this.lineNumber,
    required this.occurredAt,
    required this.amountCents,
    required this.categoryName,
    required this.paymentMethodName,
    required this.note,
    this.extraNotes,
  });

  /// 1-based line in the source file, including the header — what an error
  /// message must quote for the user to find the offending row.
  final int lineNumber;

  /// UTC epoch millis, converted from the file's local ISO-8601 timestamp.
  final int occurredAt;
  final int amountCents;
  final String categoryName;
  final String paymentMethodName;
  final String note;
  final String? extraNotes;
}

/// A row that could not be parsed, with the reason stated in the user's terms.
class ImportRowError {
  const ImportRowError({required this.lineNumber, required this.message});

  final int lineNumber;
  final String message;

  @override
  String toString() => 'Line $lineNumber: $message';
}

/// Outcome of parsing a whole file: the rows that survived, and the ones that
/// didn't. A file can be partially valid — bad rows are reported and skipped
/// rather than failing the import, since a hand-edited CSV with one broken line
/// shouldn't cost the user the other 200.
class ImportParseResult {
  const ImportParseResult({required this.rows, required this.errors});

  final List<ImportRow> rows;
  final List<ImportRowError> errors;

  bool get isEmpty => rows.isEmpty;
}

/// Raised when the file isn't an export-shaped CSV at all — a wrong header, or
/// no header. Distinct from a per-row error: there is nothing to import and
/// nothing partial to salvage.
class ImportFormatException implements Exception {
  const ImportFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parses the CSV shape that `CsvExport.serialize` produces (§2.9) back into
/// rows. The two are deliberately a matched pair: the header below is the same
/// list, in the same order, and a round trip through export → import must be
/// lossless for every field the format carries.
///
/// **What the format cannot carry**, and therefore what import cannot restore:
///
/// - **Transaction ids.** Export writes none, so an imported row is always a
///   *new* transaction. Import can't recognize a row it has already seen by id
///   — see `ImportPlan` for how exact-field matching stands in for that.
/// - **Label nesting.** Export writes a label's own name, not its path, so
///   `Food > Restaurants` exports as `Restaurants` and comes back as a
///   top-level label. Structure is rebuilt on the manage screen, not here.
abstract final class CsvImport {
  /// The export header, verbatim. Kept as the parse contract rather than a
  /// loose column sniff so a file from somewhere else fails loudly instead of
  /// importing into the wrong columns.
  static const List<String> expectedHeader = [
    'Date',
    'Amount',
    'Category',
    'Payment Method',
    'Note',
    'Additional Notes',
  ];

  static ImportParseResult parse(String csv) {
    final List<List<dynamic>> table = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(csv.replaceAll('\r\n', '\n'));

    if (table.isEmpty) {
      throw const ImportFormatException('That file is empty.');
    }

    final List<String> header = table.first
        .map((dynamic cell) => cell.toString().trim())
        .toList(growable: false);
    if (!_headerMatches(header)) {
      throw ImportFormatException(
        "That doesn't look like a spending export. Expected the columns: "
        '${expectedHeader.join(', ')}.',
      );
    }

    final List<ImportRow> rows = [];
    final List<ImportRowError> errors = [];

    for (int i = 1; i < table.length; i++) {
      final List<dynamic> raw = table[i];
      final int lineNumber = i + 1;

      // A trailing newline yields a stray empty row; that's not an error.
      if (raw.isEmpty ||
          (raw.length == 1 && (raw.first?.toString() ?? '').trim().isEmpty)) {
        continue;
      }

      final Object parsed = _parseRow(raw, lineNumber);
      if (parsed is ImportRow) {
        rows.add(parsed);
      } else if (parsed is ImportRowError) {
        errors.add(parsed);
      }
    }

    return ImportParseResult(rows: rows, errors: errors);
  }

  static bool _headerMatches(List<String> header) {
    if (header.length < expectedHeader.length) return false;
    for (int i = 0; i < expectedHeader.length; i++) {
      if (header[i].toLowerCase() != expectedHeader[i].toLowerCase()) return false;
    }
    return true;
  }

  /// Returns an [ImportRow] or an [ImportRowError].
  static Object _parseRow(List<dynamic> raw, int lineNumber) {
    String cell(int index) =>
        index < raw.length ? (raw[index]?.toString() ?? '').trim() : '';

    if (raw.length < expectedHeader.length) {
      return ImportRowError(
        lineNumber: lineNumber,
        message: 'expected ${expectedHeader.length} columns, found ${raw.length}.',
      );
    }

    final DateTime? occurred = DateTime.tryParse(cell(0));
    if (occurred == null) {
      return ImportRowError(
        lineNumber: lineNumber,
        message: "couldn't read the date '${cell(0)}'.",
      );
    }

    // Money.tryParse is the single amount-parsing rule in the app (§2.2: >0,
    // rejects 0, negatives, and non-numerics). Import gets that validation for
    // free rather than re-deriving a looser one.
    final int? amountCents = Money.tryParse(cell(1));
    if (amountCents == null) {
      return ImportRowError(
        lineNumber: lineNumber,
        message: "'${cell(1)}' isn't an amount greater than zero.",
      );
    }

    final String note = cell(4);
    if (note.isEmpty) {
      return ImportRowError(lineNumber: lineNumber, message: 'the note is blank.');
    }

    final String extraNotes = cell(5);

    return ImportRow(
      lineNumber: lineNumber,
      // Export writes local ISO-8601; the DB stores UTC millis.
      occurredAt: occurred.toUtc().millisecondsSinceEpoch,
      amountCents: amountCents,
      categoryName: cell(2),
      paymentMethodName: cell(3),
      note: note,
      extraNotes: extraNotes.isEmpty ? null : extraNotes,
    );
  }
}
