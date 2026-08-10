import 'dart:math';

import 'package:drift/drift.dart';

import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/core/ids.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/tables.dart';

/// A realistically-shaped dataset for the Phase 8 perf check: a 3-level
/// category tree, a handful of payment methods, and `count` transactions
/// spread over `spanDays`.
///
/// Shared by the benchmark and by any future load test so both measure the
/// same shape. Seeded from a fixed [Random] so timings are comparable run to
/// run rather than drifting with the row mix.
class SeededDataset {
  const SeededDataset({
    required this.categoryIds,
    required this.topLevelCategoryId,
    required this.paymentMethodIds,
  });

  /// Every live category id, all three levels.
  final List<String> categoryIds;

  /// A depth-0 category with descendants — the rollup case worth measuring,
  /// since it forces the recursive CTE plus an `IN` over the subtree.
  final String topLevelCategoryId;

  final List<String> paymentMethodIds;
}

Future<SeededDataset> seedLargeDataset(
  AppDatabase db, {
  int count = 5000,
  int spanDays = 365,
}) async {
  final Random rng = Random(42);
  final int now = DateTime.now().toUtc().millisecondsSinceEpoch;

  final List<String> categoryIds = <String>[];
  final List<String> paymentMethodIds = <String>[];
  String? firstTopLevel;

  await db.batch((Batch b) {
    // 8 top-level categories, each with 3 children, each of those with 2
    // grandchildren: 8 + 24 + 48 = 80 categories across the full 3-level cap.
    for (int i = 0; i < 8; i++) {
      final String parentId = newId();
      firstTopLevel ??= parentId;
      categoryIds.add(parentId);
      b.insert(
        db.labels,
        LabelsCompanion.insert(
          id: parentId,
          kind: LabelKind.category,
          name: 'Category $i',
          depth: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      for (int j = 0; j < 3; j++) {
        final String childId = newId();
        categoryIds.add(childId);
        b.insert(
          db.labels,
          LabelsCompanion.insert(
            id: childId,
            kind: LabelKind.category,
            name: 'Category $i.$j',
            parentId: Value(parentId),
            depth: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );

        for (int k = 0; k < 2; k++) {
          final String grandchildId = newId();
          categoryIds.add(grandchildId);
          b.insert(
            db.labels,
            LabelsCompanion.insert(
              id: grandchildId,
              kind: LabelKind.category,
              name: 'Category $i.$j.$k',
              parentId: Value(childId),
              depth: 2,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }
    }

    for (int i = 0; i < 6; i++) {
      final String id = newId();
      paymentMethodIds.add(id);
      b.insert(
        db.labels,
        LabelsCompanion.insert(
          id: id,
          kind: LabelKind.paymentMethod,
          name: 'Payment $i',
          depth: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  });

  // A slice of rows keeps the placeholders so the needs-attention path is
  // represented in the measured set rather than being a special case.
  const List<String> notes = [
    'Lunch with Sam',
    'Groceries',
    'Coffee',
    'Gas',
    'Movie tickets',
    'Books',
  ];

  await db.batch((Batch b) {
    for (int i = 0; i < count; i++) {
      final bool flagged = i % 20 == 0;
      b.insert(
        db.transactions,
        TransactionsCompanion.insert(
          id: newId(),
          amountCents: 100 + rng.nextInt(20000),
          occurredAt: now - rng.nextInt(spanDays) * 86400000,
          categoryId: flagged ? kNoCategoryId : categoryIds[rng.nextInt(categoryIds.length)],
          paymentMethodId: flagged
              ? kNoPaymentMethodId
              : paymentMethodIds[rng.nextInt(paymentMethodIds.length)],
          note: '${notes[rng.nextInt(notes.length)]} #$i',
          extraNotes: i % 3 == 0 ? Value('Extra context for entry $i') : const Value.absent(),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  });

  return SeededDataset(
    categoryIds: categoryIds,
    topLevelCategoryId: firstTopLevel!,
    paymentMethodIds: paymentMethodIds,
  );
}
