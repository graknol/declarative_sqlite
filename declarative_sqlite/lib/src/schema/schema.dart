import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:declarative_sqlite/src/schema/db_table.dart';
import 'package:declarative_sqlite/src/schema/db_view.dart';
import '../builders/analysis_context.dart';

class Schema implements SchemaProvider {
  final List<DbTable> tables;
  final List<DbView> views;

  Iterable<DbTable> get userTables => tables.where((t) => !t.isSystem);
  Iterable<DbTable> get systemTables => tables.where((t) => t.isSystem);


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

  Map<String, dynamic> toJson() => {
        'tables': tables.map((t) => t.toJson()).toList(),
        'views': views.map((v) => v.name).toList(), // Assuming DbView has a name property and we just store that for now
      };

  factory Schema.fromJson(Map<String, dynamic> json) => Schema(
        tables: (json['tables'] as List)
            .map((t) => DbTable.fromJson(t))
            .toList(),
        views: [], // Assuming we don't need to deserialize views for now
      );
}
