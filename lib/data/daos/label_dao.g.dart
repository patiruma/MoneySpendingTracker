// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'label_dao.dart';

// ignore_for_file: type=lint
mixin _$LabelDaoMixin on DatabaseAccessor<AppDatabase> {
  $LabelsTable get labels => attachedDatabase.labels;
  $TransactionsTable get transactions => attachedDatabase.transactions;
  LabelDaoManager get managers => LabelDaoManager(this);
}

class LabelDaoManager {
  final _$LabelDaoMixin _db;
  LabelDaoManager(this._db);
  $$LabelsTableTableManager get labels =>
      $$LabelsTableTableManager(_db.attachedDatabase, _db.labels);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db.attachedDatabase, _db.transactions);
}
