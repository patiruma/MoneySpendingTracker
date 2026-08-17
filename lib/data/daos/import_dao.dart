import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/csv_import.dart';
import '../../core/ids.dart';
import '../database.dart';
import '../models/import_plan.dart';
import '../tables.dart';
import 'label_dao.dart' show placeholderIdFor;

part 'import_dao.g.dart';

/// Resolves parsed CSV rows against the live database and commits them.
///
/// Split into a read-only [plan] and a writing [commit] so the user sees real
/// counts — how many rows are new, how many collide, how many labels would be
/// created — and answers every duplicate prompt *before* a single row is
/// written. Nothing in [plan] mutates.
@DriftAccessor(tables: [Transactions, Labels])
class ImportDao extends DatabaseAccessor<AppDatabase> with _$ImportDaoMixin {
  ImportDao(super.db);

  int get _now => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Builds the label-name → id map used to resolve a row's category and
  /// payment method.
  ///
  /// The export format writes a label's own name, not its full path, so a name
  /// can be ambiguous — `Restaurants` might exist under both `Food` and
  /// `Travel`. A top-level match wins; otherwise the shallowest, then
  /// alphabetically first, so resolution is deterministic across runs rather
  /// than dependent on row order.
  Future<Map<String, Label>> _labelsByName(LabelKind kind) async {
    final List<Label> live = await (select(labels)
          ..where((t) => t.kind.equalsValue(kind) & t.deletedAt.isNull()))
        .get();

    final Map<String, Label> byName = <String, Label>{};
    for (final Label label in live) {
      final String key = label.name.trim().toLowerCase();
      final Label? existing = byName[key];
      if (existing == null || _preferredOver(label, existing)) {
        byName[key] = label;
      }
    }
    return byName;
  }

  Future<Label?> _findById(String id) =>
      (select(labels)..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .getSingleOrNull();

  static bool _preferredOver(Label candidate, Label incumbent) {
    if (candidate.depth != incumbent.depth) return candidate.depth < incumbent.depth;
    return candidate.id.compareTo(incumbent.id) < 0;
  }

  /// Read-only. Resolves labels, finds exact duplicates, and reports which
  /// labels would have to be created — without writing anything.
  Future<ImportPlan> plan(ImportParseResult parsed) async {
    final Map<String, Label> categories = await _labelsByName(LabelKind.category);
    final Map<String, Label> payments = await _labelsByName(LabelKind.paymentMethod);

    final Set<String> newCategories = <String>{};
    final Set<String> newPayments = <String>{};

    for (final ImportRow row in parsed.rows) {
      final String category = row.categoryName.trim();
      if (category.isNotEmpty && !categories.containsKey(category.toLowerCase())) {
        newCategories.add(category);
      }
      final String payment = row.paymentMethodName.trim();
      if (payment.isNotEmpty && !payments.containsKey(payment.toLowerCase())) {
        newPayments.add(payment);
      }
    }

    // Duplicate detection is scoped to the rows a match could plausibly hit:
    // every live transaction whose occurred-at appears in the file. Loading
    // only those keeps this proportional to the import, not to the whole
    // database.
    final Set<int> incomingTimes =
        parsed.rows.map((ImportRow r) => r.occurredAt).toSet();
    final List<TransactionWithNames> existing = incomingTimes.isEmpty
        ? const <TransactionWithNames>[]
        : await _liveTransactionsAt(incomingTimes);

    // Read the placeholders' display names rather than hardcoding them, so
    // matching stays right if the seeded text ever changes.
    final String noCategoryName =
        (await _findById(kNoCategoryId))?.name ?? 'No Category';
    final String noPaymentMethodName =
        (await _findById(kNoPaymentMethodId))?.name ?? 'No Payment Method';

    final List<ImportRow> newRows = [];
    final List<DuplicateCandidate> duplicates = [];
    // Existing rows already claimed by an earlier incoming row. Without this,
    // a file containing the same transaction twice would match both copies
    // against the one existing row, and answering "skip" once would wrongly
    // drop a row that has no counterpart in the database.
    final Set<String> claimed = <String>{};

    for (final ImportRow row in parsed.rows) {
      TransactionWithNames? match;
      for (final TransactionWithNames candidate in existing) {
        if (claimed.contains(candidate.transaction.id)) continue;
        if (_isExactMatch(row, candidate, noCategoryName, noPaymentMethodName)) {
          match = candidate;
          break;
        }
      }

      if (match == null) {
        newRows.add(row);
      } else {
        claimed.add(match.transaction.id);
        duplicates.add(DuplicateCandidate(row: row, existing: match.transaction));
      }
    }

    return ImportPlan(
      newRows: newRows,
      duplicates: duplicates,
      errors: parsed.errors,
      newCategoryNames: newCategories,
      newPaymentMethodNames: newPayments,
    );
  }

  /// Every field the CSV carries must agree. Time is part of the key on
  /// purpose: two identical purchases on the same day are a real thing, and
  /// they differ in nothing else.
  ///
  /// Labels are compared on the name the row would **resolve to**, not the raw
  /// cell. A blank cell resolves to the placeholder, so a row exported with an
  /// empty category comes back as "No Category" — comparing raw text would miss
  /// that and re-import the row as new on every pass.
  static bool _isExactMatch(
    ImportRow row,
    TransactionWithNames existing,
    String noCategoryName,
    String noPaymentMethodName,
  ) {
    final Transaction t = existing.transaction;
    final String rowCategory = row.categoryName.trim().isEmpty
        ? noCategoryName
        : row.categoryName.trim();
    final String rowPayment = row.paymentMethodName.trim().isEmpty
        ? noPaymentMethodName
        : row.paymentMethodName.trim();

    return t.occurredAt == row.occurredAt &&
        t.amountCents == row.amountCents &&
        t.note.trim() == row.note.trim() &&
        (t.extraNotes ?? '').trim() == (row.extraNotes ?? '').trim() &&
        existing.categoryName.trim().toLowerCase() ==
            rowCategory.toLowerCase() &&
        existing.paymentMethodName.trim().toLowerCase() ==
            rowPayment.toLowerCase();
  }

  Future<List<TransactionWithNames>> _liveTransactionsAt(Set<int> occurredAt) async {
    final $LabelsTable categoryLabels = alias(labels, 'category_labels');
    final $LabelsTable paymentLabels = alias(labels, 'payment_labels');

    final JoinedSelectStatement<HasResultSet, dynamic> q =
        select(transactions).join([
          innerJoin(categoryLabels, categoryLabels.id.equalsExp(transactions.categoryId)),
          innerJoin(paymentLabels, paymentLabels.id.equalsExp(transactions.paymentMethodId)),
        ])
          ..where(transactions.deletedAt.isNull())
          ..where(transactions.occurredAt.isIn(occurredAt));

    final List<TypedResult> rows = await q.get();
    return rows
        .map(
          (TypedResult row) => TransactionWithNames(
            transaction: row.readTable(transactions),
            categoryName: row.readTable(categoryLabels).name,
            paymentMethodName: row.readTable(paymentLabels).name,
          ),
        )
        .toList(growable: false);
  }

  /// Writes the planned import in **one** transaction: label creation and row
  /// insertion succeed together or not at all. A partial import would leave
  /// the user with newly created labels and no entries under them, and no way
  /// to tell how far it got.
  ///
  /// [choices] maps a duplicate's source line number to the user's decision.
  /// Anything missing defaults to [DuplicateChoice.keepBoth] — the same
  /// no-data-loss default the confirmation offers.
  Future<ImportResult> commit(
    ImportPlan plan,
    Map<int, DuplicateChoice> choices,
  ) async {
    return transaction(() async {
      final int now = _now;
      int labelsCreated = 0;

      // Resolve inside the transaction so a label created here is visible to
      // every subsequent row in the same import.
      final Map<String, Label> categories = await _labelsByName(LabelKind.category);
      final Map<String, Label> payments = await _labelsByName(LabelKind.paymentMethod);

      Future<String> resolveLabel(
        String rawName,
        LabelKind kind,
        Map<String, Label> cache,
      ) async {
        final String name = rawName.trim();
        // A blank cell is exactly the "no value" case the placeholders exist
        // for, so it lands on one and shows up as needs-attention (§2.6).
        if (name.isEmpty) return placeholderIdFor(kind);

        final Label? found = cache[name.toLowerCase()];
        if (found != null) return found.id;

        // Created at the top level, matching the entry picker's fast path —
        // nesting is rebuilt on the manage screen (the export format carries
        // no parent, so there is nothing here to nest under).
        final Label created = Label(
          id: newId(),
          kind: kind,
          name: name,
          parentId: null,
          depth: 0,
          isPlaceholder: false,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        );
        await into(labels).insert(created);
        cache[name.toLowerCase()] = created;
        labelsCreated++;
        return created.id;
      }

      Future<void> insertRow(ImportRow row) async {
        final String categoryId =
            await resolveLabel(row.categoryName, LabelKind.category, categories);
        final String paymentMethodId = await resolveLabel(
          row.paymentMethodName,
          LabelKind.paymentMethod,
          payments,
        );
        await into(transactions).insert(
          TransactionsCompanion.insert(
            id: newId(),
            amountCents: row.amountCents,
            occurredAt: row.occurredAt,
            categoryId: categoryId,
            paymentMethodId: paymentMethodId,
            note: row.note,
            extraNotes: Value(row.extraNotes),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      int inserted = 0;
      int replaced = 0;
      int skipped = 0;

      for (final ImportRow row in plan.newRows) {
        await insertRow(row);
        inserted++;
      }

      for (final DuplicateCandidate candidate in plan.duplicates) {
        final DuplicateChoice choice =
            choices[candidate.row.lineNumber] ?? DuplicateChoice.keepBoth;
        switch (choice) {
          case DuplicateChoice.skip:
            skipped++;
          case DuplicateChoice.keepBoth:
            await insertRow(candidate.row);
            inserted++;
          case DuplicateChoice.replace:
            final ImportRow row = candidate.row;
            final String categoryId =
                await resolveLabel(row.categoryName, LabelKind.category, categories);
            final String paymentMethodId = await resolveLabel(
              row.paymentMethodName,
              LabelKind.paymentMethod,
              payments,
            );
            await (update(transactions)
                  ..where((t) => t.id.equals(candidate.existing.id)))
                .write(
                  TransactionsCompanion(
                    amountCents: Value(row.amountCents),
                    occurredAt: Value(row.occurredAt),
                    categoryId: Value(categoryId),
                    paymentMethodId: Value(paymentMethodId),
                    note: Value(row.note),
                    extraNotes: Value(row.extraNotes),
                    updatedAt: Value(now),
                  ),
                );
            replaced++;
        }
      }

      return ImportResult(
        inserted: inserted,
        replaced: replaced,
        skipped: skipped,
        labelsCreated: labelsCreated,
        errors: plan.errors,
      );
    });
  }
}

/// A transaction plus its label *names*, which is what duplicate matching
/// compares against (the CSV carries names, not ids).
class TransactionWithNames {
  const TransactionWithNames({
    required this.transaction,
    required this.categoryName,
    required this.paymentMethodName,
  });

  final Transaction transaction;
  final String categoryName;
  final String paymentMethodName;
}
