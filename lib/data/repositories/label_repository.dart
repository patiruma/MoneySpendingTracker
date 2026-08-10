import '../daos/label_dao.dart';
import '../database.dart';
import '../models/impacts.dart';
import '../models/label_node.dart';
import '../tables.dart';

export '../daos/label_dao.dart' show LabelException;

/// The label vocabulary for both Categories and Payment Methods (§2.4).
///
/// Every method is parameterized by [LabelKind] rather than duplicated per
/// kind — the two share byte-identical rules, so this is written once.
class LabelRepository {
  LabelRepository(this._dao);

  final LabelDao _dao;

  /// The manage screen's source of truth. Re-emits on every write, so callers
  /// never invalidate manually.
  Stream<List<LabelNode>> watchTree(LabelKind kind) =>
      _dao.watchAll(kind).map(buildLabelTree);

  Future<List<LabelNode>> getTree(LabelKind kind) async =>
      buildLabelTree(await _dao.getAll(kind));

  /// Type-ahead backing for [LabelPicker].
  Future<List<Label>> search(LabelKind kind, String query) => _dao.search(kind, query);

  Future<Label?> findByName(LabelKind kind, String name, {String? parentId}) =>
      _dao.findByName(kind, name, parentId: parentId);

  Future<Label?> findById(String id) => _dao.findById(id);

  Future<Label> create({
    required LabelKind kind,
    required String name,
    String? parentId,
  }) => _dao.create(kind: kind, name: name, parentId: parentId);

  /// How many past entries a rename would re-label. The rename itself touches
  /// no transaction rows — this count is what the §3.1 dialog reports.
  Future<RenameImpact> previewRename(String id) async {
    final Label? target = await _dao.findById(id);
    if (target == null) {
      return const RenameImpact(affectedTransactionCount: 0);
    }
    final int count = await _dao.countTransactionsReferencing(target.kind, {id});
    return RenameImpact(affectedTransactionCount: count);
  }

  Future<void> rename(String id, String newName) => _dao.rename(id, newName);

  Future<MoveImpact> previewMove(String id, String? newParentId) async {
    final MoveCheck check = await _dao.checkMove(id, newParentId);
    return MoveImpact(
      subtreeCount: check.subtreeCount,
      valid: check.valid,
      reason: check.reason,
    );
  }

  Future<void> move(String id, String? newParentId) => _dao.move(id, newParentId);

  Future<DeleteImpact> previewDelete(String id) async {
    final (int descendants, int affected) = await _dao.previewDelete(id);
    return DeleteImpact(
      descendantCount: descendants,
      affectedTransactionCount: affected,
    );
  }

  Future<void> deleteCascade(String id) => _dao.deleteCascade(id);

  Future<Set<String>> subtreeIds(String id) => _dao.subtreeIds(id);
}
