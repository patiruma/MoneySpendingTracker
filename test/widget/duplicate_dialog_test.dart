import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_spending_tracker/core/csv_import.dart';
import 'package:money_spending_tracker/data/database.dart';
import 'package:money_spending_tracker/data/models/import_plan.dart';
import 'package:money_spending_tracker/features/import/duplicate_dialog.dart';

void main() {
  DuplicateCandidate candidate({String note = 'Lunch'}) {
    final int occurredAt = DateTime(2024, 3, 1, 12).toUtc().millisecondsSinceEpoch;
    return DuplicateCandidate(
      row: ImportRow(
        lineNumber: 2,
        occurredAt: occurredAt,
        amountCents: 1234,
        categoryName: 'Food',
        paymentMethodName: 'Cash',
        note: note,
      ),
      existing: Transaction(
        id: 't1',
        amountCents: 1234,
        occurredAt: occurredAt,
        categoryId: 'c1',
        paymentMethodId: 'p1',
        note: note,
        createdAt: occurredAt,
        updatedAt: occurredAt,
      ),
    );
  }

  Future<DuplicateResolution?> showAndTap(
    WidgetTester tester, {
    required int remaining,
    required String buttonText,
    bool tickApplyToRest = false,
  }) async {
    DuplicateResolution? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () async {
              result = await duplicateDialog(
                context,
                candidate: candidate(),
                remaining: remaining,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    if (tickApplyToRest) {
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text(buttonText));
    await tester.pumpAndSettle();

    return result;
  }

  testWidgets('shows the incoming row so the user knows which entry it is',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () => duplicateDialog(
              context,
              candidate: candidate(note: 'Lunch with Sam'),
              remaining: 0,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Lunch with Sam'), findsOneWidget);
    expect(find.textContaining('Food'), findsOneWidget);
    expect(find.text('Keep both'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('offers all three choices and returns the one tapped',
      (tester) async {
    for (final (String label, DuplicateChoice expected) in <(String, DuplicateChoice)>[
      ('Keep both', DuplicateChoice.keepBoth),
      ('Replace', DuplicateChoice.replace),
      ('Skip', DuplicateChoice.skip),
    ]) {
      final DuplicateResolution? result =
          await showAndTap(tester, remaining: 0, buttonText: label);
      expect(result!.choice, expected, reason: 'tapping "$label"');
      expect(result.applyToRest, isFalse);
    }
  });

  testWidgets('cancelling returns a null choice, abandoning the import',
      (tester) async {
    final DuplicateResolution? result =
        await showAndTap(tester, remaining: 3, buttonText: 'Cancel import');
    expect(result!.choice, isNull);
  });

  testWidgets('the apply-to-rest checkbox appears only when more remain',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () =>
                duplicateDialog(context, candidate: candidate(), remaining: 0),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Nothing left to apply it to, so the option would be meaningless.
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('the checkbox names how many remain, pluralized', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () =>
                duplicateDialog(context, candidate: candidate(), remaining: 1),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Do this for the remaining 1 duplicate'), findsOneWidget);
  });

  testWidgets('ticking apply-to-rest is reported back with the choice',
      (tester) async {
    final DuplicateResolution? result = await showAndTap(
      tester,
      remaining: 4,
      buttonText: 'Skip',
      tickApplyToRest: true,
    );

    expect(result!.choice, DuplicateChoice.skip);
    expect(result.applyToRest, isTrue);
  });
}
