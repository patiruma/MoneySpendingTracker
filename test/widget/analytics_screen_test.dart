import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/core/ids.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/tables.dart';
import 'package:money_spending_tracker/features/analytics/analytics_screen.dart';
import 'package:money_spending_tracker/features/analytics/widgets/category_bar_chart.dart';
import 'package:money_spending_tracker/features/analytics/widgets/spending_line_chart.dart';
import 'package:money_spending_tracker/shared/providers.dart';
import 'package:money_spending_tracker/shared/widgets/label_picker.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> addLabel(String name) async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final String id = newId();
    await db
        .into(db.labels)
        .insert(
          LabelsCompanion.insert(
            id: id,
            kind: LabelKind.category,
            name: name,
            depth: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> addTransaction({
    String? categoryId,
    int amountCents = 1000,
    String note = 'entry',
    DateTime? occurredAt,
  }) async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.transactions)
        .insert(
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

  Future<void> pumpAnalytics(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: AnalyticsScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  /// The headline total, addressed specifically. The same formatted amount can
  /// legitimately appear again as a bar's direct value label, so matching on
  /// the text alone would be ambiguous.
  Finder headlineTotal(String formatted) => find.descendant(
    of: find.byType(AnalyticsScreen),
    matching: find.byWidgetPredicate(
      (Widget w) =>
          w is Text && w.data == formatted && (w.style?.fontSize ?? 0) > 24,
    ),
  );

  /// The screen scrolls; the list and its section title sit below the charts,
  /// off-screen in the default test viewport and lazily built. Scroll before
  /// asserting on anything down there.
  Future<void> scrollToBottom(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('Transactions'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the total for the scope and range', (tester) async {
    await addTransaction(amountCents: 1250, note: 'Lunch');
    await addTransaction(amountCents: 750, note: 'Coffee');

    await pumpAnalytics(tester);

    expect(find.text('Total spending'), findsOneWidget);
    expect(headlineTotal(r'$20.00'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('renders the line chart and, for Combined scope, the category bars', (
    tester,
  ) async {
    final String food = await addLabel('Food');
    await addTransaction(categoryId: food, amountCents: 3000);

    await pumpAnalytics(tester);

    expect(find.byType(SpendingLineChart), findsOneWidget);
    expect(find.text('By category'), findsOneWidget);
    expect(find.byType(CategoryBarChart), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('hides the by-category breakdown for a single-category scope', (tester) async {
    final String food = await addLabel('Food');
    await addTransaction(categoryId: food, amountCents: 3000);
    await pumpAnalytics(tester);

    expect(find.text('By category'), findsOneWidget);

    // Narrow the scope to a single category via the picker. The tap must be
    // scoped to the modal sheet's row — "Food" also appears behind it as a
    // category-bar label, and that one isn't tappable.
    // The picker's tap target is the InkWell inside the field, not the
    // floating InputDecorator label.
    await tester.tap(
      find.descendant(of: find.byType(LabelPicker), matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(ListTile), matching: find.text('Food')),
    );
    await tester.pumpAndSettle();

    expect(find.text('By category'), findsNothing);
    expect(find.byType(CategoryBarChart), findsNothing);
    // The line chart and total stay.
    expect(find.byType(SpendingLineChart), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the bucket toggle re-buckets without changing the total', (tester) async {
    await addTransaction(amountCents: 1000, occurredAt: DateTime.now());
    await addTransaction(
      amountCents: 2000,
      occurredAt: DateTime.now().subtract(const Duration(days: 3)),
    );

    await pumpAnalytics(tester);
    expect(headlineTotal(r'$30.00'), findsOneWidget);

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    // Same filter, different granularity: the headline is unchanged.
    expect(headlineTotal(r'$30.00'), findsOneWidget);

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(headlineTotal(r'$30.00'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('reuses the transaction list beneath the charts', (tester) async {
    await addTransaction(note: 'Lunch with Sam');
    await pumpAnalytics(tester);
    await scrollToBottom(tester);

    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Lunch with Sam'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('caps the transaction list and says so, without capping the total', (
    tester,
  ) async {
    // Analytics nests the list in an outer ListView, so it can't virtualize and
    // builds every row it's given. Past the cap it shows a subset plus a footer
    // — but the headline must still sum every matching entry.
    for (int i = 0; i < 60; i++) {
      await addTransaction(amountCents: 100, note: 'Entry $i');
    }

    await pumpAnalytics(tester);

    // 60 x $1.00 — the total covers all of them, not just the 50 rendered.
    expect(headlineTotal(r'$60.00'), findsOneWidget);

    await scrollToBottom(tester);
    await tester.dragUntilVisible(
      find.textContaining('Showing the 50 most recent'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );

    expect(find.textContaining('of 60 matching entries'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('shows no overflow footer when the list fits under the cap', (tester) async {
    await addTransaction(note: 'Only one');
    await pumpAnalytics(tester);
    await scrollToBottom(tester);

    expect(find.textContaining('Showing the'), findsNothing);
    expect(find.text('Only one'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('an empty range shows a zero total and the list empty state', (tester) async {
    await addTransaction(
      note: 'Long ago',
      occurredAt: DateTime.now().subtract(const Duration(days: 400)),
    );

    await pumpAnalytics(tester);

    expect(headlineTotal(r'$0.00'), findsOneWidget);

    await scrollToBottom(tester);
    expect(find.text('No transactions match these filters.'), findsOneWidget);
    expect(find.text('Long ago'), findsNothing);

    await unmount(tester);
  });
}
