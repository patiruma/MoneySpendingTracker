import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/core/csv_import.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/models/transaction_with_labels.dart';
import 'package:money_spending_tracker/features/export/csv_export.dart';

void main() {
  const String header = 'Date,Amount,Category,Payment Method,Note,Additional Notes';

  group('header validation', () {
    test('rejects a file that is not a spending export', () {
      expect(
        () => CsvImport.parse('Name,Email\nSam,sam@example.com'),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('rejects an empty file', () {
      expect(() => CsvImport.parse(''), throwsA(isA<ImportFormatException>()));
    });

    test('accepts a header-only export and yields no rows', () {
      final ImportParseResult result = CsvImport.parse(header);
      expect(result.rows, isEmpty);
      expect(result.errors, isEmpty);
      expect(result.isEmpty, isTrue);
    });

    test('header match is case-insensitive', () {
      final ImportParseResult result = CsvImport.parse(
        'date,amount,category,payment method,note,additional notes\n'
        '2024-03-01T12:00:00.000,5.00,Food,Cash,Lunch,',
      );
      expect(result.rows, hasLength(1));
    });
  });

  group('row parsing', () {
    test('parses a well-formed row into cents and UTC millis', () {
      final ImportParseResult result = CsvImport.parse(
        '$header\n2024-03-01T12:00:00.000,12.34,Food,Cash,Lunch,split 3 ways',
      );

      expect(result.errors, isEmpty);
      final ImportRow row = result.rows.single;
      expect(row.amountCents, 1234);
      expect(row.categoryName, 'Food');
      expect(row.paymentMethodName, 'Cash');
      expect(row.note, 'Lunch');
      expect(row.extraNotes, 'split 3 ways');
      expect(
        DateTime.fromMillisecondsSinceEpoch(row.occurredAt, isUtc: true).toLocal(),
        DateTime(2024, 3, 1, 12),
      );
    });

    test('blank extra notes become null, not an empty string', () {
      final ImportParseResult result = CsvImport.parse(
        '$header\n2024-03-01T12:00:00.000,5.00,Food,Cash,Lunch,',
      );
      expect(result.rows.single.extraNotes, isNull);
    });

    test('a trailing newline does not produce a phantom row', () {
      final ImportParseResult result = CsvImport.parse(
        '$header\n2024-03-01T12:00:00.000,5.00,Food,Cash,Lunch,\n',
      );
      expect(result.rows, hasLength(1));
      expect(result.errors, isEmpty);
    });

    test('quoted fields containing commas survive', () {
      final ImportParseResult result = CsvImport.parse(
        '$header\n2024-03-01T12:00:00.000,5.00,Food,Cash,"Lunch, with Sam","a, b"',
      );
      expect(result.rows.single.note, 'Lunch, with Sam');
      expect(result.rows.single.extraNotes, 'a, b');
    });
  });

  group('invalid rows are reported and skipped, not fatal', () {
    test('amount of zero is rejected per §2.2', () {
      final ImportParseResult result = CsvImport.parse(
        '$header\n2024-03-01T12:00:00.000,0.00,Food,Cash,Lunch,',
      );
      expect(result.rows, isEmpty);
      expect(result.errors.single.lineNumber, 2);
    });

    test('negative amount is rejected', () {
      final ImportParseResult result = CsvImport.parse(
        '$header\n2024-03-01T12:00:00.000,-5.00,Food,Cash,Lunch,',
      );
      expect(result.rows, isEmpty);
      expect(result.errors, hasLength(1));
    });

    test('blank note is rejected per §2.2', () {
      final ImportParseResult result = CsvImport.parse(
        '$header\n2024-03-01T12:00:00.000,5.00,Food,Cash,,',
      );
      expect(result.rows, isEmpty);
      expect(result.errors.single.message, contains('note'));
    });

    test('unparseable date is rejected', () {
      final ImportParseResult result = CsvImport.parse(
        '$header\nnot-a-date,5.00,Food,Cash,Lunch,',
      );
      expect(result.errors.single.message, contains('date'));
    });

    test('one bad row does not cost the good ones', () {
      final ImportParseResult result = CsvImport.parse(
        '$header\n'
        '2024-03-01T12:00:00.000,5.00,Food,Cash,Good one,\n'
        '2024-03-02T12:00:00.000,0,Food,Cash,Bad one,\n'
        '2024-03-03T12:00:00.000,7.00,Food,Cash,Another good one,',
      );
      expect(result.rows, hasLength(2));
      expect(result.errors, hasLength(1));
      expect(result.errors.single.lineNumber, 3);
    });

    test('error line numbers point at the real line in the file', () {
      final ImportParseResult result = CsvImport.parse(
        '$header\n'
        '2024-03-01T12:00:00.000,5.00,Food,Cash,Fine,\n'
        '2024-03-02T12:00:00.000,nope,Food,Cash,Broken,',
      );
      expect(result.errors.single.lineNumber, 3);
    });
  });

  // The export and import formats are a matched pair; this is the test that
  // keeps them from drifting apart.
  group('round trip with CsvExport', () {
    TransactionWithLabels entry({
      required int amountCents,
      required String note,
      String? extraNotes,
      String categoryName = 'Food',
      String paymentMethodName = 'Cash',
      required int occurredAt,
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
        categoryIsPlaceholder: false,
        paymentMethodId: 'pm1',
        paymentMethodName: paymentMethodName,
        paymentMethodIsPlaceholder: false,
      );
    }

    test('every field survives export -> import unchanged', () {
      final int occurredAt =
          DateTime(2024, 3, 1, 12, 30).toUtc().millisecondsSinceEpoch;
      final List<TransactionWithLabels> original = [
        entry(
          amountCents: 123456,
          note: 'Lunch with Sam',
          extraNotes: 'split 3 ways',
          categoryName: 'Restaurants',
          paymentMethodName: 'Venmo',
          occurredAt: occurredAt,
        ),
      ];

      final ImportParseResult result = CsvImport.parse(CsvExport.serialize(original));

      final ImportRow row = result.rows.single;
      expect(row.amountCents, 123456);
      expect(row.occurredAt, occurredAt);
      expect(row.note, 'Lunch with Sam');
      expect(row.extraNotes, 'split 3 ways');
      expect(row.categoryName, 'Restaurants');
      expect(row.paymentMethodName, 'Venmo');
    });

    test('non-ASCII text round trips', () {
      final List<TransactionWithLabels> original = [
        entry(
          amountCents: 500,
          note: 'Café crème',
          extraNotes: 'très bon 🍕',
          categoryName: 'Épicerie',
          occurredAt: DateTime(2024, 3, 1, 9).toUtc().millisecondsSinceEpoch,
        ),
      ];

      final ImportRow row =
          CsvImport.parse(CsvExport.serialize(original)).rows.single;
      expect(row.note, 'Café crème');
      expect(row.extraNotes, 'très bon 🍕');
      expect(row.categoryName, 'Épicerie');
    });

    test('an empty export imports as nothing, not as an error', () {
      final ImportParseResult result =
          CsvImport.parse(CsvExport.serialize(const []));
      expect(result.rows, isEmpty);
      expect(result.errors, isEmpty);
    });

    test('a multi-row export preserves count and order', () {
      final List<TransactionWithLabels> original = [
        entry(
          amountCents: 100,
          note: 'First',
          occurredAt: DateTime(2024, 3, 3).toUtc().millisecondsSinceEpoch,
        ),
        entry(
          amountCents: 200,
          note: 'Second',
          occurredAt: DateTime(2024, 3, 2).toUtc().millisecondsSinceEpoch,
        ),
      ];

      final ImportParseResult result =
          CsvImport.parse(CsvExport.serialize(original));
      expect(result.rows.map((ImportRow r) => r.note), ['First', 'Second']);
    });
  });
}
