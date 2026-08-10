import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../data/models/transaction_with_labels.dart';

/// One row in the transaction list, reused by History and Analytics
/// (§2.8.4). Needs-attention entries (§2.6) get a visual flag — derived from
/// [TransactionWithLabels.needsAttention], never stored.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectable = false,
    this.onSelectedChanged,
  });

  final TransactionWithLabels entry;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectable;
  final ValueChanged<bool?>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final DateFormat dateFormat = DateFormat.yMMMd().add_jm();
    final bool flagged = entry.needsAttention;

    final Widget leading = selectable
        ? Checkbox(value: selected, onChanged: onSelectedChanged)
        : CircleAvatar(
            backgroundColor: flagged ? colors.errorContainer : colors.secondaryContainer,
            foregroundColor: flagged ? colors.onErrorContainer : colors.onSecondaryContainer,
            child: Icon(flagged ? Icons.priority_high : Icons.receipt_long, size: 20),
          );

    return ListTile(
      selected: selected,
      leading: leading,
      title: Text(entry.transaction.note),
      subtitle: Text(
        '${entry.categoryName} · ${entry.paymentMethodName} · '
        '${dateFormat.format(DateTime.fromMillisecondsSinceEpoch(entry.transaction.occurredAt, isUtc: true).toLocal())}',
        style: flagged ? TextStyle(color: colors.error) : null,
      ),
      trailing: Text(
        Money.format(entry.transaction.amountCents),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
