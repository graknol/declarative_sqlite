import 'package:declarative_sqlite/src/schema/schema.dart';
import 'package:declarative_sqlite/src/schema/table.dart';
import 'package:declarative_sqlite/src/schema/view.dart';
import 'package:declarative_sqlite/src/builders/table_builder.dart';
import 'package:declarative_sqlite/src/builders/view_builder.dart';

class SchemaBuilder {
  final List<Table> _tables = [];
  final List<View> _views = [];

  void table(String name, void Function(TableBuilder table) callback) {
    final builder = TableBuilder(name);
    callback(builder);
    _tables.add(builder.build());
  }

  void view(String name, void Function(ViewBuilder view) callback) {
    final builder = ViewBuilder(name);
    callback(builder);
    _views.add(builder.build());
  }

  Schema build() {
    return Schema(tables: _tables, views: _views);
  }
}
