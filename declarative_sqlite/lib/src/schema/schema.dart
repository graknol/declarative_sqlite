import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:declarative_sqlite/src/schema/table.dart';
import 'package:declarative_sqlite/src/schema/view.dart';

class Schema {
  final List<Table> tables;
  final List<View> views;

  Iterable<Table> get userTables => tables.where((t) => !t.isSystem);
  Iterable<Table> get systemTables => tables.where((t) => t.isSystem);


  const Schema({
    required this.tables,
    required this.views,
  });

  String toHash() {
    final schemaMap = {
      'tables': tables.map((t) => t.toMap()).toList(),
      'views': views.map((v) => v.toMap()).toList(),
    };
    final jsonString = jsonEncode(schemaMap);
    return sha256.convert(utf8.encode(jsonString)).toString();
  }
}
