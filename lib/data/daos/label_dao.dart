import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/ids.dart';
import '../database.dart';
import '../tables.dart';

part 'label_dao.g.dart';

/// Raised when a mutation would violate a §2.4 rule. Carries a user-facing
/// message — the UI surfaces [message] directly.
class LabelException implements Exception {
  const LabelException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The placeholder id for a given kind. Placeholders are ordinary rows, so
/// reassignment on delete is just an UPDATE to this id.
String placeholderIdFor(LabelKind kind) =>
    kind == LabelKind.category ? kNoCategoryId : kNoPaymentMethodId;

@DriftAccessor(tables: [Labels, Transactions])
class LabelDao extends DatabaseAccessor<AppDatabase> with _$LabelDaoMixin {
  LabelDao(super.db);

  int get _now => DateTime.now().toUtc().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- reads

  /// All live labels of one kind, flat. The tree is assembled in Dart by
  /// [buildLabelTree]; only *subtree resolution* needs SQL recursion.
  Stream<List<Label>> watchAll(LabelKind kind) {
    return (select(labels)
          ..where((t) => t.kind.equalsValue(kind) & t.deletedAt.isNull()))
        .watch();
  }

  Future<List<Label>> getAll(LabelKind kind) {
    return (select(labels)
          ..where((t) => t.kind.equalsValue(kind) & t.deletedAt.isNull()))
        .get();
  }

  Future<Label?> findById(String id) {
    return (select(labels)..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// Type-ahead source. Empty query returns everything of the kind.
  Future<List<Label>> search(LabelKind kind, String query) {
    final String trimmed = query.trim().toLowerCase();
    final SimpleSelectStatement<$LabelsTable, Label> q = select(labels)
      ..where((t) => t.kind.equalsValue(kind) & t.deletedAt.isNull());
    if (trimmed.isNotEmpty) {
      q.where((t) => t.name.lower().like('%$trimmed%'));
    }
    return q.get();
  }

  /// Exact-name lookup within a sibling group — drives the picker's
  /// "does this already exist?" check and the uniqueness guards below.
  Future<Label?> findByName(LabelKind kind, String name, {String? parentId}) {
    final String trimmed = name.trim().toLowerCase();
    final SimpleSelectStatement<$LabelsTable, Label> q = select(labels)
      ..where((t) => t.kind.equalsValue(kind) & t.deletedAt.isNull())
      ..where((t) => t.name.lower().equals(trimmed));
    if (parentId == null) {
      q.where((t) => t.parentId.isNull());
    } else {
      q.where((t) => t.parentId.equals(parentId));
    }
    return q.getSingleOrNull();
  }

  /// Ids of [rootId] and every live descendant, via the recursive CTE.
  /// This one query powers rollup totals, cascade delete, and move validation.
  Future<Set<String>> subtreeIds(String rootId) async {
    final List<QueryRow> rows = await customSelect(
      '''
WITH RECURSIVE subtree(id) AS (
  SELECT id FROM labels WHERE id = ?1 AND deleted_at IS NULL
  UNION ALL
  SELECT l.id FROM labels l JOIN subtree s ON l.parent_id = s.id WHERE l.deleted_at IS NULL
)
SELECT id FROM subtree
''',
      variables: [Variable<String>(rootId)],
      readsFrom: {labels},
    ).get();
    return rows.map((QueryRow r) => r.read<String>('id')).toSet();
  }

  /// Max depth anywhere in [rootId]'s subtree, relative to [rootId].
  /// A leaf is 0. Used by the move-validity math.
  Future<int> subtreeHeight(String rootId) async {
    final List<QueryRow> rows = await customSelect(
      '''
WITH RECURSIVE subtree(id, depth) AS (
  SELECT id, depth FROM labels WHERE id = ?1 AND deleted_at IS NULL
  UNION ALL
  SELECT l.id, l.depth FROM labels l JOIN subtree s ON l.parent_id = s.id
    WHERE l.deleted_at IS NULL
)
SELECT MAX(depth) - MIN(depth) AS height FROM subtree
''',
      variables: [Variable<String>(rootId)],
      readsFrom: {labels},
    ).get();
    if (rows.isEmpty) return 0;
    return rows.first.read<int?>('height') ?? 0;
  }

  /// Live transactions pointing at any label in [labelIds], for the given kind's
  /// column. Counted before a delete so the dialog can state the impact.
  Future<int> countTransactionsReferencing(LabelKind kind, Set<String> labelIds) async {
    if (labelIds.isEmpty) return 0;
    final String column = kind == LabelKind.category ? 'category_id' : 'payment_method_id';
    final String placeholders = List<String>.filled(labelIds.length, '?').join(',');
    final List<QueryRow> rows = await customSelect(
      'SELECT COUNT(*) AS c FROM transactions '
      'WHERE deleted_at IS NULL AND $column IN ($placeholders)',
      variables: labelIds.map((String id) => Variable<String>(id)).toList(),
      readsFrom: {transactions},
    ).get();
    return rows.first.read<int>('c');
  }

  // --------------------------------------------------------------- writes

  /// Creates a label under [parentId] (null = top level).
  ///
  /// Enforces: parent exists and is live, parent is not a placeholder, the
  /// resulting depth is within [kMaxDepth], and no live sibling shares the name.
  Future<Label> create({
    required LabelKind kind,
    required String name,
    String? parentId,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const LabelException('Name cannot be blank.');
    }

    return transaction(() async {
      int depth = 0;
      if (parentId != null) {
        final Label? parent = await findById(parentId);
        if (parent == null) {
          throw const LabelException('That parent no longer exists.');
        }
        if (parent.isPlaceholder) {
          throw LabelException('"${parent.name}" cannot have sub-items.');
        }
        if (parent.kind != kind) {
          throw const LabelException('Parent belongs to a different list.');
        }
        depth = parent.depth + 1;
        if (depth > kMaxDepth) {
          throw LabelException(
            'Nesting is limited to ${kMaxDepth + 1} levels.',
          );
        }
      }

      final Label? clash = await findByName(kind, trimmed, parentId: parentId);
      if (clash != null) {
        throw LabelException('"$trimmed" already exists here.');
      }

      final int now = _now;
      final Label row = Label(
        id: newId(),
        kind: kind,
        name: trimmed,
        parentId: parentId,
        depth: depth,
        isPlaceholder: false,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );
      await into(labels).insert(row);
      return row;
    });
  }

  /// Renames in place. Because transactions reference labels by id, this alone
  /// makes the §2.4 rename cascade true — no transaction rows are touched.
  Future<void> rename(String id, String newName) async {
    final String trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const LabelException('Name cannot be blank.');
    }

    await transaction(() async {
      final Label target = await _requireLive(id);
      if (target.isPlaceholder) {
        throw LabelException('"${target.name}" cannot be renamed.');
      }
      if (target.name == trimmed) return;

      final Label? clash = await findByName(target.kind, trimmed, parentId: target.parentId);
      if (clash != null && clash.id != id) {
        throw LabelException('"$trimmed" already exists here.');
      }

      await (update(labels)..where((t) => t.id.equals(id))).write(
        LabelsCompanion(name: Value(trimmed), updatedAt: Value(_now)),
      );
    });
  }

  /// Checks a reparent without performing it. Mirrors [move]'s rules exactly so
  /// the confirmation dialog can never promise something the write rejects.
  Future<MoveCheck> checkMove(String id, String? newParentId) async {
    final Label? target = await findById(id);
    if (target == null) {
      return const MoveCheck.invalid('That item no longer exists.');
    }
    if (target.isPlaceholder) {
      return MoveCheck.invalid('"${target.name}" cannot be moved.');
    }

    final Set<String> subtree = await subtreeIds(id);
    final int descendantCount = subtree.length - 1;

    if (newParentId == target.parentId) {
      return MoveCheck.invalid(
        '"${target.name}" is already there.',
        subtreeCount: descendantCount,
      );
    }

    int parentDepth = -1;
    if (newParentId != null) {
      if (newParentId == id) {
        return MoveCheck.invalid(
          'An item cannot be moved into itself.',
          subtreeCount: descendantCount,
        );
      }
      if (subtree.contains(newParentId)) {
        return MoveCheck.invalid(
          'An item cannot be moved into its own sub-items.',
          subtreeCount: descendantCount,
        );
      }

      final Label? parent = await findById(newParentId);
      if (parent == null) {
        return MoveCheck.invalid(
          'That destination no longer exists.',
          subtreeCount: descendantCount,
        );
      }
      if (parent.isPlaceholder) {
        return MoveCheck.invalid(
          '"${parent.name}" cannot have sub-items.',
          subtreeCount: descendantCount,
        );
      }
      if (parent.kind != target.kind) {
        return MoveCheck.invalid(
          'That destination belongs to a different list.',
          subtreeCount: descendantCount,
        );
      }
      parentDepth = parent.depth;
    }

    // dp + 1 + h(x) <= kMaxDepth
    final int height = await subtreeHeight(id);
    if (parentDepth + 1 + height > kMaxDepth) {
      return MoveCheck.invalid(
        'That would nest deeper than ${kMaxDepth + 1} levels.',
        subtreeCount: descendantCount,
      );
    }

    final Label? clash = await findByName(target.kind, target.name, parentId: newParentId);
    if (clash != null && clash.id != id) {
      return MoveCheck.invalid(
        '"${target.name}" already exists there.',
        subtreeCount: descendantCount,
      );
    }

    return MoveCheck.valid(
      subtreeCount: descendantCount,
      newDepth: parentDepth + 1,
      subtree: subtree,
    );
  }

  /// Reparents [id] and shifts `depth` across its whole subtree atomically.
  /// Transaction rows are untouched — only analytics rollups shift.
  Future<void> move(String id, String? newParentId) async {
    await transaction(() async {
      final MoveCheck check = await checkMove(id, newParentId);
      if (!check.valid) {
        throw LabelException(check.reason!);
      }

      final Label target = await _requireLive(id);
      final int delta = check.newDepth! - target.depth;
      final int now = _now;

      await (update(labels)..where((t) => t.id.equals(id))).write(
        LabelsCompanion(
          parentId: Value<String?>(newParentId),
          depth: Value(check.newDepth!),
          updatedAt: Value(now),
        ),
      );

      if (delta != 0) {
        // Descendants keep their parent; only their depth shifts.
        final Set<String> descendants = Set<String>.of(check.subtree!)..remove(id);
        for (final String descendantId in descendants) {
          await customUpdate(
            'UPDATE labels SET depth = depth + ?, updated_at = ? WHERE id = ?',
            variables: [
              Variable<int>(delta),
              Variable<int>(now),
              Variable<String>(descendantId),
            ],
            updates: {labels},
          );
        }
      }
    });
  }

  /// Counts what [deleteCascade] would affect, without mutating anything.
  Future<(int descendantCount, int affectedTransactionCount)> previewDelete(String id) async {
    final Label? target = await findById(id);
    if (target == null) return (0, 0);

    final Set<String> subtree = await subtreeIds(id);
    final int affected = await countTransactionsReferencing(target.kind, subtree);
    return (subtree.length - 1, affected);
  }

  /// Soft-deletes [id] and its whole subtree, reassigning every referencing
  /// transaction to the kind's placeholder — all in one atomic transaction, so
  /// no entry can be left pointing at a deleted label.
  Future<void> deleteCascade(String id) async {
    await transaction(() async {
      final Label target = await _requireLive(id);
      if (target.isPlaceholder) {
        throw LabelException('"${target.name}" cannot be deleted.');
      }

      final Set<String> subtree = await subtreeIds(id);
      final int now = _now;
      final String placeholderId = placeholderIdFor(target.kind);
      final String column =
          target.kind == LabelKind.category ? 'category_id' : 'payment_method_id';
      final String inList = List<String>.filled(subtree.length, '?').join(',');
      final List<Variable<Object>> idVars =
          subtree.map((String s) => Variable<String>(s)).toList();

      // 1. Reassign referencing transactions to the placeholder (§2.4/§2.6).
      await customUpdate(
        'UPDATE transactions SET $column = ?, updated_at = ? '
        'WHERE deleted_at IS NULL AND $column IN ($inList)',
        variables: <Variable<Object>>[
          Variable<String>(placeholderId),
          Variable<int>(now),
          ...idVars,
        ],
        updates: {transactions},
      );

      // 2. Soft-delete the subtree. Clearing parent_id is deliberate: the
      //    partial unique index only covers live rows, so tombstones must not
      //    block a future label reusing the same (kind, parent, name) slot.
      await customUpdate(
        'UPDATE labels SET deleted_at = ?, updated_at = ? WHERE id IN ($inList)',
        variables: <Variable<Object>>[
          Variable<int>(now),
          Variable<int>(now),
          ...idVars,
        ],
        updates: {labels},
      );
    });
  }

  Future<Label> _requireLive(String id) async {
    final Label? row = await findById(id);
    if (row == null) {
      throw const LabelException('That item no longer exists.');
    }
    return row;
  }
}

/// Result of [LabelDao.checkMove]. Carries the resolved subtree and target depth
/// so [LabelDao.move] doesn't recompute them.
class MoveCheck {
  const MoveCheck.valid({
    required this.subtreeCount,
    required this.newDepth,
    required this.subtree,
  }) : valid = true,
       reason = null;

  const MoveCheck.invalid(String this.reason, {this.subtreeCount = 0})
    : valid = false,
      newDepth = null,
      subtree = null;

  final bool valid;
  final String? reason;
  final int subtreeCount;
  final int? newDepth;
  final Set<String>? subtree;
}
