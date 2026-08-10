import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_spending_tracker/core/bucketing.dart';
import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/core/date_range.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/models/analytics_series.dart';
import 'package:money_spending_tracker/data/models/transaction_draft.dart';
import 'package:money_spending_tracker/data/models/transaction_filter.dart';
import 'package:money_spending_tracker/data/repositories/label_repository.dart';
import 'package:money_spending_tracker/data/repositories/transaction_repository.dart';
import 'package:money_spending_tracker/data/tables.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late LabelRepository labelRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TransactionRepository(db.transactionDao);
    labelRepo = LabelRepository(db.labelDao);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> addAt({
    required DateTime occurredAt,
    required int amountCents,
    String? categoryId,
    String note = 'entry',
  }) {
    return repo.upsert(
      TransactionDraft(
        amountCents: amountCents,
        // Local time in, so bucketing lines up with what the user sees.
        occurredAt: occurredAt.millisecondsSinceEpoch,
        categoryId: categoryId ?? kNoCategoryId,
        paymentMethodId: kNoPaymentMethodId,
        note: note,
      ),
    );
  }

  Future<AnalyticsSummary> summarize(TransactionFilter f, Bucket bucket) =>
      repo.watchSummary(f, bucket).first;

  // A fixed range well away from "now", so tests don't drift with the clock.
  DateRange janRange() =>
      DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31, 23, 59, 59, 999));

  group('rollup', () {
    test("a parent's rollup total equals the sum of its subtree", () async {
      final Label food = await labelRepo.create(kind: LabelKind.category, name: 'Food');
      final Label restaurants = await labelRepo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );
      final Label fastFood = await labelRepo.create(
        kind: LabelKind.category,
        name: 'Fast Food',
        parentId: restaurants.id,
      );
      final Label travel = await labelRepo.create(kind: LabelKind.category, name: 'Travel');

      await addAt(occurredAt: DateTime(2026, 1, 5), amountCents: 1000, categoryId: food.id);
      await addAt(
        occurredAt: DateTime(2026, 1, 6),
        amountCents: 2000,
        categoryId: restaurants.id,
      );
      await addAt(occurredAt: DateTime(2026, 1, 7), amountCents: 500, categoryId: fastFood.id);
      // Outside the subtree — must not be rolled in.
      await addAt(occurredAt: DateTime(2026, 1, 8), amountCents: 9999, categoryId: travel.id);

      final AnalyticsSummary rolled = await summarize(
        TransactionFilter(range: janRange(), categoryId: food.id),
        Bucket.day,
      );
      expect(rolled.totalCents, 3500);

      // And the same scope without rollup sees only the direct entry.
      final AnalyticsSummary exact = await summarize(
        TransactionFilter(range: janRange(), categoryId: food.id, rollupCategory: false),
        Bucket.day,
      );
      expect(exact.totalCents, 1000);
    });

    test('rollup follows a moved subtree', () async {
      final Label food = await labelRepo.create(kind: LabelKind.category, name: 'Food');
      final Label travel = await labelRepo.create(kind: LabelKind.category, name: 'Travel');
      final Label snacks = await labelRepo.create(
        kind: LabelKind.category,
        name: 'Snacks',
        parentId: food.id,
      );
      await addAt(occurredAt: DateTime(2026, 1, 5), amountCents: 700, categoryId: snacks.id);

      TransactionFilter scope(String id) => TransactionFilter(range: janRange(), categoryId: id);

      expect((await summarize(scope(food.id), Bucket.day)).totalCents, 700);
      expect((await summarize(scope(travel.id), Bucket.day)).totalCents, 0);

      await labelRepo.move(snacks.id, travel.id);

      // The transaction never moved; only where it rolls up did.
      expect((await summarize(scope(food.id), Bucket.day)).totalCents, 0);
      expect((await summarize(scope(travel.id), Bucket.day)).totalCents, 700);
    });
  });

  group('by-category breakdown', () {
    test('absent for single-category scope, present for Combined', () async {
      final Label food = await labelRepo.create(kind: LabelKind.category, name: 'Food');
      await addAt(occurredAt: DateTime(2026, 1, 5), amountCents: 1000, categoryId: food.id);

      final AnalyticsSummary single = await summarize(
        TransactionFilter(range: janRange(), categoryId: food.id),
        Bucket.day,
      );
      expect(single.byCategory, isEmpty);

      final AnalyticsSummary combined = await summarize(
        TransactionFilter(range: janRange()),
        Bucket.day,
      );
      expect(combined.byCategory, isNotEmpty);
    });

    test('ranks categories by total, descending', () async {
      final Label food = await labelRepo.create(kind: LabelKind.category, name: 'Food');
      final Label travel = await labelRepo.create(kind: LabelKind.category, name: 'Travel');

      await addAt(occurredAt: DateTime(2026, 1, 5), amountCents: 300, categoryId: food.id);
      await addAt(occurredAt: DateTime(2026, 1, 6), amountCents: 400, categoryId: food.id);
      await addAt(occurredAt: DateTime(2026, 1, 7), amountCents: 5000, categoryId: travel.id);

      final AnalyticsSummary combined = await summarize(
        TransactionFilter(range: janRange()),
        Bucket.day,
      );
      expect(
        combined.byCategory.map((CategoryTotal c) => c.categoryName),
        ['Travel', 'Food'],
      );
      expect(combined.byCategory.first.totalCents, 5000);
      expect(combined.byCategory.last.totalCents, 700);
    });
  });

  group('bucketing', () {
    test('day buckets total per calendar day and fill empty days with zero', () async {
      await addAt(occurredAt: DateTime(2026, 1, 1, 9), amountCents: 100);
      await addAt(occurredAt: DateTime(2026, 1, 1, 18), amountCents: 250);
      // 2 Jan deliberately left empty.
      await addAt(occurredAt: DateTime(2026, 1, 3, 12), amountCents: 400);

      final AnalyticsSummary s = await summarize(
        TransactionFilter(
          range: DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 3, 23, 59, 59)),
        ),
        Bucket.day,
      );

      expect(s.series.map((BucketPoint p) => p.totalCents), [350, 0, 400]);
      expect(s.series.map((BucketPoint p) => p.start.day), [1, 2, 3]);
      expect(s.totalCents, 750);
    });

    test('week buckets group 7 days starting Monday', () async {
      // 5 Jan 2026 is a Monday; 11 Jan is the Sunday that closes that week.
      await addAt(occurredAt: DateTime(2026, 1, 5), amountCents: 100);
      await addAt(occurredAt: DateTime(2026, 1, 11, 23), amountCents: 200);
      await addAt(occurredAt: DateTime(2026, 1, 12), amountCents: 900);

      final AnalyticsSummary s = await summarize(
        TransactionFilter(
          range: DateRange(start: DateTime(2026, 1, 5), end: DateTime(2026, 1, 18, 23, 59, 59)),
        ),
        Bucket.week,
      );

      expect(s.series, hasLength(2));
      expect(s.series.first.start, DateTime(2026, 1, 5));
      expect(s.series.first.totalCents, 300);
      expect(s.series.last.start, DateTime(2026, 1, 12));
      expect(s.series.last.totalCents, 900);
    });

    test('month buckets group by calendar month', () async {
      await addAt(occurredAt: DateTime(2026, 1, 31), amountCents: 100);
      await addAt(occurredAt: DateTime(2026, 2, 1), amountCents: 200);
      await addAt(occurredAt: DateTime(2026, 3, 15), amountCents: 300);

      final AnalyticsSummary s = await summarize(
        TransactionFilter(
          range: DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 3, 31, 23, 59, 59)),
        ),
        Bucket.month,
      );

      expect(s.series.map((BucketPoint p) => p.totalCents), [100, 200, 300]);
    });

    test('re-bucketing the same filter preserves the total', () async {
      for (int day = 1; day <= 28; day++) {
        await addAt(occurredAt: DateTime(2026, 1, day, 10), amountCents: 100);
      }
      final TransactionFilter f = TransactionFilter(range: janRange());

      final AnalyticsSummary byDay = await summarize(f, Bucket.day);
      final AnalyticsSummary byWeek = await summarize(f, Bucket.week);
      final AnalyticsSummary byMonth = await summarize(f, Bucket.month);

      expect(byDay.totalCents, 2800);
      expect(byWeek.totalCents, 2800);
      expect(byMonth.totalCents, 2800);
      // Same data, different granularity — bucket counts must differ.
      expect(byDay.series.length, greaterThan(byWeek.series.length));
      expect(byWeek.series.length, greaterThan(byMonth.series.length));
      expect(byMonth.series, hasLength(1));
    });

    test('series plots per-period totals, not a cumulative sum', () async {
      await addAt(occurredAt: DateTime(2026, 1, 1), amountCents: 100);
      await addAt(occurredAt: DateTime(2026, 1, 2), amountCents: 100);
      await addAt(occurredAt: DateTime(2026, 1, 3), amountCents: 100);

      final AnalyticsSummary s = await summarize(
        TransactionFilter(
          range: DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 3, 23, 59, 59)),
        ),
        Bucket.day,
      );

      // Cumulative would be [100, 200, 300].
      expect(s.series.map((BucketPoint p) => p.totalCents), [100, 100, 100]);
    });

    test('a 5-day range defaults to Day buckets', () {
      final DateRange short = DateRange(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 5, 23, 59, 59),
      );
      expect(short.spanInDays, 5);
      expect(defaultBucketFor(short), Bucket.day);

      expect(defaultBucketFor(DateRange.last30Days()), Bucket.week);
    });
  });

  test('an empty filtered range yields a zero total and a zeroed axis', () async {
    await addAt(occurredAt: DateTime(2026, 1, 5), amountCents: 1000);

    final AnalyticsSummary s = await summarize(
      TransactionFilter(
        range: DateRange(start: DateTime(2025, 6, 1), end: DateTime(2025, 6, 3, 23, 59, 59)),
      ),
      Bucket.day,
    );

    expect(s.totalCents, 0);
    expect(s.byCategory, isEmpty);
    // Still an axis, so the chart renders an empty range rather than nothing.
    expect(s.series, hasLength(3));
    expect(s.series.every((BucketPoint p) => p.totalCents == 0), isTrue);
  });

  test('the summary respects payment-method and text filters too', () async {
    final Label cash = await labelRepo.create(kind: LabelKind.paymentMethod, name: 'Cash');
    await repo.upsert(
      TransactionDraft(
        amountCents: 1000,
        occurredAt: DateTime(2026, 1, 5).millisecondsSinceEpoch,
        categoryId: kNoCategoryId,
        paymentMethodId: cash.id,
        note: 'Coffee',
      ),
    );
    await addAt(occurredAt: DateTime(2026, 1, 6), amountCents: 5000, note: 'Rent');

    final AnalyticsSummary byPayment = await summarize(
      TransactionFilter(range: janRange(), paymentMethodId: cash.id),
      Bucket.day,
    );
    expect(byPayment.totalCents, 1000);

    final AnalyticsSummary byQuery = await summarize(
      TransactionFilter(range: janRange(), query: 'rent'),
      Bucket.day,
    );
    expect(byQuery.totalCents, 5000);
  });

  test('soft-deleted transactions drop out of the total', () async {
    await addAt(occurredAt: DateTime(2026, 1, 5), amountCents: 1000, note: 'Keep');
    await addAt(occurredAt: DateTime(2026, 1, 6), amountCents: 2500, note: 'Remove');

    final TransactionFilter f = TransactionFilter(range: janRange());
    expect((await summarize(f, Bucket.day)).totalCents, 3500);

    final Transaction doomed = (await repo.listFiltered(f))
        .firstWhere((e) => e.transaction.note == 'Remove')
        .transaction;
    await repo.delete(doomed.id);

    expect((await summarize(f, Bucket.day)).totalCents, 1000);
  });
}
