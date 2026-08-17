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

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Import CSV is offered in the overflow menu on every tab',
      (tester) async {
    // Import takes no filter, so unlike the export button it is not scoped to
    // History and Analytics — it must be reachable from the default Add tab.
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Import CSV'), findsOneWidget);
    expect(find.text('Manage Categories'), findsOneWidget);

    // Unmount inside the body: drift schedules a zero-duration cleanup timer on
    // provider dispose, and disposing during teardown trips the pending-timer
    // invariant with a stack trace pointing into riverpod rather than here.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('tapping Import does not crash the app', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // On the test host `file_selector` resolves to no file without a real
    // platform channel, which is the same path as the user cancelling the
    // picker — the import should end quietly rather than throw.
    await tester.tap(find.text('Import CSV'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
