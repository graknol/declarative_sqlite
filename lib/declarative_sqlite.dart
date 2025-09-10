/// A declarative SQLite schema builder for Dart.
/// 
/// This library provides a fluent interface for defining database schemas
/// and automatically migrating SQLite databases to match the declared schema.
/// It also includes a comprehensive data access layer for type-safe database operations.
/// 
/// ## Schema Definition Example
/// ```dart
/// import 'package:declarative_sqlite/declarative_sqlite.dart';
/// 
/// final schema = SchemaBuilder()
///   .table('users', (table) => table
///     .autoIncrementPrimaryKey('id')
///     .text('username', (col) => col.notNull().unique())
///     .text('email', (col) => col.notNull())
///     .integer('age', (col) => col.withDefaultValue(0))
///     .index('idx_username', ['username']))
///   .table('posts', (table) => table
///     .autoIncrementPrimaryKey('id')
///     .text('title', (col) => col.notNull())
///     .text('content')
///     .integer('user_id', (col) => col.notNull())
///     .index('idx_user_id', ['user_id']));
/// ```
/// 
/// ## Migration Example
/// ```dart
/// // Apply schema to database
/// final migrator = SchemaMigrator();
/// await migrator.migrate(database, schema);
/// ```
/// 
/// ## Data Access Layer Example
/// ```dart
/// // Create data access layer
/// final dataAccess = DataAccess(database: database, schema: schema);
/// 
/// // Insert a user
/// final userId = await dataAccess.insert('users', {
///   'username': 'alice',
///   'email': 'alice@example.com',
///   'age': 30,
/// });
/// 
/// // Get user by primary key
/// final user = await dataAccess.getByPrimaryKey('users', userId);
/// 
/// // Update specific columns
/// await dataAccess.updateByPrimaryKey('users', userId, {
///   'age': 31,
/// });
/// 
/// // Get users with conditions
/// final youngUsers = await dataAccess.getAllWhere('users',
///     where: 'age < ?', whereArgs: [25]);
/// ```
library declarative_sqlite;

// Export all public APIs
export 'src/schema_builder.dart';
export 'src/table_builder.dart';
export 'src/column_builder.dart';
export 'src/index_builder.dart';
export 'src/data_types.dart';
export 'src/migrator.dart';
export 'src/data_access.dart';
