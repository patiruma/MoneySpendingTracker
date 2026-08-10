import 'package:flutter/material.dart';

import '../../../data/models/label_node.dart';

/// A chosen reparent destination. A null [parentId] means top level.
class MoveTarget {
  const MoveTarget({required this.parentId, required this.name});

  const MoveTarget.topLevel() : parentId = null, name = 'Top level';

  final String? parentId;
  final String name;
}

/// Destination picker for a reparent. Offers "Top level" plus every label that
/// could legally receive [moving], filtered client-side so obviously-invalid
/// targets never appear:
///
/// - the node itself and its own descendants (cycle),
/// - placeholders (cannot be a parent),
/// - the node's current parent (no-op),
/// - anything too deep to hold the moving subtree.
///
/// The repository's `previewMove` re-checks all of this before the write — this
/// filtering is a courtesy, not the enforcement.
Future<MoveTarget?> showMoveTargetSheet(
  BuildContext context, {
  required List<LabelNode> roots,
  required LabelNode moving,
  required String noun,
}) {
  final Set<String> blocked = moving.selfAndDescendants.map((LabelNode n) => n.id).toSet();
  final int height = moving.subtreeHeight;

  final List<LabelNode> candidates = <LabelNode>[];
  for (final LabelNode root in roots) {
    for (final LabelNode node in root.selfAndDescendants) {
      if (blocked.contains(node.id)) continue;
      if (node.isPlaceholder) continue;
      if (node.id == moving.label.parentId) continue;
      // depth(parent) + 1 + height(moving) must stay within 3 levels.
      if (node.depth + 1 + height > 2) continue;
      candidates.add(node);
    }
  }

  final bool alreadyTopLevel = moving.label.parentId == null;

  return showModalBottomSheet<MoveTarget>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (BuildContext context, ScrollController controller) {
          if (candidates.isEmpty && alreadyTopLevel) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'There is nowhere to move "${moving.name}" to.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            controller: controller,
            itemCount: candidates.length + (alreadyTopLevel ? 1 : 2),
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Move "${moving.name}" to…',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              if (!alreadyTopLevel && index == 1) {
                return ListTile(
                  leading: const Icon(Icons.vertical_align_top),
                  title: const Text('Top level'),
                  onTap: () =>
                      Navigator.of(context).pop(const MoveTarget.topLevel()),
                );
              }
              final LabelNode node = candidates[index - (alreadyTopLevel ? 1 : 2)];
              return ListTile(
                contentPadding: EdgeInsets.only(left: 16.0 + node.depth * 20.0, right: 16),
                leading: const Icon(Icons.subdirectory_arrow_right),
                title: Text(node.name),
                onTap: () => Navigator.of(context).pop(
                  MoveTarget(parentId: node.id, name: node.name),
                ),
              );
            },
          );
        },
      );
    },
  );
}
