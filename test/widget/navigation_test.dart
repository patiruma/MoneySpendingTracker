import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/app.dart';

void main() {
  testWidgets('all nav destinations are reachable', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsWidgets);

    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('Analytics'), findsWidgets);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Add Transaction'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

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

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Export'), findsWidgets);
  });
}
