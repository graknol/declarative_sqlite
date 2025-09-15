import 'package:declarative_sqlite/src/migration/schema_diff.dart';
import 'package:declarative_sqlite/src/schema/column.dart';
import 'package:declarative_sqlite/src/schema/key.dart';

List<String> generateMigrationScripts(List<SchemaChange> changes) {
  final scripts = <String>[];
  for (final change in changes) {
    if (change is CreateTable) {
      scripts.add(_generateCreateTableScript(change));
    } else if (change is DropTable) {
      scripts.add('DROP TABLE ${change.table.name};');
    } else if (change is AlterTable) {
      scripts.addAll(_generateAlterTableScripts(change));
    } else if (change is CreateView) {
      scripts
          .add('CREATE VIEW ${change.view.name} AS ${change.view.definition};');
    } else if (change is DropView) {
      scripts.add('DROP VIEW ${change.view.name};');
    } else if (change is AlterView) {
      scripts.add('DROP VIEW ${change.liveView.name};');
      scripts.add(
          'CREATE VIEW ${change.targetView.name} AS ${change.targetView.definition};');
    }
  }
  return scripts;
}

String _generateCreateTableScript(CreateTable change) {
  final table = change.table;
  final columns = table.columns.map(_generateColumnDefinition).join(', ');
  final primaryKeys = table.keys
      .where((k) => k.type == KeyType.primary)
      .map((k) => 'PRIMARY KEY (${k.columns.join(', ')})')
      .join(', ');
  final parts = [columns, if (primaryKeys.isNotEmpty) primaryKeys];
  return 'CREATE TABLE ${table.name} (${parts.join(', ')});';
}

String _generateColumnDefinition(Column column) {
  final parts = [
    column.name,
    column.type,
    if (column.isNotNull) 'NOT NULL',
  ];
  return parts.join(' ');
}

List<String> _generateAlterTableScripts(AlterTable change) {
  final scripts = <String>[];
  final addColumnChanges = change.columnChanges.whereType<AddColumn>().toList();
  final dropColumnChanges =
      change.columnChanges.whereType<DropColumn>().toList();

  if (dropColumnChanges.isNotEmpty) {
    // Recreate table if columns are dropped
    final newTable = change.targetTable;
    final oldTable = change.liveTable;
    final tempTableName = 'old_${oldTable.name}';
    final keptColumns = newTable.columns.map((c) => c.name).toList();

    // 1. Rename old table
    scripts.add('ALTER TABLE ${oldTable.name} RENAME TO $tempTableName;');

    // 2. Create new table with original name
    scripts.add(_generateCreateTableScript(CreateTable(newTable)));

    // 3. Copy data from old table to new table
    scripts.add(
        'INSERT INTO ${newTable.name} (${keptColumns.join(', ')}) SELECT ${keptColumns.join(', ')} FROM $tempTableName;');

    // 4. Drop old table
    scripts.add('DROP TABLE $tempTableName;');
  } else {
    // Only handle adding columns if no columns are dropped
    for (final columnChange in addColumnChanges) {
      final columnDef = _generateColumnDefinition(columnChange.column);
      scripts
          .add('ALTER TABLE ${change.liveTable.name} ADD COLUMN $columnDef;');
    }
  }

  // NOTE: This implementation assumes that if any column is dropped, the table
  // is recreated. If columns are only added, it uses ALTER TABLE ADD COLUMN.
  // More complex scenarios like altering column types or constraints are not
  // yet handled.
  return scripts;
}
