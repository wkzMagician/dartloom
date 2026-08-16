import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

Future<DatabaseConnection> openDartloomConnection(String name) async =>
    DatabaseConnection(driftDatabase(name: name));
