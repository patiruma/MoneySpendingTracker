import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/repositories/label_repository.dart';
import 'package:money_spending_tracker/data/tables.dart';
import 'package:money_spending_tracker/features/labels/labels_screen.dart';
import 'package:money_spending_tracker/shared/providers.dart';

/// Exercises the manage screen's nesting paths end to end through the real
/// widget tree, because every bug this file guards against lived in the
/// *dialog lifecycle*, not in the repository. `label_repository_test.dart`
/// already proves the SQL is right; these prove the UI can actually drive it.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  LabelRepository repo() => LabelRepository(db.labelDao);

  /// Live rows of one kind, straight from the table — the depth assertions below
  /// check the persisted value, not the tree the UI happened to render.
  Future<List<Label>> liveRows(LabelKind kind) => (db.select(db.labels)
        ..where((t) => t.kind.equalsValue(kind) & t.deletedAt.isNull()))
      .get();

  Future<void> pump(WidgetTester tester, {LabelKind kind = LabelKind.category}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: LabelsScreen(kind: kind)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  /// Drives the full two-step create flow: name prompt, then §3.1 confirmation.
  Future<void> createViaDialogs(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextFormField), name);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
  }

  /// The overflow menu button on a given row. Matched by its icon rather than
  /// by `PopupMenuButton<T>` — the action enum is private to the screen, so the
  /// generic type isn't nameable from here.
  Finder menuButtonFor(String nodeName) => find.descendant(
    of: find.widgetWithText(ListTile, nodeName),
    matching: find.byIcon(Icons.more_vert),
  );

  /// A row inside the open move sheet. The sheet renders *above* the manage
  /// list, so an unscoped `widgetWithText(ListTile, …)` matches the row
  /// underneath it too — every move assertion has to say which layer it means.
  Finder sheetRow(String name) => find.descendant(
    of: find.byType(DraggableScrollableSheet),
    matching: find.widgetWithText(ListTile, name),
  );

  /// Opens a node's overflow menu and selects [action].
  Future<void> tapMenu(WidgetTester tester, String nodeName, String action) async {
    await tester.tap(menuButtonFor(nodeName));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action).last);
    await tester.pumpAndSettle();
  }

  group('create', () {
    testWidgets('adds a top-level label via the FAB without a lifecycle error', (tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();
      await createViaDialogs(tester, 'Food');

      expect(find.widgetWithText(ListTile, 'Food'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('adds a child under an existing label', (tester) async {
      await repo().create(kind: LabelKind.category, name: 'Food');
      await pump(tester);

      await tapMenu(tester, 'Food', 'Add sub-category');
      await createViaDialogs(tester, 'Restaurants');

      expect(find.widgetWithText(ListTile, 'Restaurants'), findsOneWidget);
      final List<Label> rows = await liveRows(LabelKind.category);
      final Label child = rows.firstWhere((Label l) => l.name == 'Restaurants');
      expect(child.depth, 1);
      await unmount(tester);
    });

    testWidgets('adds a grandchild — the full 3 levels', (tester) async {
      final Label food = await repo().create(kind: LabelKind.category, name: 'Food');
      await repo().create(kind: LabelKind.category, name: 'Restaurants', parentId: food.id);
      await pump(tester);

      await tapMenu(tester, 'Restaurants', 'Add sub-category');
      await createViaDialogs(tester, 'Fast Food');

      expect(find.widgetWithText(ListTile, 'Fast Food'), findsOneWidget);
      final List<Label> rows = await liveRows(LabelKind.category);
      expect(rows.firstWhere((Label l) => l.name == 'Fast Food').depth, 2);
      await unmount(tester);
    });

    testWidgets('a depth-2 node offers no Add sub-category action', (tester) async {
      final Label food = await repo().create(kind: LabelKind.category, name: 'Food');
      final Label rest =
          await repo().create(kind: LabelKind.category, name: 'Restaurants', parentId: food.id);
      await repo().create(kind: LabelKind.category, name: 'Fast Food', parentId: rest.id);
      await pump(tester);

      await tester.tap(menuButtonFor('Fast Food'));
      await tester.pumpAndSettle();

      expect(find.text('Add sub-category'), findsNothing);
      expect(find.text('Rename'), findsOneWidget);

      await tester.tapAt(const Offset(5, 5)); // dismiss the menu
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('a duplicate sibling name surfaces a snackbar, not a crash', (tester) async {
      await repo().create(kind: LabelKind.category, name: 'Food');
      await pump(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();
      await createViaDialogs(tester, 'Food');

      expect(find.text('"Food" already exists here.'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('cancelling the name prompt leaves nothing behind', (tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Discarded');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Discarded'), findsNothing);
      await unmount(tester);
    });

    testWidgets('cancelling the confirmation does not create the label', (tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Discarded');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Discarded'), findsNothing);
      await unmount(tester);
    });

    testWidgets('a blank name is rejected by the prompt validator', (tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a name'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('creating repeatedly in one session stays stable', (tester) async {
      await pump(tester);

      // The lifecycle bug only reliably bit on the *second* dialog of a
      // session, once a disposed controller was still wired into the tree.
      for (final String name in <String>['One', 'Two', 'Three']) {
        await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
        await tester.pumpAndSettle();
        await createViaDialogs(tester, name);
      }

      expect(find.widgetWithText(ListTile, 'One'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Two'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Three'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('rename', () {
    testWidgets('renames a label and prefills the current name', (tester) async {
      await repo().create(kind: LabelKind.category, name: 'Food');
      await pump(tester);

      await tapMenu(tester, 'Food', 'Rename');
      expect(find.widgetWithText(TextFormField, 'Food'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Groceries');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Groceries'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Food'), findsNothing);
      await unmount(tester);
    });

    testWidgets('renaming then immediately adding does not trip the lifecycle', (tester) async {
      await repo().create(kind: LabelKind.category, name: 'Food');
      await pump(tester);

      await tapMenu(tester, 'Food', 'Rename');
      await tester.enterText(find.byType(TextFormField), 'Groceries');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      await tapMenu(tester, 'Groceries', 'Add sub-category');
      await createViaDialogs(tester, 'Produce');

      expect(find.widgetWithText(ListTile, 'Produce'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('move', () {
    testWidgets('moves a top-level label under another', (tester) async {
      await repo().create(kind: LabelKind.category, name: 'Food');
      await repo().create(kind: LabelKind.category, name: 'Snacks');
      await pump(tester);

      await tapMenu(tester, 'Snacks', 'Move');
      await tester.tap(sheetRow('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();

      final List<Label> rows = await liveRows(LabelKind.category);
      final Label snacks = rows.firstWhere((Label l) => l.name == 'Snacks');
      expect(snacks.depth, 1);
      expect(snacks.parentId, rows.firstWhere((Label l) => l.name == 'Food').id);
      await unmount(tester);
    });

    testWidgets('moves a child back out to top level', (tester) async {
      final Label food = await repo().create(kind: LabelKind.category, name: 'Food');
      await repo().create(kind: LabelKind.category, name: 'Snacks', parentId: food.id);
      await pump(tester);

      await tapMenu(tester, 'Snacks', 'Move');
      await tester.tap(sheetRow('Top level'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();

      final List<Label> rows = await liveRows(LabelKind.category);
      final Label snacks = rows.firstWhere((Label l) => l.name == 'Snacks');
      expect(snacks.depth, 0);
      expect(snacks.parentId, isNull);
      await unmount(tester);
    });

    testWidgets('a move shifts descendant depths too', (tester) async {
      await repo().create(kind: LabelKind.category, name: 'Food');
      final Label snacks = await repo().create(kind: LabelKind.category, name: 'Snacks');
      await repo().create(kind: LabelKind.category, name: 'Chips', parentId: snacks.id);
      await pump(tester);

      await tapMenu(tester, 'Snacks', 'Move');
      await tester.tap(sheetRow('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();

      final List<Label> rows = await liveRows(LabelKind.category);
      expect(rows.firstWhere((Label l) => l.name == 'Snacks').depth, 1);
      expect(rows.firstWhere((Label l) => l.name == 'Chips').depth, 2);
      await unmount(tester);
    });

    testWidgets('a destination that would overflow the depth cap is not offered', (tester) async {
      // Snacks has height 1, so it can only land at depth 0 or 1 — never under
      // Restaurants (depth 1), which would put Chips at depth 3.
      final Label food = await repo().create(kind: LabelKind.category, name: 'Food');
      await repo().create(kind: LabelKind.category, name: 'Restaurants', parentId: food.id);
      final Label snacks = await repo().create(kind: LabelKind.category, name: 'Snacks');
      await repo().create(kind: LabelKind.category, name: 'Chips', parentId: snacks.id);
      await pump(tester);

      await tapMenu(tester, 'Snacks', 'Move');

      expect(sheetRow('Food'), findsOneWidget);
      expect(sheetRow('Restaurants'), findsNothing);

      await tester.tap(sheetRow('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('a node cannot be offered itself or its own descendants', (tester) async {
      final Label food = await repo().create(kind: LabelKind.category, name: 'Food');
      await repo().create(kind: LabelKind.category, name: 'Restaurants', parentId: food.id);
      await repo().create(kind: LabelKind.category, name: 'Other');
      await pump(tester);

      await tapMenu(tester, 'Food', 'Move');

      // The sheet's header names the moving node; the *rows* must not.
      expect(sheetRow('Food'), findsNothing);
      expect(sheetRow('Restaurants'), findsNothing);
      expect(sheetRow('Other'), findsOneWidget);

      await tester.tap(sheetRow('Other'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });
  });

  group('delete', () {
    testWidgets('deletes a leaf', (tester) async {
      await repo().create(kind: LabelKind.category, name: 'Food');
      await pump(tester);

      await tapMenu(tester, 'Food', 'Delete');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Food'), findsNothing);
      await unmount(tester);
    });

    testWidgets('deleting a parent cascades to its children', (tester) async {
      final Label food = await repo().create(kind: LabelKind.category, name: 'Food');
      await repo().create(kind: LabelKind.category, name: 'Restaurants', parentId: food.id);
      await pump(tester);

      await tapMenu(tester, 'Food', 'Delete');
      expect(find.textContaining('and its 1 sub-categories'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Food'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Restaurants'), findsNothing);
      await unmount(tester);
    });
  });

  group('placeholders', () {
    testWidgets('the placeholder row exposes no actions', (tester) async {
      await pump(tester);

      expect(find.widgetWithText(ListTile, 'No Category'), findsOneWidget);
      expect(menuButtonFor('No Category'), findsNothing);
      await unmount(tester);
    });

    testWidgets('the placeholder is not offered as a move destination', (tester) async {
      await repo().create(kind: LabelKind.category, name: 'Food');
      await repo().create(kind: LabelKind.category, name: 'Snacks');
      await pump(tester);

      await tapMenu(tester, 'Snacks', 'Move');
      expect(sheetRow('No Category'), findsNothing);

      await tester.tap(sheetRow('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });
  });

  group('payment methods', () {
    testWidgets('the same nesting flow works for the payment-method kind', (tester) async {
      await repo().create(kind: LabelKind.paymentMethod, name: 'Card');
      await pump(tester, kind: LabelKind.paymentMethod);

      expect(find.text('Manage Payment Methods'), findsOneWidget);

      await tapMenu(tester, 'Card', 'Add sub-payment method');
      await createViaDialogs(tester, 'Visa');

      expect(find.widgetWithText(ListTile, 'Visa'), findsOneWidget);
      final List<Label> rows = await liveRows(LabelKind.paymentMethod);
      expect(rows.firstWhere((Label l) => l.name == 'Visa').depth, 1);
      await unmount(tester);
    });
  });
}
