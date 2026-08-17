import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/core/csv_import.dart';
import 'package:money_spending_tracker/core/date_range.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/models/import_plan.dart';
import 'package:money_spending_tracker/data/models/transaction_draft.dart';
import 'package:money_spending_tracker/data/models/transaction_filter.dart';
import 'package:money_spending_tracker/data/repositories/label_repository.dart';
import 'package:money_spending_tracker/data/repositories/transaction_repository.dart';
import 'package:money_spending_tracker/data/tables.dart';
import 'package:money_spending_tracker/features/export/csv_export.dart';

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

  const String header = 'Date,Amount,Category,Payment Method,Note,Additional Notes';

  String csv(List<String> rows) => [header, ...rows].join('\n');

  Future<ImportPlan> planFor(String source) =>
      repo.planImport(CsvImport.parse(source));

  Future<ImportResult> importAll(
    String source, {
    Map<int, DuplicateChoice> choices = const {},
  }) async {
    final ImportPlan plan = await planFor(source);
    return repo.commitImport(plan, choices);
  }

  Future<List<Transaction>> liveTransactions() =>
      (db.select(db.transactions)..where((t) => t.deletedAt.isNull())).get();

  group('label resolution', () {
    test('reuses an existing label instead of creating a duplicate', () async {
      final Label food =
          await labelRepo.create(kind: LabelKind.category, name: 'Food');

      final ImportPlan plan = await planFor(
        csv(['2024-03-01T12:00:00.000,5.00,Food,Cash,Lunch,']),
      );
      expect(plan.newCategoryNames, isEmpty);
      expect(plan.newPaymentMethodNames, {'Cash'});

      await repo.commitImport(plan, const {});
      final Transaction inserted = (await liveTransactions()).single;
      expect(inserted.categoryId, food.id);
    });

    test('matches an existing label case-insensitively', () async {
      final Label food =
          await labelRepo.create(kind: LabelKind.category, name: 'Food');

      await importAll(csv(['2024-03-01T12:00:00.000,5.00,FOOD,Cash,Lunch,']));

      final Transaction inserted = (await liveTransactions()).single;
      expect(inserted.categoryId, food.id);
      final List<Label> categories =
          await db.labelDao.getAll(LabelKind.category);
      // Only the seeded placeholder plus the one real category.
      expect(categories.where((Label l) => !l.isPlaceholder), hasLength(1));
    });

    test('creates a missing label at the top level', () async {
      final ImportResult result = await importAll(
        csv(['2024-03-01T12:00:00.000,5.00,Groceries,Venmo,Milk,']),
      );

      expect(result.labelsCreated, 2);
      final Label created = (await db.labelDao.getAll(LabelKind.category))
          .firstWhere((Label l) => l.name == 'Groceries');
      expect(created.depth, 0);
      expect(created.parentId, isNull);
      expect(created.isPlaceholder, isFalse);
    });

    test('a name repeated across rows creates the label exactly once', () async {
      final ImportResult result = await importAll(
        csv([
          '2024-03-01T12:00:00.000,5.00,Groceries,Cash,Milk,',
          '2024-03-02T12:00:00.000,6.00,Groceries,Cash,Bread,',
          '2024-03-03T12:00:00.000,7.00,Groceries,Cash,Eggs,',
        ]),
      );

      expect(result.inserted, 3);
      expect(result.labelsCreated, 2); // Groceries + Cash
      expect(
        (await db.labelDao.getAll(LabelKind.category))
            .where((Label l) => l.name == 'Groceries'),
        hasLength(1),
      );
    });

    test('a blank label cell falls back to the placeholder (§2.6)', () async {
      await importAll(csv(['2024-03-01T12:00:00.000,5.00,,,Lunch,']));

      final Transaction inserted = (await liveTransactions()).single;
      expect(inserted.categoryId, kNoCategoryId);
      expect(inserted.paymentMethodId, kNoPaymentMethodId);
    });

    test('an ambiguous name resolves to the top-level label, deterministically',
        () async {
      // Export writes a label's own name, not its path, so "Restaurants" under
      // two parents is indistinguishable in the file. Shallowest wins.
      final Label top = await labelRepo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
      );
      final Label food =
          await labelRepo.create(kind: LabelKind.category, name: 'Food');
      await labelRepo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );

      await importAll(csv(['2024-03-01T12:00:00.000,5.00,Restaurants,Cash,Dinner,']));

      expect((await liveTransactions()).single.categoryId, top.id);
    });

    test('a category and a payment method may share a name without colliding',
        () async {
      await importAll(csv(['2024-03-01T12:00:00.000,5.00,Venmo,Venmo,Rent,']));

      final Transaction inserted = (await liveTransactions()).single;
      final Label category = (await db.labelDao.findById(inserted.categoryId))!;
      final Label payment =
          (await db.labelDao.findById(inserted.paymentMethodId))!;
      expect(category.kind, LabelKind.category);
      expect(payment.kind, LabelKind.paymentMethod);
      expect(category.id, isNot(payment.id));
    });
  });

  group('duplicate detection', () {
    // Every field the CSV carries must match. Anything looser would swallow
    // two genuinely separate purchases.
    const String row = '2024-03-01T12:00:00.000,5.00,Food,Cash,Lunch,notes here';

    Future<void> seedOriginal() => importAll(csv([row]));

    test('a fresh import finds no duplicates', () async {
      final ImportPlan plan = await planFor(csv([row]));
      expect(plan.duplicates, isEmpty);
      expect(plan.newRows, hasLength(1));
    });

    test('re-importing the same file flags every row as a duplicate', () async {
      await seedOriginal();
      final ImportPlan plan = await planFor(csv([row]));
      expect(plan.duplicates, hasLength(1));
      expect(plan.newRows, isEmpty);
    });

    test('a differing amount is not a duplicate', () async {
      await seedOriginal();
      final ImportPlan plan = await planFor(
        csv(['2024-03-01T12:00:00.000,5.01,Food,Cash,Lunch,notes here']),
      );
      expect(plan.duplicates, isEmpty);
    });

    test('a differing time is not a duplicate — same purchase, twice in a day',
        () async {
      await seedOriginal();
      final ImportPlan plan = await planFor(
        csv(['2024-03-01T18:00:00.000,5.00,Food,Cash,Lunch,notes here']),
      );
      expect(plan.duplicates, isEmpty);
      expect(plan.newRows, hasLength(1));
    });

    test('a differing note is not a duplicate', () async {
      await seedOriginal();
      final ImportPlan plan = await planFor(
        csv(['2024-03-01T12:00:00.000,5.00,Food,Cash,Dinner,notes here']),
      );
      expect(plan.duplicates, isEmpty);
    });

    test('a differing extra note is not a duplicate', () async {
      await seedOriginal();
      final ImportPlan plan = await planFor(
        csv(['2024-03-01T12:00:00.000,5.00,Food,Cash,Lunch,different']),
      );
      expect(plan.duplicates, isEmpty);
    });

    test('a differing category is not a duplicate', () async {
      await seedOriginal();
      final ImportPlan plan = await planFor(
        csv(['2024-03-01T12:00:00.000,5.00,Travel,Cash,Lunch,notes here']),
      );
      expect(plan.duplicates, isEmpty);
    });

    // Regression: a blank label cell resolves to the placeholder on import, so
    // the stored row reads "No Category" while the incoming cell is still ''.
    // Comparing raw text missed that, and the row re-imported as new on every
    // pass — an export/import loop would grow the file without bound.
    test('a blank label cell matches the placeholder it resolved to', () async {
      const String blank = '2024-03-01T12:00:00.000,5.00,,,Uncategorized,';
      await importAll(csv([blank]));

      final ImportPlan plan = await planFor(csv([blank]));
      expect(plan.duplicates, hasLength(1));
      expect(plan.newRows, isEmpty);
    });

    test('a re-imported export of a placeholder row is also a duplicate',
        () async {
      // The same case arriving the other way round: exporting writes the
      // placeholder's *name*, so the round trip must match too.
      await importAll(csv(['2024-03-01T12:00:00.000,5.00,,,Uncategorized,']));
      final String exported = CsvExport.serialize(
        await repo.listFiltered(_allTime()),
      );

      final ImportPlan plan = await planFor(exported);
      expect(plan.duplicates, hasLength(1));
      expect(plan.newRows, isEmpty);
    });

    test('a soft-deleted transaction does not count as an existing match',
        () async {
      await seedOriginal();
      await repo.delete((await liveTransactions()).single.id);

      final ImportPlan plan = await planFor(csv([row]));
      expect(plan.duplicates, isEmpty);
      expect(plan.newRows, hasLength(1));
    });

    test('two identical rows in one file match distinct existing rows', () async {
      // Seed two identical transactions, then re-import both. Each incoming
      // row must claim its own existing counterpart rather than both pointing
      // at the first.
      await importAll(csv([row, row]), choices: const {});
      expect(await liveTransactions(), hasLength(2));

      final ImportPlan plan = await planFor(csv([row, row]));
      expect(plan.duplicates, hasLength(2));
      expect(plan.newRows, isEmpty);
    });

    test('one file row against two identical existing rows claims only one',
        () async {
      await importAll(csv([row, row]));

      final ImportPlan plan = await planFor(csv([row]));
      expect(plan.duplicates, hasLength(1));
    });
  });

  group('duplicate choices', () {
    const String row = '2024-03-01T12:00:00.000,5.00,Food,Cash,Lunch,';

    test('keepBoth inserts a second copy', () async {
      await importAll(csv([row]));
      final ImportPlan plan = await planFor(csv([row]));
      final ImportResult result = await repo.commitImport(plan, {
        plan.duplicates.single.row.lineNumber: DuplicateChoice.keepBoth,
      });

      expect(result.inserted, 1);
      expect(result.skipped, 0);
      expect(await liveTransactions(), hasLength(2));
    });

    test('skip leaves the database untouched', () async {
      await importAll(csv([row]));
      final ImportPlan plan = await planFor(csv([row]));
      final ImportResult result = await repo.commitImport(plan, {
        plan.duplicates.single.row.lineNumber: DuplicateChoice.skip,
      });

      expect(result.skipped, 1);
      expect(result.inserted, 0);
      expect(await liveTransactions(), hasLength(1));
    });

    test('replace overwrites in place rather than adding a row', () async {
      await importAll(csv([row]));
      final String originalId = (await liveTransactions()).single.id;

      final ImportPlan plan = await planFor(csv([row]));
      final ImportResult result = await repo.commitImport(plan, {
        plan.duplicates.single.row.lineNumber: DuplicateChoice.replace,
      });

      expect(result.replaced, 1);
      final List<Transaction> after = await liveTransactions();
      expect(after, hasLength(1));
      expect(after.single.id, originalId);
    });

    test('an unanswered duplicate defaults to keepBoth, never to data loss',
        () async {
      await importAll(csv([row]));
      final ImportPlan plan = await planFor(csv([row]));
      final ImportResult result = await repo.commitImport(plan, const {});

      expect(result.inserted, 1);
      expect(await liveTransactions(), hasLength(2));
    });

    test('choices apply per row, so a mixed answer set is honoured', () async {
      const String rowB = '2024-03-02T12:00:00.000,6.00,Food,Cash,Dinner,';
      await importAll(csv([row, rowB]));

      final ImportPlan plan = await planFor(csv([row, rowB]));
      expect(plan.duplicates, hasLength(2));

      final ImportResult result = await repo.commitImport(plan, {
        plan.duplicates[0].row.lineNumber: DuplicateChoice.skip,
        plan.duplicates[1].row.lineNumber: DuplicateChoice.keepBoth,
      });

      expect(result.skipped, 1);
      expect(result.inserted, 1);
      expect(await liveTransactions(), hasLength(3));
    });
  });

  group('commit behaviour', () {
    test('unreadable rows are skipped but do not block the good ones', () async {
      final ImportResult result = await importAll(
        csv([
          '2024-03-01T12:00:00.000,5.00,Food,Cash,Good,',
          '2024-03-02T12:00:00.000,0,Food,Cash,Zero amount,',
          '2024-03-03T12:00:00.000,7.00,Food,Cash,Also good,',
        ]),
      );

      expect(result.inserted, 2);
      expect(result.errors, hasLength(1));
      expect(await liveTransactions(), hasLength(2));
    });

    test('planning writes nothing', () async {
      await planFor(csv(['2024-03-01T12:00:00.000,5.00,Groceries,Venmo,Milk,']));

      expect(await liveTransactions(), isEmpty);
      expect(
        (await db.labelDao.getAll(LabelKind.category))
            .where((Label l) => !l.isPlaceholder),
        isEmpty,
      );
    });

    test('a failed commit rolls back labels as well as rows', () async {
      // Label creation happens inside the same transaction as row insertion.
      // If a later row fails, the earlier rows AND the labels created for them
      // must both disappear — a partial import would leave the user with new
      // empty categories and no way to tell how far it got.
      //
      // The failure is forced by a row whose note is whitespace: it survives
      // the CSV quote-parse but trips the `length(trim(note)) > 0` CHECK. The
      // parser trims before its own blank check, so this can only be built by
      // hand-constructing the plan.
      final ImportPlan good = await planFor(
        csv(['2024-03-01T12:00:00.000,5.00,Groceries,Venmo,Milk,']),
      );
      final ImportPlan poisoned = ImportPlan(
        newRows: [
          ...good.newRows,
          const ImportRow(
            lineNumber: 99,
            occurredAt: 1709294400000,
            amountCents: 500,
            categoryName: 'Groceries',
            paymentMethodName: 'Venmo',
            note: '   ',
          ),
        ],
        duplicates: const [],
        errors: const [],
        newCategoryNames: good.newCategoryNames,
        newPaymentMethodNames: good.newPaymentMethodNames,
      );

      await expectLater(
        repo.commitImport(poisoned, const {}),
        throwsA(anything),
      );

      expect(await liveTransactions(), isEmpty);
      expect(
        (await db.labelDao.getAll(LabelKind.category))
            .where((Label l) => !l.isPlaceholder),
        isEmpty,
      );
    });

    test('an import of a real export lands the same data back', () async {
      // The end-to-end promise: export what you have, import it into an empty
      // database, and get the same entries with the same labels.
      final Label food =
          await labelRepo.create(kind: LabelKind.category, name: 'Food');
      final Label cash =
          await labelRepo.create(kind: LabelKind.paymentMethod, name: 'Cash');
      await db.transactionDao.upsert(
        _draft(
          amountCents: 1234,
          occurredAt: DateTime.utc(2024, 3, 1, 12).millisecondsSinceEpoch,
          categoryId: food.id,
          paymentMethodId: cash.id,
          note: 'Lunch with Sam',
          extraNotes: 'split 3 ways',
        ),
      );

      final String exported = CsvExport.serialize(
        await repo.listFiltered(_allTime()),
      );

      // Fresh database, same file — this is the "restore onto a new install"
      // path, so a second AppDatabase is the point of the test rather than an
      // accident. The executors are independent in-memory ones, so drift's
      // shared-executor race warning doesn't apply here.
      final bool priorWarnSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            priorWarnSetting,
      );

      final AppDatabase fresh =
          AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(fresh.close);
      final TransactionRepository freshRepo =
          TransactionRepository(fresh.transactionDao, fresh.importDao);

      final ImportResult result = await freshRepo.commitImport(
        await freshRepo.planImport(CsvImport.parse(exported)),
        const {},
      );

      expect(result.inserted, 1);
      final Transaction restored = (await (fresh.select(fresh.transactions)
            ..where((t) => t.deletedAt.isNull()))
          .get())
          .single;
      expect(restored.amountCents, 1234);
      expect(restored.note, 'Lunch with Sam');
      expect(restored.extraNotes, 'split 3 ways');
      expect(
        (await fresh.labelDao.findById(restored.categoryId))!.name,
        'Food',
      );
      expect(
        (await fresh.labelDao.findById(restored.paymentMethodId))!.name,
        'Cash',
      );
    });
  });
}

TransactionDraft _draft({
  required int amountCents,
  required int occurredAt,
  required String categoryId,
  required String paymentMethodId,
  required String note,
  String? extraNotes,
}) {
  return TransactionDraft(
    amountCents: amountCents,
    occurredAt: occurredAt,
    categoryId: categoryId,
    paymentMethodId: paymentMethodId,
    note: note,
    extraNotes: extraNotes,
  );
}

/// A range wide enough to hold every fixture, so the round-trip test exports
/// everything rather than whatever the default 30-day window happens to cover.
TransactionFilter _allTime() => TransactionFilter(
  range: DateRange(start: DateTime.utc(2000), end: DateTime.utc(2100)),
);
