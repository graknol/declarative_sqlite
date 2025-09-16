import 'package:declarative_sqlite/src/schema/schema.dart';
import 'package:declarative_sqlite/src/schema/table.dart';
import 'package:declarative_sqlite/src/schema/view.dart';
import 'package:declarative_sqlite/src/builders/table_builder.dart';
import 'package:declarative_sqlite/src/builders/view_builder.dart';

class SchemaBuilder {
  final _tables = <Table>[];
  final _views = <View>[];
  int _version = 1;

  void table(String name, void Function(TableBuilder) build) {
    final builder = TableBuilder(name);
    build(builder);
    _tables.add(builder.build());
  }

  void view(String name, void Function(ViewBuilder) build) {
    final builder = ViewBuilder(name);
    build(builder);
    _views.add(builder.build());
  }

  void version(int version) {
    _version = version;
  }

  Schema build() {
    return Schema(version: _version, tables: _tables, views: _views);
  }
}
