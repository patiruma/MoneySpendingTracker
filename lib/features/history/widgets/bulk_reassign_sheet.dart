import 'package:flutter/material.dart';

import '../../../data/tables.dart';
import '../../../shared/widgets/label_picker.dart';

/// The picker sheet for §2.5 bulk recategorize: choose a new category and/or
/// payment method to apply to every selected entry. Either field may be left
/// unset — [BulkReassignChoice] only carries the ones the user actually set.
class BulkReassignChoice {
  const BulkReassignChoice({this.categoryId, this.paymentMethodId});

  final String? categoryId;
  final String? paymentMethodId;

  bool get isEmpty => categoryId == null && paymentMethodId == null;
}

Future<BulkReassignChoice?> showBulkReassignSheet(BuildContext context) {
  return showModalBottomSheet<BulkReassignChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _BulkReassignSheet(),
  );
}

class _BulkReassignSheet extends StatefulWidget {
  const _BulkReassignSheet();

  @override
  State<_BulkReassignSheet> createState() => _BulkReassignSheetState();
}

class _BulkReassignSheetState extends State<_BulkReassignSheet> {
  String? _categoryId;
  String? _paymentMethodId;

  @override
  Widget build(BuildContext context) {
    final bool canApply = _categoryId != null || _paymentMethodId != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reassign selected entries', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Set a new category and/or payment method. Anything left unset stays as-is.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          LabelPicker(
            kind: LabelKind.category,
            selectedId: _categoryId,
            labelText: 'Category (leave unset to keep)',
            onChanged: (String? id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: 12),
          LabelPicker(
            kind: LabelKind.paymentMethod,
            selectedId: _paymentMethodId,
            labelText: 'Payment method (leave unset to keep)',
            onChanged: (String? id) => setState(() => _paymentMethodId = id),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: canApply
                ? () => Navigator.of(context).pop(
                    BulkReassignChoice(categoryId: _categoryId, paymentMethodId: _paymentMethodId),
                  )
                : null,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}
