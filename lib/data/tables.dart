import 'package:drift/drift.dart';

enum LabelKind { category, paymentMethod }

class Labels extends Table {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<LabelKind>()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable().references(Labels, #id)();
  IntColumn get depth => integer()(); // 0..2
  BoolColumn get isPlaceholder => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()(); // UTC epoch ms
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    'CHECK (depth BETWEEN 0 AND 2)',
    'CHECK (length(trim(name)) > 0)',
  ];
}

class Transactions extends Table {
  TextColumn get id => text()();
  IntColumn get amountCents => integer()();
  IntColumn get occurredAt => integer()(); // UTC epoch ms, user-editable
  TextColumn get categoryId => text().references(Labels, #id)();
  TextColumn get paymentMethodId => text().references(Labels, #id)();
  TextColumn get note => text()();
  TextColumn get extraNotes => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    'CHECK (amount_cents > 0)',
    'CHECK (length(trim(note)) > 0)',
  ];
}
