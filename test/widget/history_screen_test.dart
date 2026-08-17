import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/core/ids.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/models/transaction_with_labels.dart';
import 'package:money_spending_tracker/features/history/history_screen.dart';
import 'package:money_spending_tracker/shared/providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> addTransaction({
    String? categoryId,
    String note = 'entry',
    DateTime? occurredAt,
  }) async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final String id = newId();
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        id: id,
        amountCents: 1000,
        occurredAt: (occurredAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
        categoryId: categoryId ?? kNoCategoryId,
        paymentMethodId: kNoPaymentMethodId,
        note: note,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> pumpHistoryScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: HistoryScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty state when nothing matches', (tester) async {
    await pumpHistoryScreen(tester);

    expect(find.text('No transactions match these filters.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('lists live transactions newest first', (tester) async {
    await addTransaction(note: 'Older', occurredAt: DateTime.now().subtract(const Duration(days: 2)));
    await addTransaction(note: 'Newer', occurredAt: DateTime.now());

    await pumpHistoryScreen(tester);

    final Finder tiles = find.byType(ListTile);
    expect(tiles, findsNWidgets(2));
    expect(
      tester.widget<Text>(find.descendant(of: tiles.first, matching: find.byType(Text)).first).data,
      'Newer',
    );

    await unmount(tester);
  });

  testWidgets('needs-attention chip filters to No Category entries', (tester) async {
    await addTransaction(note: 'Flagged'); // defaults to No Category
    await pumpHistoryScreen(tester);

    expect(find.text('Flagged'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Needs attention'));
    await tester.pumpAndSettle();

    expect(find.text('Flagged'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('long-press enters selection mode and shows the selection bar', (tester) async {
    await addTransaction(note: 'Entry one');
    await addTransaction(note: 'Entry two');
    await pumpHistoryScreen(tester);

    await tester.longPress(find.text('Entry one'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Select all'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reassign'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('select all selects every currently filtered entry', (tester) async {
    await addTransaction(note: 'Entry one');
    await addTransaction(note: 'Entry two');
    await pumpHistoryScreen(tester);

    await tester.longPress(find.text('Entry one'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Select all'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);

    await unmount(tester);
  });

  test('selection is scoped to the visible list when the filter narrows', () async {
    await addTransaction(note: 'Alpha');
    await addTransaction(note: 'Beta');

    final ProviderContainer container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    // Keep the stream alive for the duration of the test.
    final ProviderSubscription<AsyncValue<List<TransactionWithLabels>>> sub = container
        .listen(historyTransactionsProvider, (_, _) {});
    addTearDown(sub.close);

    await container.read(historyTransactionsProvider.future);
    final List<TransactionWithLabels> all = container
        .read(historyTransactionsProvider)
        .value!;
    expect(all, hasLength(2));

    // Select everything currently filtered in, as "Select all" does.
    container.read(historySelectionProvider.notifier).state = all
        .map((TransactionWithLabels e) => e.transaction.id)
        .toSet();
    expect(container.read(historyVisibleSelectionProvider), hasLength(2));

    // Narrow so only "Alpha" matches.
    container.read(historyFilterProvider.notifier).state = container
        .read(historyFilterProvider)
        .copyWith(query: 'Alpha');
    await container.read(historyTransactionsProvider.future);

    // "Beta" is no longer visible, so it must no longer be reassignable —
    // otherwise a bulk write would silently touch an entry the user can't see.
    final Set<String> visible = container.read(historyVisibleSelectionProvider);
    expect(visible, hasLength(1));
    expect(
      visible.single,
      all.firstWhere((TransactionWithLabels e) => e.transaction.note == 'Alpha').transaction.id,
    );
  });

  testWidgets('the selection bar offers a delete action alongside Reassign', (tester) async {
    await addTransaction(note: 'Entry one');
    await pumpHistoryScreen(tester);

    await tester.longPress(find.text('Entry one'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Reassign'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byTooltip('Delete 1 entry'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('bulk delete removes the selected entries after confirming', (tester) async {
    await addTransaction(note: 'Doomed one');
    await addTransaction(note: 'Doomed two');
    await pumpHistoryScreen(tester);

    await tester.longPress(find.text('Doomed one'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // §3.1: the dialog must state the exact count before anything is written.
    expect(find.textContaining('Delete these 2 transactions?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Doomed one'), findsNothing);
    expect(find.text('Doomed two'), findsNothing);
    expect(find.text('No transactions match these filters.'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('cancelling the delete confirmation keeps every entry', (tester) async {
    await addTransaction(note: 'Entry one');
    await addTransaction(note: 'Entry two');
    await pumpHistoryScreen(tester);

    await tester.longPress(find.text('Entry one'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Entry one'), findsOneWidget);
    expect(find.text('Entry two'), findsOneWidget);
    // Selection survives a cancel, so the user can act again without reselecting.
    expect(find.text('1 selected'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('bulk delete only touches the visible selection', (tester) async {
    await addTransaction(note: 'Alpha');
    await addTransaction(note: 'Beta');
    await pumpHistoryScreen(tester);

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    // Narrow so only Alpha is visible. Beta must survive the delete even though
    // it was selected before the filter changed.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Alpha');
    await tester.pumpAndSettle();

    // Scope to the list: "Alpha" is now also the search field's contents.
    final Finder alphaRow = find.descendant(
      of: find.byType(ListTile),
      matching: find.text('Alpha'),
    );
    await tester.longPress(alphaRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(alphaRow, findsNothing);

    // Clear the search: Beta should still be there.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets(
    'reassigning selected entries to a category clears the needs-attention flag',
    (tester) async {
      await addTransaction(note: 'Flagged one');
      await addTransaction(note: 'Flagged two');
      await pumpHistoryScreen(tester);

      await tester.longPress(find.text('Flagged one'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Select all'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Reassign'));
      await tester.pumpAndSettle();

      // Bulk reassign sheet: pick a category by creating one inline.
      await tester.tap(find.text('Select a category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Groceries');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add "Groceries" as a new category'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      // Confirmation dialog's "Reassign" button, distinct from the selection
      // bar's button of the same label underneath it.
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Reassign')),
      );
      await tester.pumpAndSettle();

      // Needs-attention chip should now show nothing.
      await tester.tap(find.widgetWithText(FilterChip, 'Needs attention'));
      await tester.pumpAndSettle();
      expect(find.text('No transactions match these filters.'), findsOneWidget);

      await unmount(tester);
    },
  );
}
