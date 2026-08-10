import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/models/transaction_with_labels.dart';
import 'package:money_spending_tracker/features/export/csv_export.dart';

void main() {
  TransactionWithLabels entry({
    int amountCents = 1234,
    String note = 'Lunch',
    String? extraNotes,
    String categoryName = 'Food',
    String paymentMethodName = 'Cash',
    bool categoryIsPlaceholder = false,
    bool paymentMethodIsPlaceholder = false,
    int occurredAt = 1700000000000,
  }) {
    return TransactionWithLabels(
      transaction: Transaction(
        id: 't1',
        amountCents: amountCents,
        occurredAt: occurredAt,
        categoryId: 'cat1',
        paymentMethodId: 'pm1',
        note: note,
        extraNotes: extraNotes,
        createdAt: occurredAt,
        updatedAt: occurredAt,
      ),
      categoryId: 'cat1',
      categoryName: categoryName,
      categoryIsPlaceholder: categoryIsPlaceholder,
      paymentMethodId: 'pm1',
      paymentMethodName: paymentMethodName,
      paymentMethodIsPlaceholder: paymentMethodIsPlaceholder,
    );
  }

  test('empty list produces a header-only file, not all data', () {
    final String csv = CsvExport.serialize(const []);
    final List<String> lines = csv.trim().split('\r\n');
    expect(lines, hasLength(1));
    expect(lines.single, 'Date,Amount,Category,Payment Method,Note,Additional Notes');
  });

  test('serializes amounts as plain decimal strings, not currency', () {
    final String csv = CsvExport.serialize([entry(amountCents: 123456)]);
    expect(csv, contains('1234.56'));
    expect(csv, isNot(contains(r'$')));
  });

  test('includes category, payment method, note, and extra notes', () {
    final String csv = CsvExport.serialize([
      entry(note: 'Lunch with Sam', extraNotes: 'split 3 ways', categoryName: 'Restaurants'),
    ]);
    expect(csv, contains('Restaurants'));
    expect(csv, contains('Cash'));
    expect(csv, contains('Lunch with Sam'));
    expect(csv, contains('split 3 ways'));
  });

  test('blank optional extra notes serializes as an empty field', () {
    final String csv = CsvExport.serialize([entry(extraNotes: null)]);
    final List<String> fields = csv.trim().split('\r\n')[1].split(',');
    expect(fields.last, '');
  });

  test('preserves row count and order for multiple entries', () {
    final String csv = CsvExport.serialize([
      entry(note: 'First'),
      entry(note: 'Second'),
    ]);
    final List<String> lines = csv.trim().split('\r\n');
    expect(lines, hasLength(3));
    expect(lines[1], contains('First'));
    expect(lines[2], contains('Second'));
  });

  // Regression: the desktop save path used `csv.codeUnits` wrapped in a
  // Uint8List, which truncates each UTF-16 unit to a single byte and silently
  // corrupts any non-ASCII character. Notes and label names are free text, so
  // accents and emoji are ordinary input, not edge cases.
  test('non-ASCII notes survive a UTF-8 encode/decode round trip', () {
    final String csv = CsvExport.serialize([
      entry(note: 'Café crème', categoryName: 'Épicerie', extraNotes: 'split 3 ways 🍕'),
    ]);

    final List<int> bytes = utf8.encode(csv);
    expect(utf8.decode(bytes), csv);
    expect(utf8.decode(bytes), contains('Café crème'));
    expect(utf8.decode(bytes), contains('Épicerie'));
    expect(utf8.decode(bytes), contains('🍕'));

    // The old behaviour, shown to be lossy: truncating code units mangles
    // exactly these characters.
    final List<int> truncated = Uint8List.fromList(csv.codeUnits);
    expect(utf8.decode(truncated, allowMalformed: true), isNot(contains('Épicerie')));
  });
}
