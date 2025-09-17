import 'package:declarative_sqlite/src/schema/table.dart';
import 'package:declarative_sqlite/src/schema/schema.dart';
import 'package:declarative_sqlite/src/builders/table_builder.dart';
import 'package:declarative_sqlite/src/builders/view_builder.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';

/// A fluent builder for defining a database schema.
///
/// The `SchemaBuilder` is the entry point for defining the structure of your
/// database, including its tables and views.
///
/// Example:
/// ```dart
/// final schemaBuilder = SchemaBuilder();
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
  final _tableBuilders = <TableBuilder>[];
  final _viewBuilders = <ViewBuilder>[];

  /// Defines a table in the schema.
  ///
  /// The [name] is the name of the table.
  /// The [build] callback provides a [TableBuilder] to define the table's
  /// columns and keys.
  ///
  /// The [name] is not allowed to start with `__` (two underscores) as that is
  /// reserved for system tables.
  void table(String name, void Function(TableBuilder) build) {
    final builder = TableBuilder(name);
    build(builder);
    _tableBuilders.add(builder);
  }

  /// Defines a view in the schema.
  ///
  /// The [name] is the name of the view.
  /// The [build] callback provides a [ViewBuilder] to define the view's
  /// SELECT statement.
  void view(String name, void Function(ViewBuilder) build) {
    final builder = ViewBuilder(name);
    build(builder);
    _viewBuilders.add(builder);
  }

  /// Builds the [Schema] object.
  ///
  /// This should be called after all tables and views have been defined.
  Schema build() {
    final userTables = _tableBuilders
        .where((t) => !t.name.startsWith('__'))
        .map((b) => b.build())
        .toList();
    final systemTables = [
      _buildSystemTableSettings(),
      _buildSystemTableFiles(),
      _buildSystemTableDirtyRows(),
    ];

    return Schema(
      tables: [...userTables, ...systemTables],
      views: _viewBuilders.map((b) => b.build()).toList(),
    );
  }

  Table _buildSystemTableSettings() {
    final builder = TableBuilder('__settings');
    builder.text('key').notNull('_');
    builder.text('value');
    builder.key(['key']).primary();
    return builder.build();
  }

  Table _buildSystemTableFiles() {
    final builder = TableBuilder('__files');
    builder.guid('id').notNull('00000000-0000-0000-0000-000000000000');
    builder.guid('owner_id').notNull('00000000-0000-0000-0000-000000000000');
    builder.text('filename').notNull('default');
    builder.integer('remote_version').notNull(0);
    builder.text('mimetype').notNull('application/octet-stream');
    builder.integer('size').notNull(0);
    builder.key(['id']).primary();
    builder.key(['owner_id', 'filename']).index();
    return builder.build();
  }

  Table _buildSystemTableDirtyRows() {
    final builder = TableBuilder('__dirty_rows');
    builder.text('table_name').notNull('default');
    builder.guid('row_id').notNull('00000000-0000-0000-0000-000000000000');
    builder.text('hlc').notNull(Hlc.min.toString());
    builder.key(['table_name', 'row_id']).primary();
    return builder.build();
  }
}
