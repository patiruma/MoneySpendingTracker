import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/app.dart';
import 'package:money_spending_tracker/core/ids.dart';
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

  Future<void> addTransaction({String note = 'entry'}) async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        id: newId(),
        amountCents: 1000,
        occurredAt: now,
        categoryId: '00000000-0000-7000-8000-000000000001',
        paymentMethodId: '00000000-0000-7000-8000-000000000002',
        note: note,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  testWidgets(
    'tapping export on History does not crash the app',
    (tester) async {
      await addTransaction(note: 'Lunch');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      // On the desktop test host this exercises the file_selector save-dialog
      // path, which resolves to no location without a real platform channel —
      // the important thing is that the app survives the round trip.
      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
