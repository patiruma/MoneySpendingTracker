import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/models/label_node.dart';
import '../../data/repositories/label_repository.dart';
import '../../data/tables.dart';
import '../providers.dart';
import 'confirm_dialog.dart';

/// Type-ahead picker for Categories and Payment Methods (§2.2, §2.4).
///
/// Selectable at **any** level — picking a parent saves under that parent, with
/// no auto-created child (§2.4). Unmatched text offers "Add 'X' as a new
/// category?", which creates a **top-level** label only: nesting happens on the
/// manage screen, and move closes the loop. That keeps the add-transaction path
/// to one field and one tap (§1).
class LabelPicker extends ConsumerStatefulWidget {
  const LabelPicker({
    super.key,
    required this.kind,
    required this.selectedId,
    required this.onChanged,
    this.labelText,
  });

  final LabelKind kind;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final String? labelText;

  @override
  ConsumerState<LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends ConsumerState<LabelPicker> {
  String get _kindNoun => widget.kind == LabelKind.category ? 'category' : 'payment method';

  Future<void> _openSheet() async {
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LabelPickerSheet(kind: widget.kind, selectedId: widget.selectedId),
    );
    if (picked != null) {
      widget.onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<LabelNode>> tree = ref.watch(labelTreeProvider(widget.kind));
    final String display = tree.maybeWhen(
      data: (List<LabelNode> nodes) => _nameFor(nodes, widget.selectedId) ?? 'Select a $_kindNoun',
      orElse: () => 'Select a $_kindNoun',
    );
    final bool hasSelection = widget.selectedId != null;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.labelText ?? (widget.kind == LabelKind.category ? 'Category' : 'Payment method'),
        border: const OutlineInputBorder(),
      ),
      child: InkWell(
        onTap: _openSheet,
        child: Row(
          children: [
            Expanded(
              child: Text(
                display,
                style: hasSelection
                    ? null
                    : TextStyle(color: Theme.of(context).hintColor),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

String? _nameFor(List<LabelNode> nodes, String? id) {
  if (id == null) return null;
  for (final LabelNode root in nodes) {
    for (final LabelNode node in root.selfAndDescendants) {
      if (node.id == id) return node.name;
    }
  }
  return null;
}

class _LabelPickerSheet extends ConsumerStatefulWidget {
  const _LabelPickerSheet({required this.kind, required this.selectedId});

  final LabelKind kind;
  final String? selectedId;

  @override
  ConsumerState<_LabelPickerSheet> createState() => _LabelPickerSheetState();
}

class _LabelPickerSheetState extends ConsumerState<_LabelPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  String get _kindNoun => widget.kind == LabelKind.category ? 'category' : 'payment method';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Flattens the tree to a list, keeping indent depth, filtered by [_query].
  /// A node is kept when it matches, or when any descendant matches — so a
  /// child hit never appears without its parent context.
  List<LabelNode> _visible(List<LabelNode> roots) {
    final String q = _query.trim().toLowerCase();
    final List<LabelNode> out = <LabelNode>[];

    bool walk(LabelNode node) {
      final bool selfMatches = q.isEmpty || node.name.toLowerCase().contains(q);
      final int mark = out.length;
      out.add(node);
      bool anyChildMatches = false;
      for (final LabelNode child in node.children) {
        anyChildMatches = walk(child) || anyChildMatches;
      }
      if (!selfMatches && !anyChildMatches) {
        out.removeRange(mark, out.length);
        return false;
      }
      return true;
    }

    for (final LabelNode root in roots) {
      walk(root);
    }
    return out;
  }

  Future<void> _createFromQuery(String name) async {
    final LabelRepository repo = ref.read(labelRepositoryProvider);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // §2.4: creating a new value is confirmed before it joins the reusable list.
    final bool confirmed = await confirmDialog(
      context,
      title: 'Add $_kindNoun',
      message: 'Add "$name" as a new $_kindNoun?',
      confirmLabel: 'Add',
    );
    if (!confirmed) return;

    try {
      final Label created = await repo.create(kind: widget.kind, name: name);
      navigator.pop(created.id);
    } on LabelException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<LabelNode>> tree = ref.watch(labelTreeProvider(widget.kind));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Search or add a $_kindNoun',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (String value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: tree.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Center(child: Text('Could not load: $e')),
                data: (List<LabelNode> roots) {
                  final List<LabelNode> visible = _visible(roots);
                  final String trimmed = _query.trim();
                  final bool exactExists = visible.any(
                    (LabelNode n) => n.name.toLowerCase() == trimmed.toLowerCase(),
                  );
                  final bool offerCreate = trimmed.isNotEmpty && !exactExists;

                  if (visible.isEmpty && !offerCreate) {
                    return const Center(child: Text('No matches'));
                  }

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: visible.length + (offerCreate ? 1 : 0),
                    itemBuilder: (BuildContext context, int index) {
                      if (offerCreate && index == visible.length) {
                        return ListTile(
                          leading: const Icon(Icons.add),
                          title: Text('Add "$trimmed" as a new $_kindNoun'),
                          onTap: () => _createFromQuery(trimmed),
                        );
                      }
                      final LabelNode node = visible[index];
                      return ListTile(
                        // Any level is selectable (§2.4).
                        contentPadding: EdgeInsets.only(
                          left: 16.0 + node.depth * 20.0,
                          right: 16,
                        ),
                        title: Text(node.name),
                        selected: node.id == widget.selectedId,
                        trailing: node.id == widget.selectedId
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.of(context).pop(node.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
