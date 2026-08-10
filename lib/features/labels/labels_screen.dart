import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/impacts.dart';
import '../../data/models/label_node.dart';
import '../../data/repositories/label_repository.dart';
import '../../data/tables.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'widgets/move_target_sheet.dart';

/// Manage Categories / Manage Payment Methods (§2.4). One screen, parameterized
/// by [LabelKind] — the two lists have identical rules.
///
/// Every structural action here goes through §3.1: a `preview*` call supplies
/// impact counts, [confirmDialog] states them, and only then does the mutation run.
class LabelsScreen extends ConsumerWidget {
  const LabelsScreen({super.key, required this.kind});

  final LabelKind kind;

  String get _title => kind == LabelKind.category ? 'Manage Categories' : 'Manage Payment Methods';

  String get _noun => kind == LabelKind.category ? 'category' : 'payment method';

  String get _pluralNoun => kind == LabelKind.category ? 'sub-categories' : 'sub-payment-methods';

  String get _placeholderName =>
      kind == LabelKind.category ? 'No Category' : 'No Payment Method';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LabelNode>> tree = ref.watch(labelTreeProvider(kind));

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref, parent: null),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: tree.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => Center(child: Text('Could not load: $e')),
        data: (List<LabelNode> roots) {
          if (roots.isEmpty) {
            return Center(child: Text('No ${_noun}s yet.'));
          }
          final List<LabelNode> flat =
              roots.expand((LabelNode r) => r.selfAndDescendants).toList(growable: false);
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: flat.length,
            itemBuilder: (BuildContext context, int index) {
              final LabelNode node = flat[index];
              return _LabelTile(
                node: node,
                noun: _noun,
                onAction: (_NodeAction action) => _handle(context, ref, node, action),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    LabelNode node,
    _NodeAction action,
  ) {
    switch (action) {
      case _NodeAction.addChild:
        return _create(context, ref, parent: node);
      case _NodeAction.rename:
        return _rename(context, ref, node);
      case _NodeAction.move:
        return _move(context, ref, node);
      case _NodeAction.delete:
        return _delete(context, ref, node);
    }
  }

  // -------------------------------------------------------------- create

  Future<void> _create(BuildContext context, WidgetRef ref, {LabelNode? parent}) async {
    if (parent != null && parent.depth >= 2) {
      await blockedDialog(
        context,
        title: 'Cannot nest deeper',
        message: 'Nesting is limited to 3 levels.',
      );
      return;
    }

    final String? name = await promptForName(
      context,
      title: parent == null ? 'Add $_noun' : 'Add under "${parent.name}"',
    );
    if (name == null || !context.mounted) return;

    final bool confirmed = await confirmDialog(
      context,
      title: 'Add $_noun',
      message: parent == null
          ? 'Add "$name" as a new $_noun?'
          : 'Add "$name" under "${parent.name}"?',
      confirmLabel: 'Add',
    );
    if (!confirmed || !context.mounted) return;

    await _run(context, ref, (LabelRepository repo) async {
      await repo.create(kind: kind, name: name, parentId: parent?.id);
    });
  }

  // -------------------------------------------------------------- rename

  Future<void> _rename(BuildContext context, WidgetRef ref, LabelNode node) async {
    if (node.isPlaceholder) {
      await blockedDialog(
        context,
        title: 'Cannot rename',
        message: '"$_placeholderName" is built in and cannot be renamed.',
      );
      return;
    }

    final String? newName = await promptForName(
      context,
      title: 'Rename $_noun',
      initialValue: node.name,
    );
    if (newName == null || newName == node.name || !context.mounted) return;

    final RenameImpact impact = await ref.read(labelRepositoryProvider).previewRename(node.id);
    if (!context.mounted) return;

    final bool confirmed = await confirmDialog(
      context,
      title: 'Rename $_noun',
      message: 'Rename "${node.name}" to "$newName"? '
          'This updates the name on ${_entries(impact.affectedTransactionCount)}.',
      confirmLabel: 'Rename',
    );
    if (!confirmed || !context.mounted) return;

    await _run(context, ref, (LabelRepository repo) => repo.rename(node.id, newName));
  }

  // ---------------------------------------------------------------- move

  Future<void> _move(BuildContext context, WidgetRef ref, LabelNode node) async {
    if (node.isPlaceholder) {
      await blockedDialog(
        context,
        title: 'Cannot move',
        message: '"$_placeholderName" is built in and cannot be moved.',
      );
      return;
    }

    final List<LabelNode> roots = await ref.read(labelRepositoryProvider).getTree(kind);
    if (!context.mounted) return;

    final MoveTarget? target = await showMoveTargetSheet(
      context,
      roots: roots,
      moving: node,
      noun: _noun,
    );
    if (target == null || !context.mounted) return;

    final MoveImpact impact =
        await ref.read(labelRepositoryProvider).previewMove(node.id, target.parentId);
    if (!context.mounted) return;

    if (!impact.valid) {
      await blockedDialog(
        context,
        title: 'Cannot move',
        message: impact.reason ?? 'That move is not allowed.',
      );
      return;
    }

    final String destination = target.parentId == null
        ? 'Top level'
        : '"${target.name}"';
    final String subtreeClause = impact.subtreeCount == 0
        ? ''
        : ' and its ${impact.subtreeCount} $_pluralNoun';

    final bool confirmed = await confirmDialog(
      context,
      title: 'Move $_noun',
      message: 'Move "${node.name}"$subtreeClause under $destination? '
          'Past entries are unchanged, but analytics rollups will shift.',
      confirmLabel: 'Move',
    );
    if (!confirmed || !context.mounted) return;

    await _run(context, ref, (LabelRepository repo) => repo.move(node.id, target.parentId));
  }

  // -------------------------------------------------------------- delete

  Future<void> _delete(BuildContext context, WidgetRef ref, LabelNode node) async {
    if (node.isPlaceholder) {
      await blockedDialog(
        context,
        title: 'Cannot delete',
        message: '"$_placeholderName" is built in and cannot be deleted.',
      );
      return;
    }

    final DeleteImpact impact = await ref.read(labelRepositoryProvider).previewDelete(node.id);
    if (!context.mounted) return;

    final String fallback = _placeholderName;
    final String message = impact.descendantCount == 0
        ? 'Delete "${node.name}"? '
              '${_entriesCapitalized(impact.affectedTransactionCount)} will move to $fallback.'
        : 'Delete "${node.name}" and its ${impact.descendantCount} $_pluralNoun? '
              '${_entriesCapitalized(impact.affectedTransactionCount)} will move to $fallback.';

    final bool confirmed = await confirmDialog(
      context,
      title: 'Delete $_noun',
      message: message,
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    await _run(context, ref, (LabelRepository repo) => repo.deleteCascade(node.id));
  }

  // ------------------------------------------------------------- helpers

  /// Runs a mutation, surfacing a [LabelException] as a snackbar rather than an
  /// unhandled error. The tree refreshes itself via `watch()` — no invalidation.
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(LabelRepository repo) action,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(labelRepositoryProvider));
    } on LabelException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static String _entries(int n) => n == 1 ? '1 past entry' : '$n past entries';

  static String _entriesCapitalized(int n) => n == 1 ? '1 entry' : '$n entries';
}

enum _NodeAction { addChild, rename, move, delete }

class _LabelTile extends StatelessWidget {
  const _LabelTile({required this.node, required this.noun, required this.onAction});

  final LabelNode node;
  final String noun;
  final ValueChanged<_NodeAction> onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canNest = node.depth < 2;

    return ListTile(
      contentPadding: EdgeInsets.only(left: 16.0 + node.depth * 24.0, right: 8),
      leading: Icon(
        node.isPlaceholder
            ? Icons.help_outline
            : (node.children.isEmpty ? Icons.label_outline : Icons.folder_outlined),
        color: node.isPlaceholder ? theme.colorScheme.outline : null,
      ),
      title: Text(
        node.name,
        style: node.isPlaceholder
            ? TextStyle(fontStyle: FontStyle.italic, color: theme.colorScheme.outline)
            : null,
      ),
      subtitle: node.children.isEmpty
          ? null
          : Text('${node.descendantCount} nested'),
      // Placeholders expose no actions at all — they cannot be renamed, moved,
      // deleted, or given children.
      trailing: node.isPlaceholder
          ? null
          : PopupMenuButton<_NodeAction>(
              onSelected: onAction,
              itemBuilder: (BuildContext context) => <PopupMenuEntry<_NodeAction>>[
                if (canNest)
                  PopupMenuItem<_NodeAction>(
                    value: _NodeAction.addChild,
                    child: Text('Add sub-$noun'),
                  ),
                const PopupMenuItem<_NodeAction>(
                  value: _NodeAction.rename,
                  child: Text('Rename'),
                ),
                const PopupMenuItem<_NodeAction>(
                  value: _NodeAction.move,
                  child: Text('Move'),
                ),
                const PopupMenuItem<_NodeAction>(
                  value: _NodeAction.delete,
                  child: Text('Delete'),
                ),
              ],
            ),
    );
  }
}
