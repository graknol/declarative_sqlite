import 'package:declarative_sqlite/src/schema/schema.dart';
import 'package:declarative_sqlite/src/schema/table.dart';
import 'package:declarative_sqlite/src/schema/view.dart';
import 'package:declarative_sqlite/src/builders/table_builder.dart';
import 'package:declarative_sqlite/src/builders/view_builder.dart';

/// A fluent builder for defining a database schema.
///
/// The `SchemaBuilder` is the entry point for defining the structure of your
/// database, including its tables, views, and version.
///
/// Example:
/// ```dart
/// final schemaBuilder = SchemaBuilder();
/// schemaBuilder.version(2);
///
/// schemaBuilder.table('users', (table) {
///   table.guid('id').notNull(Uuid().v4());
///   table.text('name').notNull('Default Name');
///   table.integer('age').notNull(0);
///   table.key(['id']).primary();
/// });
///
/// schemaBuilder.view('user_names', (view) {
///   view.select('name').from('users');
/// });
///
/// final schema = schemaBuilder.build();
/// ```
class SchemaBuilder {
  final _tables = <Table>[];
  final _views = <View>[];
  int _version = 1;

  /// Defines a table in the schema.
  ///
  /// The [name] is the name of the table.
  /// The [build] callback provides a [TableBuilder] to define the table's
  /// columns and keys.
  void table(String name, void Function(TableBuilder) build) {
    final builder = TableBuilder(name);
    build(builder);
    _tables.add(builder.build());
  }

  /// Defines a view in the schema.
  ///
  /// The [name] is the name of the view.
  /// The [build] callback provides a [ViewBuilder] to define the view's
  /// SELECT statement.
  void view(String name, void Function(ViewBuilder) build) {
    final builder = ViewBuilder(name);
    build(builder);
    _views.add(builder.build());
  }

  /// Sets the version of the schema.
  ///
  /// The version is used for database migrations. When you change the schema,
  /// you should increment the version number.
  void version(int version) {
    _version = version;
  }

  /// Builds the [Schema] object.
  ///
  /// This should be called after all tables and views have been defined.
  Schema build() {
    final hasFileset =
        _tables.any((t) => t.columns.any((c) => c.logicalType == 'fileset'));

    if (hasFileset) {
      final filesTableBuilder = TableBuilder('__files');
      filesTableBuilder.guid('id').notNull();
      filesTableBuilder.guid('owner_id').notNull();
      filesTableBuilder.text('filename').notNull();
      filesTableBuilder.text('path');
      filesTableBuilder.text('mimetype').notNull();
      filesTableBuilder.integer('size').notNull();
      filesTableBuilder.key(['id']).primary();
      filesTableBuilder.key(['owner_id']).index();
      _tables.add(filesTableBuilder.build());
    }

    return Schema(version: _version, tables: _tables, views: _views);
  }
}
