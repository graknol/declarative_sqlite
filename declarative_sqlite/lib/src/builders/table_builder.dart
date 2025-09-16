import 'package:declarative_sqlite/src/schema/column.dart';
import 'package:declarative_sqlite/src/builders/column_builder.dart';
import 'package:declarative_sqlite/src/builders/date_column_builder.dart';
import 'package:declarative_sqlite/src/builders/fileset_column_builder.dart';
import 'package:declarative_sqlite/src/builders/guid_column_builder.dart';
import 'package:declarative_sqlite/src/builders/integer_column_builder.dart';
import 'package:declarative_sqlite/src/builders/key_builder.dart';
import 'package:declarative_sqlite/src/builders/real_column_builder.dart';
import 'package:declarative_sqlite/src/builders/reference_builder.dart';
import 'package:declarative_sqlite/src/builders/text_column_builder.dart';
import 'package:declarative_sqlite/src/schema/table.dart';

class TableBuilder {
  final String name;
  final List<ColumnBuilder> _columnBuilders = [];
  final List<KeyBuilder> _keyBuilders = [];
  final List<ReferenceBuilder> _referenceBuilders = [];

  TableBuilder(this.name);

  T _addColumn<T extends ColumnBuilder>(T builder) {
    _columnBuilders.add(builder);
    return builder;
  }

  GuidColumnBuilder guid(String name) => _addColumn(GuidColumnBuilder(name));
  TextColumnBuilder text(String name) => _addColumn(TextColumnBuilder(name));
  IntegerColumnBuilder integer(String name) =>
      _addColumn(IntegerColumnBuilder(name));
  RealColumnBuilder real(String name) => _addColumn(RealColumnBuilder(name));
  DateColumnBuilder date(String name) => _addColumn(DateColumnBuilder(name));
  FilesetColumnBuilder fileset(String name) =>
      _addColumn(FilesetColumnBuilder(name));

  KeyBuilder key(List<String> columns) {
    final builder = KeyBuilder(columns);
    _keyBuilders.add(builder);
    return builder;
  }

  ReferenceBuilder reference(List<String> columns) {
    final builder = ReferenceBuilder(columns);
    _referenceBuilders.add(builder);
    return builder;
  }

  Table build() {
    final columns = _columnBuilders.map((b) => b.build()).toList();
    final hlcColumns = <Column>[];
    for (final column in columns) {
      if (column.isLww) {
        hlcColumns.add(
          Column(
            name: '${column.name}__hlc',
            type: 'TEXT',
            isNotNull: false, // Nullable to support partial inserts
            isParent: false,
            isLww: false,
          ),
        );
      }
    }

    final systemColumns = [
      Column(
        name: 'system_id',
        type: 'TEXT', // GUID
        isNotNull: false, // Nullable for migrations
        isParent: false,
        isLww: false,
      ),
      Column(
        name: 'system_created_at',
        type: 'TEXT', // HLC
        isNotNull: false, // Nullable for migrations
        isParent: false,
        isLww: false,
      ),
      Column(
        name: 'system_version',
        type: 'TEXT', // HLC
        isNotNull: false, // Nullable for migrations
        isParent: false,
        isLww: false,
      ),
    ];

    return Table(
      name: name,
      columns: [...systemColumns, ...columns, ...hlcColumns],
      keys: _keyBuilders.map((b) => b.build()).toList(),
      references: _referenceBuilders.map((b) => b.build()).toList(),
    );
  }
}
