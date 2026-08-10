import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_spending_tracker/core/constants.dart';
import 'package:money_spending_tracker/data/database.dart';

import 'generated_migrations/schema.dart';

/// Migration safety net (plan §6). The on-device DB is the user's only copy —
/// there is no server backup — so a bad migration is unrecoverable data loss.
///
/// Regenerate the snapshot after any schema change:
///   dart run drift_dev schema dump lib/data/database.dart drift_schemas/
///   dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the live schema matches the v1 snapshot', () async {
    // Guards against editing tables.dart without bumping schemaVersion or
    // re-dumping: the generated snapshot and the code would silently diverge.
    final InitializedSchema schema = await verifier.schemaAt(1);
    final AppDatabase db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 1);
    await db.close();
  });

  test('a fresh v1 database seeds exactly the two placeholders', () async {
    // onCreate must produce the placeholder rows at their fixed UUIDs — every
    // needs-attention fallback (§2.6) depends on these existing.
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    final List<Label> labels = await db.select(db.labels).get();

    expect(labels, hasLength(2));
    expect(
      labels.map((Label l) => l.id),
      containsAll(<String>[kNoCategoryId, kNoPaymentMethodId]),
    );
    expect(labels.every((Label l) => l.isPlaceholder), isTrue);
    await db.close();
  });

  test('schemaVersion matches the newest dumped snapshot', () async {
    // If these drift apart, migrateAndValidate silently stops covering the
    // newest version.
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    expect(db.schemaVersion, GeneratedHelper.versions.last);
    await db.close();
  });
}
