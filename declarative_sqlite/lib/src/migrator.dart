import 'package:sqflite_common/sqflite.dart';
import 'schema_builder.dart';
import 'table_builder.dart';

/// Handles migration and synchronization of database schemas.
/// 
/// Can create missing tables and modify existing ones to match a declared schema.
class SchemaMigrator {
  const SchemaMigrator();

  /// Executes the given schema against a SQLite database.
  /// 
  /// This will:
  /// - Create any missing tables
  /// - Create any missing indices
  /// - Note: Column modifications are not supported as they require complex migration logic
  /// 
  /// [database] The SQLite database instance
  /// [schema] The target schema to apply
  Future<void> migrate(Database database, SchemaBuilder schema) async {
    // Get existing table information
    final existingTables = await _getExistingTables(database);
    final existingIndices = await _getExistingIndices(database);

    // Process each table in the schema
    for (final table in schema.tables) {
      if (!existingTables.contains(table.name)) {
        // Create new table
        await _createTable(database, table);
      } else {
        // Table exists, check for missing indices
        await _createMissingIndices(database, table, existingIndices);
      }
    }
  }

  /// Gets a list of existing table names in the database
  Future<Set<String>> _getExistingTables(Database database) async {
    final result = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    );
    
    return result.map((row) => row['name'] as String).toSet();
  }

  /// Gets a list of existing index names in the database
  Future<Set<String>> _getExistingIndices(Database database) async {
    final result = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
    );
    
    return result.map((row) => row['name'] as String).toSet();
  }

  /// Creates a new table with all its indices
  Future<void> _createTable(Database database, TableBuilder table) async {
    // Create the table
    await database.execute(table.toSql());
    
    // Create all indices for this table
    for (final indexSql in table.indexSqlStatements()) {
      await database.execute(indexSql);
    }
  }

  /// Creates any missing indices for an existing table
  Future<void> _createMissingIndices(
    Database database, 
    TableBuilder table, 
    Set<String> existingIndices
  ) async {
    for (final index in table.indices) {
      if (!existingIndices.contains(index.name)) {
        await database.execute(index.toSql());
      }
    }
  }

  /// Validates that the schema can be safely applied.
  /// 
  /// Returns a list of validation errors, or empty list if valid.
  List<String> validateSchema(SchemaBuilder schema) {
    final errors = <String>[];
    
    // Check for empty tables
    for (final table in schema.tables) {
      if (table.columns.isEmpty) {
        errors.add('Table "${table.name}" has no columns');
      }
      
      // Check that all indexed columns exist
      for (final index in table.indices) {
        for (final columnName in index.columns) {
          if (!table.columns.any((col) => col.name == columnName)) {
            errors.add(
              'Index "${index.name}" references non-existent column "$columnName" in table "${table.name}"'
            );
          }
        }
      }
    }
    
    return errors;
  }

  /// Generates a preview of what migration actions would be performed.
  /// 
  /// This is useful for logging or user confirmation before applying changes.
  Future<MigrationPlan> planMigration(Database database, SchemaBuilder schema) async {
    final existingTables = await _getExistingTables(database);
    final existingIndices = await _getExistingIndices(database);
    
    final tablesToCreate = <String>[];
    final indicesToCreate = <String>[];
    
    for (final table in schema.tables) {
      if (!existingTables.contains(table.name)) {
        tablesToCreate.add(table.name);
        // All indices for new tables will be created
        indicesToCreate.addAll(table.indices.map((i) => i.name));
      } else {
        // Check for missing indices on existing tables
        for (final index in table.indices) {
          if (!existingIndices.contains(index.name)) {
            indicesToCreate.add(index.name);
          }
        }
      }
    }
    
    return MigrationPlan(
      tablesToCreate: tablesToCreate,
      indicesToCreate: indicesToCreate,
    );
  }
}

/// Represents a plan for database migration operations.
class MigrationPlan {
  const MigrationPlan({
    required this.tablesToCreate,
    required this.indicesToCreate,
  });

  /// Tables that will be created
  final List<String> tablesToCreate;
  
  /// Indices that will be created
  final List<String> indicesToCreate;
  
  /// Whether this migration plan has any operations
  bool get hasOperations => tablesToCreate.isNotEmpty || indicesToCreate.isNotEmpty;
  
  /// Whether this migration plan has no operations
  bool get isEmpty => !hasOperations;

  @override
  String toString() {
    if (isEmpty) {
      return 'MigrationPlan(no operations)';
    }
    
    final buffer = StringBuffer('MigrationPlan(');
    if (tablesToCreate.isNotEmpty) {
      buffer.write('tables to create: ${tablesToCreate.length}');
      if (indicesToCreate.isNotEmpty) {
        buffer.write(', ');
      }
    }
    if (indicesToCreate.isNotEmpty) {
      buffer.write('indices to create: ${indicesToCreate.length}');
    }
    buffer.write(')');
    
    return buffer.toString();
  }
}