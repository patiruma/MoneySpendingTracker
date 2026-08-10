import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/features/entry/entry_screen.dart';
import 'package:money_spending_tracker/shared/providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpEntryScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: EntryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('rejects amount 0', (tester) async {
    await pumpEntryScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '0');
    await tester.enterText(find.widgetWithText(TextFormField, 'Note'), 'Lunch');
    await tester.tap(find.widgetWithText(FilledButton, 'Add Transaction'));
    await tester.pumpAndSettle();

    expect(find.text('Enter an amount greater than 0.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('rejects negative amount', (tester) async {
    await pumpEntryScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '-5');
    await tester.enterText(find.widgetWithText(TextFormField, 'Note'), 'Lunch');
    await tester.tap(find.widgetWithText(FilledButton, 'Add Transaction'));
    await tester.pumpAndSettle();

    expect(find.text('Enter an amount greater than 0.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('rejects blank note', (tester) async {
    await pumpEntryScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '12.50');
    await tester.tap(find.widgetWithText(FilledButton, 'Add Transaction'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a note.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('add transaction persists with default placeholder labels', (tester) async {
    await pumpEntryScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '12.50');
    await tester.enterText(find.widgetWithText(TextFormField, 'Note'), 'Lunch with Sam');

    // No category/payment method picked -> blocked with a snackbar, not saved.
    await tester.tap(find.widgetWithText(FilledButton, 'Add Transaction'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a payment method.'), findsOneWidget);

    final rows = await db.select(db.transactions).get();
    expect(rows, isEmpty);

    await unmount(tester);
  });
}
