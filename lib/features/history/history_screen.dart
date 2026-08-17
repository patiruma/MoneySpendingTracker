import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../data/models/transaction_filter.dart';
import '../../data/models/transaction_with_labels.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/transaction_list.dart';
import 'widgets/bulk_reassign_sheet.dart';
import 'widgets/history_filter_bar.dart';

/// Transaction history (§2.5–2.7): filterable, newest-first list. Needs-
/// attention entries are flagged in place — no dedicated view beyond the "No
/// Category" filter shortcut here (§2.6). Long-pressing a row enters bulk
/// selection mode in place (§2.5) — there is no separate selection screen.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  Future<void> _reassign(
    BuildContext context,
    WidgetRef ref,
    Set<String> selectedIds,
  ) async {
    final BulkReassignChoice? choice = await showBulkReassignSheet(context);
    if (choice == null || choice.isEmpty) return;
    if (!context.mounted) return;

    final bool confirmed = await confirmDialog(
      context,
      title: 'Reassign entries',
      message: 'Reassign ${selectedIds.length} transactions to the selected value(s)?',
      confirmLabel: 'Reassign',
    );
    if (!confirmed) return;

    await ref
        .read(transactionRepositoryProvider)
        .bulkReassign(
          ids: selectedIds,
          categoryId: choice.categoryId,
          paymentMethodId: choice.paymentMethodId,
        );
    ref.read(historySelectionProvider.notifier).state = <String>{};
  }

  /// Bulk delete, behind the same §3.1 confirmation a single delete uses — the
  /// dialog states the exact count, since this is the one action here the user
  /// cannot undo.
  Future<void> _deleteSelected(
    BuildContext context,
    WidgetRef ref,
    Set<String> selectedIds,
  ) async {
    final int count = selectedIds.length;
    final bool confirmed = await confirmDialog(
      context,
      title: count == 1 ? 'Delete transaction' : 'Delete transactions',
      message: count == 1
          ? 'Delete this transaction? This cannot be undone.'
          : 'Delete these $count transactions? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    await ref.read(transactionRepositoryProvider).bulkDelete(selectedIds);
    ref.read(historySelectionProvider.notifier).state = <String>{};
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TransactionFilter filter = ref.watch(historyFilterProvider);
    final AsyncValue<List<TransactionWithLabels>> transactions = ref.watch(
      historyTransactionsProvider,
    );
    // Scoped to the visible list: narrowing the filter must not leave entries
    // selected that the user can no longer see, since Reassign writes to
    // exactly this set.
    final Set<String> selectedIds = ref.watch(historyVisibleSelectionProvider);
    final bool selectionMode = selectedIds.isNotEmpty;
    final bool needsAttentionOnly = filter.categoryId == kNoCategoryId;

    return Column(
      children: [
        if (selectionMode)
          _SelectionBar(
            selectedCount: selectedIds.length,
            onSelectAll: () {
              final List<TransactionWithLabels> entries = transactions.value ?? const [];
              ref.read(historySelectionProvider.notifier).state = entries
                  .map((TransactionWithLabels e) => e.transaction.id)
                  .toSet();
            },
            onClear: () => ref.read(historySelectionProvider.notifier).state = <String>{},
            onReassign: () => _reassign(context, ref, selectedIds),
            onDelete: () => _deleteSelected(context, ref, selectedIds),
          )
        else ...[
          HistoryFilterBar(
            filter: filter,
            onChanged: (TransactionFilter next) =>
                ref.read(historyFilterProvider.notifier).state = next,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Needs attention'),
                avatar: const Icon(Icons.priority_high, size: 18),
                selected: needsAttentionOnly,
                onSelected: (bool selected) {
                  ref.read(historyFilterProvider.notifier).state = filter.copyWith(
                    categoryId: () => selected ? kNoCategoryId : null,
                  );
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: transactions.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object e, _) => Center(child: Text('Could not load: $e')),
            data: (List<TransactionWithLabels> entries) => TransactionList(
              entries: entries,
              selectable: selectionMode,
              selectedIds: selectedIds,
              onSelectedChanged: (String id, bool? selected) {
                final Set<String> next = {...selectedIds};
                if (selected ?? false) {
                  next.add(id);
                } else {
                  next.remove(id);
                }
                ref.read(historySelectionProvider.notifier).state = next;
              },
              onTap: (TransactionWithLabels entry) {
                if (selectionMode) {
                  final Set<String> next = {...selectedIds};
                  final String id = entry.transaction.id;
                  if (next.contains(id)) {
                    next.remove(id);
                  } else {
                    next.add(id);
                  }
                  ref.read(historySelectionProvider.notifier).state = next;
                } else {
                  context.push('/entry/edit', extra: entry.transaction);
                }
              },
              onLongPress: (TransactionWithLabels entry) {
                if (!selectionMode) {
                  ref.read(historySelectionProvider.notifier).state = {entry.transaction.id};
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Replaces the filter bar while a bulk selection is active — select-all
/// (scoped to whatever's currently filtered in, per §2.5), clear, reassign,
/// and delete.
///
/// Delete is an icon in the error color rather than a second filled button:
/// Reassign stays the primary action, and the destructive one should not read
/// as an equal-weight peer sitting right beside it.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.onSelectAll,
    required this.onClear,
    required this.onReassign,
    required this.onDelete,
  });

  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onReassign;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Clear selection',
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
            Expanded(
              child: Text(
                '$selectedCount selected',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(onPressed: onSelectAll, child: const Text('Select all')),
            IconButton(
              tooltip: selectedCount == 1
                  ? 'Delete 1 entry'
                  : 'Delete $selectedCount entries',
              icon: const Icon(Icons.delete_outline),
              color: Theme.of(context).colorScheme.error,
              onPressed: onDelete,
            ),
            FilledButton(onPressed: onReassign, child: const Text('Reassign')),
          ],
        ),
      ),
    );
  }
}
