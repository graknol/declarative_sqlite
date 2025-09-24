import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:declarative_sqlite/src/migration/schema_diff.dart';
import 'package:declarative_sqlite/src/schema/db_key.dart';

List<String> generateMigrationScripts(List<SchemaChange> changes) {
  final scripts = <String>[];
  for (final change in changes) {
    if (change is CreateTable) {
      scripts.addAll(_generateCreateTableScripts(change));
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
  final columns = table.columns.map((c)=>c.toSql()).join(', ');
  final primaryKeys = table.keys
      .where((k) => k.type == KeyType.primary)
      .map((k) => 'PRIMARY KEY (${k.columns.join(', ')})')
      .join(', ');

  final parts = [
    columns,
    if (primaryKeys.isNotEmpty) primaryKeys,
  ];
  return 'CREATE TABLE ${table.name} (${parts.where((p) => p.isNotEmpty).join(', ')});';
}

List<String> _generateCreateTableScripts(CreateTable change) {
  final scripts = <String>[];
  final table = change.table;
  scripts.add(_generateCreateTableScript(change));

  final indexKeys = table.keys.where((k) => k.type == KeyType.indexed);
  for (final key in indexKeys) {
    var indexName = 'idx_${table.name}_${key.columns.join('_')}';
    if (indexName.length > 62) {
      final hash =
          sha1.convert(utf8.encode(indexName)).toString().substring(0, 10);
      indexName = 'idx_${table.name}_$hash';
    }
    scripts.add(
        'CREATE INDEX $indexName ON ${table.name} (${key.columns.join(', ')});');
  }
  return scripts;
}

List<String> _generateAlterTableScripts(AlterTable change) {
  final scripts = <String>[];
  final addColumnChanges = change.columnChanges.whereType<AddColumn>().toList();
  final dropColumnChanges =
      change.columnChanges.whereType<DropColumn>().toList();
  final alterColumnChanges =
      change.columnChanges.whereType<AlterColumn>().toList();
  final keyChanges = change.keyChanges;

  if (dropColumnChanges.isNotEmpty ||
      alterColumnChanges.isNotEmpty ||
      keyChanges.isNotEmpty) {
    // Recreate table if columns are dropped or altered, or if keys/references change
    final newTable = change.targetTable;
    final oldTable = change.liveTable;
    final tempTableName = 'old_${oldTable.name}';
    final keptColumns = newTable.columns.map((c) => c.name).toList();

    // 1. Rename old table
    scripts.add('ALTER TABLE ${oldTable.name} RENAME TO $tempTableName;');

    // 2. Create new table with original name
    scripts.addAll(_generateCreateTableScripts(CreateTable(newTable)));

    final selectColumns = newTable.columns.map((newCol) {
      final oldCol =
          oldTable.columns.firstWhereOrNull((c) => c.name == newCol.name);
      if (oldCol == null) {
        if (newCol.isNotNull) {
          final defaultValue = newCol.defaultValue;
          if (defaultValue != null) {
            final value =
                defaultValue is String ? "'$defaultValue'" : defaultValue;
            return '$value AS ${newCol.name}';
          }
        }
      } else {
        // The column exists in the old table, so we can select it.
        // We need to handle the case where a column is now NOT NULL,
        // but was previously nullable.
        if (newCol.isNotNull && !oldCol.isNotNull) {
          final defaultValue = newCol.defaultValue;
          final value =
              defaultValue is String ? "'$defaultValue'" : defaultValue;
          return 'IFNULL(${newCol.name}, $value) AS ${newCol.name}';
        }
      }
      return newCol.name;
    }).join(', ');

    // 3. Copy data from old table to new table
    scripts.add(
        'INSERT INTO ${newTable.name} (${keptColumns.join(', ')}) SELECT $selectColumns FROM $tempTableName;');

    // 4. Drop old table
    scripts.add('DROP TABLE $tempTableName;');
  } else {
    // Only handle adding columns if no columns are dropped, altered, or keys/references change
    for (final columnChange in addColumnChanges) {
      final columnDef = columnChange.column.toSql();
      scripts
          .add('ALTER TABLE ${change.liveTable.name} ADD COLUMN $columnDef;');
    }
  }

  // NOTE: This implementation assumes that if any column is dropped or altered,
  // the table is recreated. If columns are only added, it uses ALTER TABLE ADD
  // COLUMN.
  return scripts;
}
