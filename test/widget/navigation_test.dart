import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/app.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/shared/providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('all nav destinations are reachable', (tester) async {
    // The manage screens read real DB state, so the widget tree needs an
    // in-memory database rather than the on-device file.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    // Add Transaction is the default tab on launch (§1 fast path).
    expect(find.text('Add Transaction'), findsWidgets);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsWidgets);

    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('Analytics'), findsWidgets);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add Transaction'), findsWidgets);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Categories'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Categories'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Payment Methods'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Payment Methods'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Export has no dedicated route (§2.9) — it's an app-bar action on
    // whichever view invoked it, reading that view's own filter.
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.ios_share), findsOneWidget);

    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.ios_share), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.ios_share), findsNothing);

    // Tear the tree down inside the test body so drift's stream-query cleanup
    // timer drains here. Left to teardown, it trips the pending-timer check.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
