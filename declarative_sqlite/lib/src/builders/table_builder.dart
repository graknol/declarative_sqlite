import 'package:declarative_sqlite/src/schema/db_column.dart';
import 'package:declarative_sqlite/src/builders/column_builder.dart';
import 'package:declarative_sqlite/src/builders/date_column_builder.dart';
import 'package:declarative_sqlite/src/builders/fileset_column_builder.dart';
import 'package:declarative_sqlite/src/builders/guid_column_builder.dart';
import 'package:declarative_sqlite/src/builders/integer_column_builder.dart';
import 'package:declarative_sqlite/src/builders/key_builder.dart';
import 'package:declarative_sqlite/src/builders/real_column_builder.dart';
import 'package:declarative_sqlite/src/builders/text_column_builder.dart';
import 'package:declarative_sqlite/src/schema/db_table.dart';

class TableBuilder {
  final String name;
  final List<ColumnBuilder> _columnBuilders = [];
  final List<KeyBuilder> _keyBuilders = [];

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

  DbTable build() {
    final columns = _columnBuilders.map((b) => b.build()).toList();
    final hlcColumns = <DbColumn>[];
    for (final column in columns) {
      if (column.isLww) {
        hlcColumns.add(
          DbColumn(
            name: '${column.name}__hlc',
            logicalType: 'hlc',
            type: 'TEXT',
            isNotNull: false, // Nullable to support partial inserts
            isParent: false,
            isLww: false,
          ),
        );
      }
    }

    final isSystemTable = name.startsWith('__');

    final systemColumns = isSystemTable
        ? <DbColumn>[]
        : [
            DbColumn(
              name: 'system_id',
              logicalType: 'guid',
              type: 'TEXT', // GUID
              isNotNull: true,
              defaultValue: '00000000-0000-0000-0000-000000000000',
              isParent: false,
              isLww: false,
            ),
            DbColumn(
              name: 'system_created_at',
              logicalType: 'hlc',
              type: 'TEXT', // HLC
              isNotNull: true,
              defaultValue: '000000000000000:000000000:000000000000000000000000000000000000', // HLC format: milliseconds(15):counter(9):nodeId(36)
              isParent: false,
              isLww: false,
            ),
            DbColumn(
              name: 'system_version',
              logicalType: 'hlc',
              type: 'TEXT', // HLC
              isNotNull: true,
              defaultValue: '000000000000000:000000000:000000000000000000000000000000000000', // HLC format: milliseconds(15):counter(9):nodeId(36)
              isParent: false,
              isLww: false,
            ),
          ];

    return DbTable(
      name: name,
      columns: [...systemColumns, ...columns, ...hlcColumns],
      keys: _keyBuilders.map((b) => b.build()).toList(),
    );
  }
}
