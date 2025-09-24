import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:declarative_sqlite/src/schema/table.dart';
import 'package:declarative_sqlite/src/schema/view.dart';
import '../builders/analysis_context.dart';

class Schema implements SchemaProvider {
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

  @override
  bool tableHasColumn(String tableName, String columnName) {
    // Check tables
    final table = tables.where((t) => t.name == tableName).firstOrNull;
    if (table != null) {
      return table.columns.any((c) => c.name == columnName);
    }
    
    // Check views using the new structured information
    final view = views.where((v) => v.name == tableName).firstOrNull;
    if (view != null) {
      return view.columns.any((c) => c.name == columnName);
    }
    
    return false;
  }

  @override
  List<String> getTablesWithColumn(String columnName) {
    final result = <String>[];
    
    // Check all tables
    for (final table in tables) {
      if (table.columns.any((c) => c.name == columnName)) {
        result.add(table.name);
      }
    }
    
    // Check all views using structured column information
    for (final view in views) {
      if (view.columns.any((c) => c.name == columnName)) {
        result.add(view.name);
      }
    }
    
    return result;
  }
}
