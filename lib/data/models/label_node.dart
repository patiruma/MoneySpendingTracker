import '../database.dart';

/// A label plus its children, forming the tree the manage screen renders.
///
/// Built once from a flat `List<Label>` — see [buildLabelTree] — so the DB is
/// queried once per tree rather than once per level.
class LabelNode {
  const LabelNode({required this.label, required this.children});

  final Label label;
  final List<LabelNode> children;

  String get id => label.id;
  String get name => label.name;
  int get depth => label.depth;
  bool get isPlaceholder => label.isPlaceholder;

  /// Number of descendants below this node (excludes the node itself).
  int get descendantCount =>
      children.fold(0, (int sum, LabelNode c) => sum + 1 + c.descendantCount);

  /// Max depth below this node, relative to it. A leaf is 0.
  int get subtreeHeight => children.isEmpty
      ? 0
      : 1 + children.map((LabelNode c) => c.subtreeHeight).reduce((int a, int b) => a > b ? a : b);

  /// This node and all its descendants, depth-first.
  Iterable<LabelNode> get selfAndDescendants sync* {
    yield this;
    for (final LabelNode child in children) {
      yield* child.selfAndDescendants;
    }
  }
}

/// Assembles a flat list of live labels into a forest, ordered alphabetically
/// within each sibling group (plan §5.4: `sort_order` exists but isn't surfaced
/// in v1, so name is the ordering).
///
/// Placeholders sort last at the top level so "No Category" doesn't sit above
/// the user's real categories.
List<LabelNode> buildLabelTree(List<Label> labels) {
  final Map<String?, List<Label>> byParent = <String?, List<Label>>{};
  for (final Label label in labels) {
    byParent.putIfAbsent(label.parentId, () => <Label>[]).add(label);
  }

  List<LabelNode> childrenOf(String? parentId) {
    final List<Label> group = byParent[parentId] ?? const <Label>[];
    final List<Label> sorted = List<Label>.of(group)..sort(_compareSiblings);
    return sorted
        .map((Label l) => LabelNode(label: l, children: childrenOf(l.id)))
        .toList(growable: false);
  }

  return childrenOf(null);
}

int _compareSiblings(Label a, Label b) {
  if (a.isPlaceholder != b.isPlaceholder) {
    return a.isPlaceholder ? 1 : -1;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
