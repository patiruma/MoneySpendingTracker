// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_dao.dart';

// ignore_for_file: type=lint
mixin _$ImportDaoMixin on DatabaseAccessor<AppDatabase> {
  $LabelsTable get labels => attachedDatabase.labels;
  $TransactionsTable get transactions => attachedDatabase.transactions;
  ImportDaoManager get managers => ImportDaoManager(this);
}

class ImportDaoManager {
  final _$ImportDaoMixin _db;
  ImportDaoManager(this._db);
  $$LabelsTableTableManager get labels =>
      $$LabelsTableTableManager(_db.attachedDatabase, _db.labels);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db.attachedDatabase, _db.transactions);
}
