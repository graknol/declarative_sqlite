import 'package:collection/collection.dart';
import 'package:declarative_sqlite/src/migration/schema_diff.dart';
import 'package:declarative_sqlite/src/schema/live_schema.dart';
import 'package:declarative_sqlite/src/schema/table.dart';
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
      if (columnChanges.isNotEmpty) {
        changes.add(AlterTable(liveTable, declarativeTable, columnChanges));
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

List<ColumnChange> _diffColumns(Table declarativeTable, LiveTable liveTable) {
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
