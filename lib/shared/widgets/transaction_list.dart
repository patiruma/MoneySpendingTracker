import 'package:flutter/material.dart';

import '../../data/models/transaction_with_labels.dart';
import 'transaction_tile.dart';

/// The §2.8.4 reuse point: History and Analytics both render this for their
/// filtered transaction set rather than duplicating the list. Renders a true
/// empty state — a filtered view with no matches never falls back to
/// unfiltered data (§5).
class TransactionList extends StatelessWidget {
  const TransactionList({
    super.key,
    required this.entries,
    this.onTap,
    this.onLongPress,
    this.selectable = false,
    this.selectedIds = const <String>{},
    this.onSelectedChanged,
    this.shrinkWrap = false,
    this.physics,
    this.maxItems,
    this.overflowFooterBuilder,
  });

  final List<TransactionWithLabels> entries;
  final ValueChanged<TransactionWithLabels>? onTap;
  final ValueChanged<TransactionWithLabels>? onLongPress;
  final bool selectable;
  final Set<String> selectedIds;
  final void Function(String id, bool? selected)? onSelectedChanged;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  /// Caps how many rows are built. Only meaningful when [shrinkWrap] is true:
  /// a shrink-wrapped list inside an outer scroll view can't virtualize, so
  /// every row is built whether or not it's on screen. History leaves this null
  /// — it scrolls normally and virtualizes, so capping it would just hide data.
  final int? maxItems;

  /// Rendered below the rows when [maxItems] actually truncated the list, with
  /// (shown, total). Lets the caller explain where the rest of the entries are
  /// rather than silently dropping them.
  final Widget Function(int shown, int total)? overflowFooterBuilder;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyState();
    }

    final int cap = maxItems ?? entries.length;
    final int shown = cap < entries.length ? cap : entries.length;
    final bool truncated = shown < entries.length;
    final Widget? footer = truncated
        ? overflowFooterBuilder?.call(shown, entries.length)
        : null;

    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: shown + (footer != null ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        if (index == shown && footer != null) {
          return footer;
        }
        final TransactionWithLabels entry = entries[index];
        return TransactionTile(
          entry: entry,
          selectable: selectable,
          selected: selectedIds.contains(entry.transaction.id),
          onSelectedChanged: onSelectedChanged == null
              ? null
              : (bool? value) => onSelectedChanged!(entry.transaction.id, value),
          onTap: onTap == null ? null : () => onTap!(entry),
          onLongPress: onLongPress == null ? null : () => onLongPress!(entry),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // Scrollable rather than a bare Center: on a very short viewport (e.g. the
    // History tab with several filter rows already expanded above it) a fixed
    // Column can be taller than the remaining space, which would overflow.
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(
              'No transactions match these filters.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
