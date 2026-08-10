// Impact counts backing the §3.1 confirmation dialogs. Every structural
// mutation previews its blast radius before the user commits to it.

/// What a cascade delete would take with it.
class DeleteImpact {
  const DeleteImpact({
    required this.descendantCount,
    required this.affectedTransactionCount,
  });

  /// Sub-labels deleted alongside the target (excludes the target itself).
  final int descendantCount;

  /// Live transactions that would be reassigned to the placeholder.
  final int affectedTransactionCount;
}

/// Whether a reparent is legal, and what it would move.
class MoveImpact {
  const MoveImpact({
    required this.subtreeCount,
    required this.valid,
    this.reason,
  });

  const MoveImpact.invalid(String this.reason, {this.subtreeCount = 0}) : valid = false;

  /// Sub-labels that travel with the moved node (excludes the node itself).
  final int subtreeCount;

  /// False when [reason] explains why the move is rejected.
  final bool valid;

  /// User-facing rejection reason; null when [valid].
  final String? reason;
}

/// How many past entries a rename would re-label.
class RenameImpact {
  const RenameImpact({required this.affectedTransactionCount});

  final int affectedTransactionCount;
}
