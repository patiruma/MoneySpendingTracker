import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/constants.dart';
import 'daos/label_dao.dart';
import 'daos/transaction_dao.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Labels, Transactions], daos: [LabelDao, TransactionDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'spending_tracker'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await customStatement(
        'CREATE UNIQUE INDEX ux_labels_sibling '
        "ON labels (kind, IFNULL(parent_id,''), name) WHERE deleted_at IS NULL;",
      );
      await customStatement('CREATE INDEX ix_labels_parent ON labels (kind, parent_id);');
      await customStatement(
        'CREATE INDEX ix_tx_occurred ON transactions (occurred_at DESC) WHERE deleted_at IS NULL;',
      );
      await customStatement('CREATE INDEX ix_tx_category ON transactions (category_id);');
      await customStatement('CREATE INDEX ix_tx_payment ON transactions (payment_method_id);');
      await _seedPlaceholders();
    },
  );

  Future<void> _seedPlaceholders() async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await into(labels).insert(
      LabelsCompanion.insert(
        id: kNoCategoryId,
        kind: LabelKind.category,
        name: 'No Category',
        depth: 0,
        isPlaceholder: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await into(labels).insert(
      LabelsCompanion.insert(
        id: kNoPaymentMethodId,
        kind: LabelKind.paymentMethod,
        name: 'No Payment Method',
        depth: 0,
        isPlaceholder: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}
