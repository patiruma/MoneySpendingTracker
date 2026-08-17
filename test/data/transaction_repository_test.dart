import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_spending_tracker/core/bucketing.dart';
import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/core/date_range.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/models/analytics_series.dart';
import 'package:money_spending_tracker/data/models/transaction_draft.dart';
import 'package:money_spending_tracker/data/models/transaction_filter.dart';
import 'package:money_spending_tracker/data/models/transaction_with_labels.dart';
import 'package:money_spending_tracker/data/repositories/label_repository.dart';
import 'package:money_spending_tracker/data/repositories/transaction_repository.dart';
import 'package:money_spending_tracker/data/tables.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late LabelRepository labelRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TransactionRepository(db.transactionDao, db.importDao);
    labelRepo = LabelRepository(db.labelDao);
  });

  tearDown(() async {
    await db.close();
  });

  TransactionDraft draft({
    String? id,
    int amountCents = 1500,
    String note = 'Lunch',
    String? extraNotes,
  }) {
    return TransactionDraft(
      id: id,
      amountCents: amountCents,
      occurredAt: DateTime.utc(2026, 1, 15).millisecondsSinceEpoch,
      categoryId: kNoCategoryId,
      paymentMethodId: kNoPaymentMethodId,
      note: note,
      extraNotes: extraNotes,
    );
  }

  test('add -> edit -> delete round trip persists', () async {
    await repo.upsert(draft(note: 'Lunch with Sam'));
    final Transaction inserted = (await db.select(db.transactions).get()).single;
    expect(inserted.note, 'Lunch with Sam');
    expect(inserted.amountCents, 1500);
    expect(inserted.deletedAt, isNull);

    await repo.upsert(draft(id: inserted.id, amountCents: 2000, note: 'Lunch, updated'));
    final Transaction updated = (await repo.findById(inserted.id))!;
    expect(updated.amountCents, 2000);
    expect(updated.note, 'Lunch, updated');
    expect(updated.id, inserted.id);

    await repo.delete(inserted.id);
    expect(await repo.findById(inserted.id), isNull);
    final Transaction rawAfterDelete = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(inserted.id))).getSingle();
    expect(rawAfterDelete.deletedAt, isNotNull);
  });

  test('editing any field of a past entry works', () async {
    await repo.upsert(draft());
    final Transaction inserted = (await db.select(db.transactions).get()).single;

    await repo.upsert(
      TransactionDraft(
        id: inserted.id,
        amountCents: 999,
        occurredAt: DateTime.utc(2020, 5, 1).millisecondsSinceEpoch,
        categoryId: kNoCategoryId,
        paymentMethodId: kNoPaymentMethodId,
        note: 'Completely different',
        extraNotes: 'now with extra notes',
      ),
    );

    final Transaction updated = (await repo.findById(inserted.id))!;
    expect(updated.amountCents, 999);
    expect(updated.occurredAt, DateTime.utc(2020, 5, 1).millisecondsSinceEpoch);
    expect(updated.note, 'Completely different');
    expect(updated.extraNotes, 'now with extra notes');
  });

  test('rejects amount of 0', () async {
    await expectLater(repo.upsert(draft(amountCents: 0)), throwsA(anything));
  });

  test('rejects negative amount', () async {
    await expectLater(repo.upsert(draft(amountCents: -100)), throwsA(anything));
  });

  test('rejects blank note', () async {
    await expectLater(repo.upsert(draft(note: '   ')), throwsA(anything));
  });

  group('watchFiltered', () {
    Future<void> addAt({
      required DateTime occurredAt,
      String? categoryId,
      String? paymentMethodId,
      String note = 'entry',
      String? extraNotes,
      int amountCents = 500,
    }) {
      return repo.upsert(
        TransactionDraft(
          amountCents: amountCents,
          occurredAt: occurredAt.toUtc().millisecondsSinceEpoch,
          categoryId: categoryId ?? kNoCategoryId,
          paymentMethodId: paymentMethodId ?? kNoPaymentMethodId,
          note: note,
          extraNotes: extraNotes,
        ),
      );
    }

    test('range, category, and search compose as an intersection', () async {
      final Label food = await labelRepo.create(kind: LabelKind.category, name: 'Food');
      final Label travel = await labelRepo.create(kind: LabelKind.category, name: 'Travel');

      // In range, right category, matches search.
      await addAt(
        occurredAt: DateTime.utc(2026, 1, 10),
        categoryId: food.id,
        note: 'Lunch with Sam',
      );
      // In range, right category, but search won't match.
      await addAt(occurredAt: DateTime.utc(2026, 1, 11), categoryId: food.id, note: 'Groceries');
      // In range, wrong category.
      await addAt(
        occurredAt: DateTime.utc(2026, 1, 10),
        categoryId: travel.id,
        note: 'Lunch flight',
      );
      // Right category and search, but out of range.
      await addAt(
        occurredAt: DateTime.utc(2020, 1, 10),
        categoryId: food.id,
        note: 'Old lunch',
      );

      final TransactionFilter filter = TransactionFilter(
        range: DateRange(start: DateTime.utc(2026, 1, 1), end: DateTime.utc(2026, 1, 31)),
        categoryId: food.id,
        query: 'lunch',
      );

      final List<TransactionWithLabels> results = await repo.listFiltered(filter);
      expect(results, hasLength(1));
      expect(results.single.transaction.note, 'Lunch with Sam');
    });

    test('search matches extraNotes as well as note', () async {
      await addAt(occurredAt: DateTime.now(), note: 'Coffee', extraNotes: 'split with Alex');

      final TransactionFilter filter = TransactionFilter(
        range: DateRange.last30Days(),
        query: 'alex',
      );
      final List<TransactionWithLabels> results = await repo.listFiltered(filter);
      expect(results, hasLength(1));
    });

    test('filtering to the No Category placeholder returns exactly the flagged entries', () async {
      final Label food = await labelRepo.create(kind: LabelKind.category, name: 'Food');
      await addAt(occurredAt: DateTime.now(), categoryId: food.id, note: 'Categorized');
      await addAt(occurredAt: DateTime.now(), note: 'Uncategorized');

      final TransactionFilter filter = TransactionFilter(
        range: DateRange.last30Days(),
        categoryId: kNoCategoryId,
      );
      final List<TransactionWithLabels> results = await repo.listFiltered(filter);
      expect(results, hasLength(1));
      expect(results.single.needsAttention, isTrue);
      expect(results.single.transaction.note, 'Uncategorized');
    });

    test('category rollup includes descendant spending, exact match excludes it', () async {
      final Label food = await labelRepo.create(kind: LabelKind.category, name: 'Food');
      final Label restaurants = await labelRepo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );
      await addAt(occurredAt: DateTime.now(), categoryId: food.id, note: 'Direct food spend');
      await addAt(
        occurredAt: DateTime.now(),
        categoryId: restaurants.id,
        note: 'Restaurant spend',
      );

      final TransactionFilter rollup = TransactionFilter(
        range: DateRange.last30Days(),
        categoryId: food.id,
      );
      expect(await repo.listFiltered(rollup), hasLength(2));

      final TransactionFilter exact = TransactionFilter(
        range: DateRange.last30Days(),
        categoryId: food.id,
        rollupCategory: false,
      );
      final List<TransactionWithLabels> exactResults = await repo.listFiltered(exact);
      expect(exactResults, hasLength(1));
      expect(exactResults.single.transaction.note, 'Direct food spend');
    });

    test('newest first by default', () async {
      await addAt(occurredAt: DateTime.utc(2026, 1, 1), note: 'oldest');
      await addAt(occurredAt: DateTime.utc(2026, 1, 15), note: 'newest');
      await addAt(occurredAt: DateTime.utc(2026, 1, 8), note: 'middle');

      final List<TransactionWithLabels> results = await repo.listFiltered(
        TransactionFilter(
          range: DateRange(start: DateTime.utc(2026, 1, 1), end: DateTime.utc(2026, 1, 31)),
        ),
      );
      expect(results.map((e) => e.transaction.note), ['newest', 'middle', 'oldest']);
    });

    test('empty result set stays empty rather than falling back to unfiltered data', () async {
      await addAt(occurredAt: DateTime.now(), note: 'Something');

      final TransactionFilter filter = TransactionFilter(
        range: DateRange.last30Days(),
        query: 'no such text anywhere',
      );
      expect(await repo.listFiltered(filter), isEmpty);
    });
  });

  group('bulkReassign', () {
    Future<void> addAt({
      required DateTime occurredAt,
      String? categoryId,
      String? paymentMethodId,
      String note = 'entry',
    }) {
      return repo.upsert(
        TransactionDraft(
          amountCents: 500,
          occurredAt: occurredAt.toUtc().millisecondsSinceEpoch,
          categoryId: categoryId ?? kNoCategoryId,
          paymentMethodId: paymentMethodId ?? kNoPaymentMethodId,
          note: note,
        ),
      );
    }

    test('reassigns category and clears the needs-attention flag for selected entries', () async {
      final Label food = await labelRepo.create(kind: LabelKind.category, name: 'Food');
      await addAt(occurredAt: DateTime.now(), note: 'Uncategorized 1');
      await addAt(occurredAt: DateTime.now(), note: 'Uncategorized 2');
      await addAt(occurredAt: DateTime.now(), note: 'Left alone');

      final TransactionFilter noCategoryFilter = TransactionFilter(
        range: DateRange.last30Days(),
        categoryId: kNoCategoryId,
      );
      final List<TransactionWithLabels> flagged = await repo.listFiltered(noCategoryFilter);
      expect(flagged, hasLength(3));

      final Set<String> toReassign = flagged
          .where((e) => e.transaction.note.startsWith('Uncategorized'))
          .map((e) => e.transaction.id)
          .toSet();

      await repo.bulkReassign(ids: toReassign, categoryId: food.id);

      final List<TransactionWithLabels> stillFlagged = await repo.listFiltered(noCategoryFilter);
      expect(stillFlagged, hasLength(1));
      expect(stillFlagged.single.transaction.note, 'Left alone');

      final List<TransactionWithLabels> nowFood = await repo.listFiltered(
        TransactionFilter(range: DateRange.last30Days(), categoryId: food.id),
      );
      expect(nowFood.map((e) => e.transaction.note), unorderedEquals(['Uncategorized 1', 'Uncategorized 2']));
    });

    test('leaves payment method untouched when only reassigning category, and vice versa', () async {
      final Label food = await labelRepo.create(kind: LabelKind.category, name: 'Food');
      final Label cash = await labelRepo.create(kind: LabelKind.paymentMethod, name: 'Cash');
      await addAt(occurredAt: DateTime.now(), note: 'Entry');
      final Transaction inserted = (await db.select(db.transactions).get()).single;

      await repo.bulkReassign(ids: {inserted.id}, categoryId: food.id);
      Transaction updated = (await repo.findById(inserted.id))!;
      expect(updated.categoryId, food.id);
      expect(updated.paymentMethodId, kNoPaymentMethodId);

      await repo.bulkReassign(ids: {inserted.id}, paymentMethodId: cash.id);
      updated = (await repo.findById(inserted.id))!;
      expect(updated.categoryId, food.id);
      expect(updated.paymentMethodId, cash.id);
    });

    test('no-op for an empty id set', () async {
      await addAt(occurredAt: DateTime.now(), note: 'Entry');
      await repo.bulkReassign(ids: <String>{}, categoryId: kNoCategoryId);
      // Should not throw, and should not touch anything.
      expect(await repo.listFiltered(TransactionFilter(range: DateRange.last30Days())), hasLength(1));
    });
  });

  group('bulkDelete', () {
    Future<void> addAt({required String note}) {
      return repo.upsert(
        TransactionDraft(
          amountCents: 500,
          occurredAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          categoryId: kNoCategoryId,
          paymentMethodId: kNoPaymentMethodId,
          note: note,
        ),
      );
    }

    Future<List<TransactionWithLabels>> live() =>
        repo.listFiltered(TransactionFilter(range: DateRange.last30Days()));

    test('deletes exactly the selected entries and leaves the rest', () async {
      await addAt(note: 'Doomed one');
      await addAt(note: 'Doomed two');
      await addAt(note: 'Survivor');

      final Set<String> doomed = (await live())
          .where((TransactionWithLabels e) => e.transaction.note.startsWith('Doomed'))
          .map((TransactionWithLabels e) => e.transaction.id)
          .toSet();

      await repo.bulkDelete(doomed);

      final List<TransactionWithLabels> remaining = await live();
      expect(remaining, hasLength(1));
      expect(remaining.single.transaction.note, 'Survivor');
    });

    test('soft-deletes rather than removing rows', () async {
      await addAt(note: 'Entry');
      final String id = (await live()).single.transaction.id;

      await repo.bulkDelete({id});

      // The tombstone must survive — it is the sync marker, not an undo log.
      final Transaction row =
          (await (db.select(db.transactions)..where((t) => t.id.equals(id))).get()).single;
      expect(row.deletedAt, isNotNull);
      expect(await live(), isEmpty);
    });

    test('no-op for an empty id set', () async {
      await addAt(note: 'Entry');
      await repo.bulkDelete(<String>{});
      expect(await live(), hasLength(1));
    });

    test('deleted entries drop out of analytics totals too', () async {
      await addAt(note: 'Counted');
      await addAt(note: 'Removed');
      final Set<String> removed = (await live())
          .where((TransactionWithLabels e) => e.transaction.note == 'Removed')
          .map((TransactionWithLabels e) => e.transaction.id)
          .toSet();

      await repo.bulkDelete(removed);

      final AnalyticsSummary summary = await repo
          .watchSummary(TransactionFilter(range: DateRange.last30Days()), Bucket.day)
          .first;
      expect(summary.totalCents, 500);
    });
  });
}
