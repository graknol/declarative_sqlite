import 'package:collection/collection.dart';
import 'package:declarative_sqlite/src/migration/schema_diff.dart';
import 'package:declarative_sqlite/src/schema/live_schema.dart';
import 'package:declarative_sqlite/src/schema/db_table.dart';
import 'package:declarative_sqlite/src/schema/schema.dart';

List<SchemaChange> diffSchemas(
    Schema declarativeSchema, LiveSchema liveSchema) {
  final changes = <SchemaChange>[];

  final declarativeTables = declarativeSchema.tables;
  final liveTables = liveSchema.tables;

  // Compare tables
  for (final declarativeTable in declarativeTables) {
    final liveTable =
        liveTables.firstWhereOrNull((t) => t.name == declarativeTable.name);
    if (liveTable == null) {
      changes.add(CreateTable(declarativeTable));
    } else {
      final columnChanges = _diffColumns(declarativeTable, liveTable);
      final keyChanges = _diffKeys(declarativeTable, liveTable);
      if (columnChanges.isNotEmpty || keyChanges.isNotEmpty) {
        changes.add(
            AlterTable(liveTable, declarativeTable, columnChanges, keyChanges));
      }
    }
  }

  for (final liveTable in liveTables) {
    if (!declarativeTables.any((t) => t.name == liveTable.name)) {
      changes.add(DropTable(liveTable));
    }
  }

  // Compare views
  final declarativeViews = declarativeSchema.views;
  final liveViews = liveSchema.views;

  for (final declarativeView in declarativeViews) {
    final liveView =
        liveViews.firstWhereOrNull((v) => v.name == declarativeView.name);
    if (liveView == null) {
      changes.add(CreateView(declarativeView));
    } else if (liveView.sql != declarativeView.definition) {
      changes.add(AlterView(liveView, declarativeView));
    }
  }

  for (final liveView in liveViews) {
    if (!declarativeViews.any((v) => v.name == liveView.name)) {
      changes.add(DropView(liveView));
    }
  }

  return changes;
}

List<ColumnChange> _diffColumns(DbTable declarativeTable, LiveTable liveTable) {
  final changes = <ColumnChange>[];
  final declarativeColumns = declarativeTable.columns;
  final liveColumns = liveTable.columns;

  for (final declarativeColumn in declarativeColumns) {
    final liveColumn =
        liveColumns.firstWhereOrNull((c) => c.name == declarativeColumn.name);
    if (liveColumn == null) {
      changes.add(AddColumn(declarativeColumn));
    } else {
      // A simple diff for demonstration. A real implementation would be more robust.
      if (liveColumn.type.toUpperCase() !=
              declarativeColumn.type.toUpperCase() ||
          liveColumn.isNotNull != declarativeColumn.isNotNull) {
        changes.add(AlterColumn(liveColumn, declarativeColumn));
      }
    }
  }

  for (final liveColumn in liveColumns) {
    if (!declarativeColumns.any((c) => c.name == liveColumn.name)) {
      changes.add(DropColumn(liveColumn));
    }
  }

  return changes;
}

List<KeyChange> _diffKeys(DbTable declarativeTable, LiveTable liveTable) {
  final changes = <KeyChange>[];
  final declarativeKeys = declarativeTable.keys;
  final liveKeys = liveTable.keys;

  for (final declarativeKey in declarativeKeys) {
    final liveKey = liveKeys.firstWhereOrNull(
        (k) => const ListEquality().equals(k.columns, declarativeKey.columns));
    if (liveKey == null) {
      changes.add(AddKey(declarativeKey));
    }
  }

  for (final liveKey in liveKeys) {
    if (!declarativeKeys
        .any((k) => const ListEquality().equals(k.columns, liveKey.columns))) {
      changes.add(DropKey(liveKey));
    }
  }

  return changes;
}

