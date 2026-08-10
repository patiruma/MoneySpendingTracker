import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Generates a UUID v7 string (time-sortable, sync-friendly primary key).
String newId() => _uuid.v7();
