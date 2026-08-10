import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/core/ids.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/tables.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('fresh database seeds exactly the two placeholder rows', () async {
    final List<Label> allLabels = await db.select(db.labels).get();
    expect(allLabels.length, 2);

    final Label noCategory = allLabels.firstWhere((Label l) => l.id == kNoCategoryId);
    expect(noCategory.kind, LabelKind.category);
    expect(noCategory.isPlaceholder, isTrue);
    expect(noCategory.depth, 0);

    final Label noPaymentMethod =
        allLabels.firstWhere((Label l) => l.id == kNoPaymentMethodId);
    expect(noPaymentMethod.kind, LabelKind.paymentMethod);
    expect(noPaymentMethod.isPlaceholder, isTrue);
  });

  test('inserting a transaction with amount_cents = 0 throws', () async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    expect(
      () => db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: newId(),
          amountCents: 0,
          occurredAt: now,
          categoryId: kNoCategoryId,
          paymentMethodId: kNoPaymentMethodId,
          note: 'test',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsA(anything),
    );
  });

  test('inserting a transaction with a blank note throws', () async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    expect(
      () => db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: newId(),
          amountCents: 100,
          occurredAt: now,
          categoryId: kNoCategoryId,
          paymentMethodId: kNoPaymentMethodId,
          note: '   ',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsA(anything),
    );
  });

  test('a valid transaction insert succeeds', () async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        id: newId(),
        amountCents: 1500,
        occurredAt: now,
        categoryId: kNoCategoryId,
        paymentMethodId: kNoPaymentMethodId,
        note: 'Coffee',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final List<Transaction> rows = await db.select(db.transactions).get();
    expect(rows.length, 1);
  });

  test('duplicate sibling label names are rejected by the unique index', () async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.labels).insert(
      LabelsCompanion.insert(
        id: newId(),
        kind: LabelKind.category,
        name: 'Food',
        depth: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(
      () => db.into(db.labels).insert(
        LabelsCompanion.insert(
          id: newId(),
          kind: LabelKind.category,
          name: 'Food',
          depth: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsA(anything),
    );
  });
}
