import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/core/date_range.dart';
import 'package:money_spending_tracker/core/ids.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/models/transaction_filter.dart';
import 'package:money_spending_tracker/data/models/transaction_with_labels.dart';
import 'package:money_spending_tracker/data/tables.dart';
import 'package:money_spending_tracker/features/export/csv_export.dart';

/// Export has no filter logic of its own (§2.9) — [listFiltered] is exactly
/// the same query [watchFiltered] uses. These tests exercise that repository
/// call directly, then confirm serialization reflects it.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> addTransaction({
    String? categoryId,
    int amountCents = 1000,
    String note = 'entry',
    DateTime? occurredAt,
  }) async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        id: newId(),
        amountCents: amountCents,
        occurredAt: (occurredAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
        categoryId: categoryId ?? kNoCategoryId,
        paymentMethodId: kNoPaymentMethodId,
        note: note,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('exporting a filtered view yields exactly that filtered set', () async {
    await addTransaction(note: 'In range', occurredAt: DateTime.now());
    await addTransaction(
      note: 'Out of range',
      occurredAt: DateTime.now().subtract(const Duration(days: 400)),
    );

    final List<TransactionWithLabels> filtered = await db.transactionDao.getFiltered(
      TransactionFilter.initial(),
    );

    expect(filtered, hasLength(1));
    expect(filtered.single.transaction.note, 'In range');

    final String csv = CsvExport.serialize(filtered);
    expect(csv, contains('In range'));
    expect(csv, isNot(contains('Out of range')));
  });

  test('exporting an empty filtered view yields a header-only file', () async {
    await addTransaction(
      note: 'Long ago',
      occurredAt: DateTime.now().subtract(const Duration(days: 400)),
    );

    final List<TransactionWithLabels> filtered = await db.transactionDao.getFiltered(
      TransactionFilter.initial(),
    );
    expect(filtered, isEmpty);

    final String csv = CsvExport.serialize(filtered);
    expect(csv.trim().split('\r\n'), hasLength(1));
  });

  test('respects the "No Category" placeholder as a normal filter value', () async {
    final String food = 'food-id';
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.labels).insert(
      LabelsCompanion.insert(id: food, kind: LabelKind.category, name: 'Food', depth: 0, createdAt: now, updatedAt: now),
    );
    await addTransaction(note: 'Flagged'); // defaults to No Category
    await addTransaction(note: 'Categorized', categoryId: food);

    final List<TransactionWithLabels> filtered = await db.transactionDao.getFiltered(
      TransactionFilter.initial().copyWith(categoryId: () => kNoCategoryId),
    );

    expect(filtered, hasLength(1));
    expect(filtered.single.transaction.note, 'Flagged');
  });

  test('a custom date range narrows export the same way it narrows History', () async {
    await addTransaction(note: 'Today', occurredAt: DateTime.now());
    await addTransaction(
      note: 'Ten days ago',
      occurredAt: DateTime.now().subtract(const Duration(days: 10)),
    );

    final DateRange narrow = DateRange(
      start: DateTime.now().subtract(const Duration(days: 1)),
      end: DateTime.now().add(const Duration(days: 1)),
    );
    final List<TransactionWithLabels> filtered = await db.transactionDao.getFiltered(
      TransactionFilter.initial().copyWith(range: narrow),
    );

    expect(filtered, hasLength(1));
    expect(filtered.single.transaction.note, 'Today');
  });
}
