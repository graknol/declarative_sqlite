import 'dart:convert';
import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:declarative_sqlite/src/migration/schema_diff.dart';
import 'package:declarative_sqlite/src/schema/db_key.dart';

List<String> generateMigrationScripts(List<SchemaChange> changes) {
  developer.log('🔄 Starting migration script generation with ${changes.length} schema changes', name: 'Migration');
  
  final scripts = <String>[];
  for (int i = 0; i < changes.length; i++) {
    final change = changes[i];
    developer.log('📝 Processing change ${i + 1}/${changes.length}: ${change.runtimeType}', name: 'Migration');
    
    if (change is CreateTable) {
      developer.log('➕ Creating table: ${change.table.name} with ${change.table.columns.length} columns', name: 'Migration');
      final tableScripts = _generateCreateTableScripts(change);
      scripts.addAll(tableScripts);
      developer.log('  └─ Generated ${tableScripts.length} scripts for table creation', name: 'Migration');
    } else if (change is DropTable) {
      developer.log('🗑️ Dropping table: ${change.table.name}', name: 'Migration');
      scripts.add('DROP TABLE ${change.table.name};');
    } else if (change is AlterTable) {
      developer.log('🔧 Altering table: ${change.liveTable.name} → ${change.targetTable.name}', name: 'Migration');
      developer.log('  └─ Column changes: ${change.columnChanges.length}, Key changes: ${change.keyChanges.length}', name: 'Migration');
      final alterScripts = _generateAlterTableScripts(change);
      scripts.addAll(alterScripts);
      developer.log('  └─ Generated ${alterScripts.length} scripts for table alteration', name: 'Migration');
    } else if (change is CreateView) {
      developer.log('👁️ Creating view: ${change.view.name}', name: 'Migration');
      scripts.add('CREATE VIEW ${change.view.name} AS ${change.view.definition};');
    } else if (change is DropView) {
      developer.log('🗑️ Dropping view: ${change.view.name}', name: 'Migration');
      scripts.add('DROP VIEW ${change.view.name};');
    } else if (change is AlterView) {
      developer.log('🔧 Altering view: ${change.liveView.name} → ${change.targetView.name}', name: 'Migration');
      scripts.add('DROP VIEW ${change.liveView.name};');
      scripts.add('CREATE VIEW ${change.targetView.name} AS ${change.targetView.definition};');
      developer.log('  └─ Generated 2 scripts (drop + create) for view alteration', name: 'Migration');
    } else {
      developer.log('⚠️ Unknown schema change type: ${change.runtimeType}', name: 'Migration');
    }
  }
  
  developer.log('✅ Migration script generation complete. Total scripts: ${scripts.length}', name: 'Migration');
  if (scripts.isNotEmpty) {
    developer.log('📋 Generated SQL scripts:', name: 'Migration');
    for (int i = 0; i < scripts.length; i++) {
      developer.log('  ${i + 1}. ${scripts[i]}', name: 'Migration');
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
  
  // Log table details
  developer.log('    📊 Table details: ${table.columns.length} columns, ${table.keys.length} keys', name: 'Migration');
  for (final column in table.columns) {
    developer.log('      • ${column.name} (${column.logicalType}${column.isNotNull ? ', NOT NULL' : ''}${column.defaultValue != null ? ', default: ${column.defaultValue}' : ''})', name: 'Migration');
  }
  
  scripts.add(_generateCreateTableScript(change));

  final indexKeys = table.keys.where((k) => k.type == KeyType.indexed);
  final uniqueKeys = table.keys.where((k) => k.type == KeyType.unique);
  
  if (indexKeys.isNotEmpty) {
    developer.log('    📊 Creating ${indexKeys.length} indexes for table ${table.name}', name: 'Migration');
  }
  
  if (uniqueKeys.isNotEmpty) {
    developer.log('    📊 Creating ${uniqueKeys.length} unique constraints for table ${table.name}', name: 'Migration');
  }
  
  // Create regular indexes
  for (final key in indexKeys) {
    var indexName = 'idx_${table.name}_${key.columns.join('_')}';
    if (indexName.length > 62) {
      final hash =
          sha1.convert(utf8.encode(indexName)).toString().substring(0, 10);
      indexName = 'idx_${table.name}_$hash';
      developer.log('      • Index name truncated: $indexName (${key.columns.join(', ')})', name: 'Migration');
    } else {
      developer.log('      • Index: $indexName (${key.columns.join(', ')})', name: 'Migration');
    }
    scripts.add(
        'CREATE INDEX $indexName ON ${table.name} (${key.columns.join(', ')});');
  }
  
  // Create unique indexes
  for (final key in uniqueKeys) {
    var indexName = 'uniq_${table.name}_${key.columns.join('_')}';
    if (indexName.length > 62) {
      final hash =
          sha1.convert(utf8.encode(indexName)).toString().substring(0, 10);
      indexName = 'uniq_${table.name}_$hash';
      developer.log('      • Unique index name truncated: $indexName (${key.columns.join(', ')})', name: 'Migration');
    } else {
      developer.log('      • Unique index: $indexName (${key.columns.join(', ')})', name: 'Migration');
    }
    scripts.add(
        'CREATE UNIQUE INDEX $indexName ON ${table.name} (${key.columns.join(', ')});');
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

  // Log detailed change breakdown
  developer.log('    📊 Alter table breakdown:', name: 'Migration');
  developer.log('      • Add columns: ${addColumnChanges.length}', name: 'Migration');
  if (addColumnChanges.isNotEmpty) {
    for (final add in addColumnChanges) {
      developer.log('        + ${add.column.name} (${add.column.logicalType})', name: 'Migration');
    }
  }
  developer.log('      • Drop columns: ${dropColumnChanges.length}', name: 'Migration');
  if (dropColumnChanges.isNotEmpty) {
    for (final drop in dropColumnChanges) {
      developer.log('        - ${drop.column.name}', name: 'Migration');
    }
  }
  developer.log('      • Alter columns: ${alterColumnChanges.length}', name: 'Migration');
  if (alterColumnChanges.isNotEmpty) {
    for (final alter in alterColumnChanges) {
      developer.log('        ~ ${alter.liveColumn.name}: ${alter.liveColumn.type} → ${alter.targetColumn.logicalType}', name: 'Migration');
    }
  }
  developer.log('      • Key changes: ${keyChanges.length}', name: 'Migration');

  if (dropColumnChanges.isNotEmpty ||
      alterColumnChanges.isNotEmpty ||
      keyChanges.isNotEmpty) {
    developer.log('    ⚠️ Complex changes detected - will recreate table ${change.liveTable.name}', name: 'Migration');
    // Recreate table if columns are dropped or altered, or if keys/references change
    final newTable = change.targetTable;
    final oldTable = change.liveTable;
    final tempTableName = 'old_${oldTable.name}';
    final keptColumns = newTable.columns.map((c) => c.name).toList();

    developer.log('    🔄 Table recreation steps:', name: 'Migration');
    developer.log('      1️⃣ Rename ${oldTable.name} → $tempTableName', name: 'Migration');
    
    // 1. Rename old table
    scripts.add('ALTER TABLE ${oldTable.name} RENAME TO $tempTableName;');

    developer.log('      2️⃣ Create new ${newTable.name} with ${newTable.columns.length} columns', name: 'Migration');
    
    // 2. Create new table with original name
    scripts.addAll(_generateCreateTableScripts(CreateTable(newTable)));

    developer.log('      3️⃣ Prepare data migration for ${keptColumns.length} columns', name: 'Migration');
    
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

    developer.log('      4️⃣ Copy data: SELECT $selectColumns FROM $tempTableName', name: 'Migration');
    
    // 3. Copy data from old table to new table
    scripts.add(
        'INSERT INTO ${newTable.name} (${keptColumns.join(', ')}) SELECT $selectColumns FROM $tempTableName;');

    developer.log('      5️⃣ Drop temporary table: $tempTableName', name: 'Migration');
    
    // 4. Drop old table
    scripts.add('DROP TABLE $tempTableName;');
  } else {
    developer.log('    ✨ Simple column additions - using ALTER TABLE ADD COLUMN', name: 'Migration');
    
    // Only handle adding columns if no columns are dropped, altered, or keys/references change
    for (final columnChange in addColumnChanges) {
      final columnDef = columnChange.column.toSql();
      developer.log('      + Adding column: ${columnChange.column.name} (${columnChange.column.logicalType})', name: 'Migration');
      scripts
          .add('ALTER TABLE ${change.liveTable.name} ADD COLUMN $columnDef;');
    }
  }

  // NOTE: This implementation assumes that if any column is dropped or altered,
  // the table is recreated. If columns are only added, it uses ALTER TABLE ADD
  // COLUMN.
  return scripts;
}
