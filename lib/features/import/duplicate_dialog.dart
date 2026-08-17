import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../data/models/import_plan.dart';

/// The user's answer to one duplicate prompt, plus whether it should stand in
/// for every remaining duplicate in this file.
class DuplicateResolution {
  const DuplicateResolution({required this.choice, required this.applyToRest});

  /// Null means the user cancelled the whole import.
  final DuplicateChoice? choice;
  final bool applyToRest;
}

/// A file-copy-style conflict prompt: this row already exists, keep both /
/// replace / skip, with an "apply to the remaining N" checkbox.
///
/// Shows the incoming row's fields rather than just a count, because "exact
/// duplicate" here means *every* field matched — the user's real question is
/// which transaction it is, not how many there are.
Future<DuplicateResolution> duplicateDialog(
  BuildContext context, {
  required DuplicateCandidate candidate,
  required int remaining,
}) async {
  bool applyToRest = false;

  final DuplicateChoice? choice = await showDialog<DuplicateChoice>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          final DateTime when = DateTime.fromMillisecondsSinceEpoch(
            candidate.row.occurredAt,
            isUtc: true,
          ).toLocal();

          return AlertDialog(
            title: const Text('This entry already exists'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DateFormat.yMMMd().add_jm().format(when)}\n'
                  '${Money.format(candidate.row.amountCents)} · '
                  '${candidate.row.note}',
                ),
                const SizedBox(height: 8),
                Text(
                  '${candidate.row.categoryName} · '
                  '${candidate.row.paymentMethodName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Every field matches an entry you already have. '
                  'What should happen to it?',
                ),
                if (remaining > 0) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: applyToRest,
                    onChanged: (bool? value) =>
                        setState(() => applyToRest = value ?? false),
                    title: Text(
                      'Do this for the remaining $remaining '
                      '${remaining == 1 ? 'duplicate' : 'duplicates'}',
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel import'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(DuplicateChoice.skip),
                child: const Text('Skip'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(DuplicateChoice.replace),
                child: const Text('Replace'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(DuplicateChoice.keepBoth),
                child: const Text('Keep both'),
              ),
            ],
          );
        },
      );
    },
  );

  return DuplicateResolution(choice: choice, applyToRest: applyToRest);
}
