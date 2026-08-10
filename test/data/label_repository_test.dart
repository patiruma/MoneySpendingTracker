import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/core/ids.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/models/impacts.dart';
import 'package:money_spending_tracker/data/models/label_node.dart';
import 'package:money_spending_tracker/data/repositories/label_repository.dart';
import 'package:money_spending_tracker/data/tables.dart';

void main() {
  late AppDatabase db;
  late LabelRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LabelRepository(db.labelDao);
  });

  tearDown(() async {
    await db.close();
  });

  /// Inserts a live transaction pointing at the given labels.
  Future<String> addTransaction({
    String? categoryId,
    String? paymentMethodId,
    int amountCents = 1000,
  }) async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final String id = newId();
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        id: id,
        amountCents: amountCents,
        occurredAt: now,
        categoryId: categoryId ?? kNoCategoryId,
        paymentMethodId: paymentMethodId ?? kNoPaymentMethodId,
        note: 'test entry',
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<Transaction> readTransaction(String id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();

  Future<Label?> readLabelRaw(String id) =>
      (db.select(db.labels)..where((t) => t.id.equals(id))).getSingleOrNull();

  // ------------------------------------------------------------- creation

  group('create', () {
    test('creates a top-level label at depth 0', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      expect(food.depth, 0);
      expect(food.parentId, isNull);
      expect(food.isPlaceholder, isFalse);
    });

    test('nests to depth 1 and 2', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label rest = await repo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );
      final Label fast = await repo.create(
        kind: LabelKind.category,
        name: 'Fast Food',
        parentId: rest.id,
      );
      expect(rest.depth, 1);
      expect(fast.depth, 2);
    });

    test('depth cap rejects a 4th level', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label rest = await repo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );
      final Label fast = await repo.create(
        kind: LabelKind.category,
        name: 'Fast Food',
        parentId: rest.id,
      );

      await expectLater(
        repo.create(kind: LabelKind.category, name: 'Burgers', parentId: fast.id),
        throwsA(isA<LabelException>()),
      );
    });

    test('duplicate sibling name is rejected', () async {
      await repo.create(kind: LabelKind.category, name: 'Food');
      await expectLater(
        repo.create(kind: LabelKind.category, name: 'Food'),
        throwsA(isA<LabelException>()),
      );
    });

    test('duplicate sibling name is rejected case-insensitively', () async {
      await repo.create(kind: LabelKind.category, name: 'Food');
      await expectLater(
        repo.create(kind: LabelKind.category, name: 'food'),
        throwsA(isA<LabelException>()),
      );
    });

    test('the same name is allowed under different parents', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label travel = await repo.create(kind: LabelKind.category, name: 'Travel');

      await repo.create(kind: LabelKind.category, name: 'Misc', parentId: food.id);
      await repo.create(kind: LabelKind.category, name: 'Misc', parentId: travel.id);

      final List<LabelNode> tree = await repo.getTree(LabelKind.category);
      expect(tree.expand((LabelNode n) => n.selfAndDescendants).length, 5);
    });

    test('the same name is allowed across kinds', () async {
      await repo.create(kind: LabelKind.category, name: 'Cash');
      await repo.create(kind: LabelKind.paymentMethod, name: 'Cash');

      final List<LabelNode> categories = await repo.getTree(LabelKind.category);
      final List<LabelNode> methods = await repo.getTree(LabelKind.paymentMethod);
      expect(categories.where((LabelNode n) => n.name == 'Cash'), hasLength(1));
      expect(methods.where((LabelNode n) => n.name == 'Cash'), hasLength(1));
    });

    test('a blank name is rejected', () async {
      await expectLater(
        repo.create(kind: LabelKind.category, name: '   '),
        throwsA(isA<LabelException>()),
      );
    });

    test('a placeholder cannot be used as a parent', () async {
      await expectLater(
        repo.create(kind: LabelKind.category, name: 'Nope', parentId: kNoCategoryId),
        throwsA(isA<LabelException>()),
      );
    });
  });

  // --------------------------------------------------------------- rename

  group('rename', () {
    test('leaves transaction rows untouched', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final String txId = await addTransaction(categoryId: food.id);
      final Transaction before = await readTransaction(txId);

      await repo.rename(food.id, 'Groceries');

      final Transaction after = await readTransaction(txId);
      expect(after.categoryId, food.id);
      expect(after.categoryId, before.categoryId);

      // The rename cascade is a display consequence of the id reference.
      final Label? renamed = await repo.findById(food.id);
      expect(renamed!.name, 'Groceries');
    });

    test('previewRename counts referencing entries', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      await addTransaction(categoryId: food.id);
      await addTransaction(categoryId: food.id);
      await addTransaction();

      final RenameImpact impact = await repo.previewRename(food.id);
      expect(impact.affectedTransactionCount, 2);
    });

    test('rejects a duplicate sibling name', () async {
      await repo.create(kind: LabelKind.category, name: 'Food');
      final Label travel = await repo.create(kind: LabelKind.category, name: 'Travel');

      await expectLater(
        repo.rename(travel.id, 'Food'),
        throwsA(isA<LabelException>()),
      );
    });

    test('renaming to its own current name is a no-op, not a clash', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      await repo.rename(food.id, 'Food');
      expect((await repo.findById(food.id))!.name, 'Food');
    });

    test('placeholder rename throws', () async {
      await expectLater(
        repo.rename(kNoCategoryId, 'Something Else'),
        throwsA(isA<LabelException>()),
      );
    });
  });

  // ----------------------------------------------------------------- move

  group('move', () {
    test('rejects a cycle: moving a node under its own descendant', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label rest = await repo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );

      final MoveImpact preview = await repo.previewMove(food.id, rest.id);
      expect(preview.valid, isFalse);
      expect(preview.reason, isNotNull);

      await expectLater(
        repo.move(food.id, rest.id),
        throwsA(isA<LabelException>()),
      );
    });

    test('rejects moving a node into itself', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final MoveImpact preview = await repo.previewMove(food.id, food.id);
      expect(preview.valid, isFalse);
      await expectLater(repo.move(food.id, food.id), throwsA(isA<LabelException>()));
    });

    test('rejects a depth overflow', () async {
      // Food > Restaurants > Fast Food  (height 2), moved under Travel > Trips
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label rest = await repo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );
      await repo.create(kind: LabelKind.category, name: 'Fast Food', parentId: rest.id);

      final Label travel = await repo.create(kind: LabelKind.category, name: 'Travel');
      final Label trips = await repo.create(
        kind: LabelKind.category,
        name: 'Trips',
        parentId: travel.id,
      );

      // dp(1) + 1 + h(2) = 4 > kMaxDepth(2)
      final MoveImpact preview = await repo.previewMove(food.id, trips.id);
      expect(preview.valid, isFalse);
      await expectLater(repo.move(food.id, trips.id), throwsA(isA<LabelException>()));
    });

    test('recomputes descendant depths across the whole subtree', () async {
      // Food > Restaurants > Fast Food, then move Restaurants to top level.
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label rest = await repo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );
      final Label fast = await repo.create(
        kind: LabelKind.category,
        name: 'Fast Food',
        parentId: rest.id,
      );
      expect(rest.depth, 1);
      expect(fast.depth, 2);

      await repo.move(rest.id, null);

      expect((await repo.findById(rest.id))!.depth, 0);
      expect((await repo.findById(rest.id))!.parentId, isNull);
      // The descendant shifted too — this is the depth-shift under test.
      expect((await repo.findById(fast.id))!.depth, 1);
      expect((await repo.findById(fast.id))!.parentId, rest.id);
      expect((await repo.findById(food.id))!.depth, 0);
    });

    test('shifts depth downward when moving deeper', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label snacks = await repo.create(kind: LabelKind.category, name: 'Snacks');
      final Label chips = await repo.create(
        kind: LabelKind.category,
        name: 'Chips',
        parentId: snacks.id,
      );

      await repo.move(snacks.id, food.id);

      expect((await repo.findById(snacks.id))!.depth, 1);
      expect((await repo.findById(chips.id))!.depth, 2);
    });

    test('leaves transactions untouched', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label snacks = await repo.create(kind: LabelKind.category, name: 'Snacks');
      final String txId = await addTransaction(categoryId: snacks.id);

      await repo.move(snacks.id, food.id);

      expect((await readTransaction(txId)).categoryId, snacks.id);
    });

    test('rejects a duplicate sibling name at the destination', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      await repo.create(kind: LabelKind.category, name: 'Misc', parentId: food.id);
      final Label topMisc = await repo.create(kind: LabelKind.category, name: 'Misc');

      final MoveImpact preview = await repo.previewMove(topMisc.id, food.id);
      expect(preview.valid, isFalse);
      await expectLater(repo.move(topMisc.id, food.id), throwsA(isA<LabelException>()));
    });

    test('previewMove reports the subtree count', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      await repo.create(kind: LabelKind.category, name: 'A', parentId: food.id);
      final Label b = await repo.create(kind: LabelKind.category, name: 'B', parentId: food.id);
      await repo.create(kind: LabelKind.category, name: 'B1', parentId: b.id);
      await repo.create(kind: LabelKind.category, name: 'Travel');

      final Label travel =
          (await repo.getTree(LabelKind.category)).firstWhere((LabelNode n) => n.name == 'Travel').label;
      final MoveImpact preview = await repo.previewMove(food.id, travel.id);
      expect(preview.subtreeCount, 3);
    });

    test('placeholder move throws', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final MoveImpact preview = await repo.previewMove(kNoCategoryId, food.id);
      expect(preview.valid, isFalse);
      await expectLater(
        repo.move(kNoCategoryId, food.id),
        throwsA(isA<LabelException>()),
      );
    });

    test('a placeholder cannot be a move destination', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final MoveImpact preview = await repo.previewMove(food.id, kNoCategoryId);
      expect(preview.valid, isFalse);
      await expectLater(
        repo.move(food.id, kNoCategoryId),
        throwsA(isA<LabelException>()),
      );
    });
  });

  // --------------------------------------------------------------- delete

  group('deleteCascade', () {
    test('reassigns referencing transactions to the placeholder', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final String txId = await addTransaction(categoryId: food.id);

      await repo.deleteCascade(food.id);

      expect((await readTransaction(txId)).categoryId, kNoCategoryId);
    });

    test('cascades to children and reassigns their transactions too', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label rest = await repo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );
      final Label fast = await repo.create(
        kind: LabelKind.category,
        name: 'Fast Food',
        parentId: rest.id,
      );

      final String parentTx = await addTransaction(categoryId: food.id);
      final String childTx = await addTransaction(categoryId: rest.id);
      final String grandchildTx = await addTransaction(categoryId: fast.id);

      await repo.deleteCascade(food.id);

      // Whole subtree is gone from live reads.
      expect(await repo.findById(food.id), isNull);
      expect(await repo.findById(rest.id), isNull);
      expect(await repo.findById(fast.id), isNull);

      // Every referencing entry fell back to the placeholder (§2.4, §2.6).
      expect((await readTransaction(parentTx)).categoryId, kNoCategoryId);
      expect((await readTransaction(childTx)).categoryId, kNoCategoryId);
      expect((await readTransaction(grandchildTx)).categoryId, kNoCategoryId);
    });

    test('is a soft delete — rows survive with deleted_at set', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      await repo.deleteCascade(food.id);

      final Label? raw = await readLabelRaw(food.id);
      expect(raw, isNotNull);
      expect(raw!.deletedAt, isNotNull);
    });

    test('frees the name for reuse afterwards', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      await repo.deleteCascade(food.id);

      // The partial unique index covers live rows only, so this must succeed.
      final Label recreated = await repo.create(kind: LabelKind.category, name: 'Food');
      expect(recreated.id, isNot(food.id));
    });

    test('does not touch transactions of a different kind', () async {
      final Label cash = await repo.create(kind: LabelKind.paymentMethod, name: 'Cash');
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final String txId = await addTransaction(categoryId: food.id, paymentMethodId: cash.id);

      await repo.deleteCascade(cash.id);

      final Transaction tx = await readTransaction(txId);
      expect(tx.paymentMethodId, kNoPaymentMethodId);
      // The category side is untouched.
      expect(tx.categoryId, food.id);
    });

    test('previewDelete counts descendants and affected entries', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label rest = await repo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );
      await repo.create(kind: LabelKind.category, name: 'Fast Food', parentId: rest.id);

      await addTransaction(categoryId: food.id);
      await addTransaction(categoryId: rest.id);
      await addTransaction(); // unrelated, on the placeholder

      final DeleteImpact impact = await repo.previewDelete(food.id);
      expect(impact.descendantCount, 2);
      expect(impact.affectedTransactionCount, 2);
    });

    test('placeholder delete throws', () async {
      await expectLater(
        repo.deleteCascade(kNoCategoryId),
        throwsA(isA<LabelException>()),
      );
    });
  });

  // ------------------------------------------------------- subtree & tree

  group('subtreeIds', () {
    test('returns the node and all descendants', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label rest = await repo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );
      final Label fast = await repo.create(
        kind: LabelKind.category,
        name: 'Fast Food',
        parentId: rest.id,
      );
      await repo.create(kind: LabelKind.category, name: 'Travel');

      final Set<String> ids = await repo.subtreeIds(food.id);
      expect(ids, {food.id, rest.id, fast.id});
    });

    test('a leaf returns just itself', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      expect(await repo.subtreeIds(food.id), {food.id});
    });

    test('excludes soft-deleted descendants', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      final Label rest = await repo.create(
        kind: LabelKind.category,
        name: 'Restaurants',
        parentId: food.id,
      );
      await repo.deleteCascade(rest.id);

      expect(await repo.subtreeIds(food.id), {food.id});
    });
  });

  group('watchTree', () {
    test('emits the seeded placeholder and re-emits on write', () async {
      final Stream<List<LabelNode>> stream = repo.watchTree(LabelKind.category);

      final List<LabelNode> first = await stream.first;
      expect(first, hasLength(1));
      expect(first.single.id, kNoCategoryId);

      await repo.create(kind: LabelKind.category, name: 'Food');

      final List<LabelNode> next = await stream.first;
      expect(next, hasLength(2));
    });

    test('nests children under parents', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      await repo.create(kind: LabelKind.category, name: 'Restaurants', parentId: food.id);

      final List<LabelNode> tree = await repo.getTree(LabelKind.category);
      final LabelNode foodNode = tree.firstWhere((LabelNode n) => n.id == food.id);
      expect(foodNode.children, hasLength(1));
      expect(foodNode.children.single.name, 'Restaurants');
    });

    test('sorts siblings alphabetically with placeholders last', () async {
      await repo.create(kind: LabelKind.category, name: 'Zebra');
      await repo.create(kind: LabelKind.category, name: 'apple');

      final List<LabelNode> tree = await repo.getTree(LabelKind.category);
      expect(tree.map((LabelNode n) => n.name).toList(), ['apple', 'Zebra', 'No Category']);
    });

    test('separates the two kinds', () async {
      await repo.create(kind: LabelKind.category, name: 'Food');
      await repo.create(kind: LabelKind.paymentMethod, name: 'Cash');

      final List<LabelNode> categories = await repo.getTree(LabelKind.category);
      final List<LabelNode> methods = await repo.getTree(LabelKind.paymentMethod);
      expect(categories.map((LabelNode n) => n.name), containsAll(['Food', 'No Category']));
      expect(categories.map((LabelNode n) => n.name), isNot(contains('Cash')));
      expect(methods.map((LabelNode n) => n.name), containsAll(['Cash', 'No Payment Method']));
    });
  });

  group('search', () {
    test('matches a substring case-insensitively', () async {
      await repo.create(kind: LabelKind.category, name: 'Restaurants');
      await repo.create(kind: LabelKind.category, name: 'Travel');

      final List<Label> hits = await repo.search(LabelKind.category, 'REST');
      expect(hits.map((Label l) => l.name), ['Restaurants']);
    });

    test('an empty query returns everything of the kind', () async {
      await repo.create(kind: LabelKind.category, name: 'Food');
      final List<Label> hits = await repo.search(LabelKind.category, '');
      expect(hits, hasLength(2)); // Food + placeholder
    });

    test('excludes deleted labels', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      await repo.deleteCascade(food.id);

      expect(await repo.search(LabelKind.category, 'Food'), isEmpty);
    });
  });

  group('findByName', () {
    test('scopes to the sibling group', () async {
      final Label food = await repo.create(kind: LabelKind.category, name: 'Food');
      await repo.create(kind: LabelKind.category, name: 'Misc', parentId: food.id);

      expect(await repo.findByName(LabelKind.category, 'Misc'), isNull);
      expect(
        await repo.findByName(LabelKind.category, 'Misc', parentId: food.id),
        isNotNull,
      );
    });
  });
}
