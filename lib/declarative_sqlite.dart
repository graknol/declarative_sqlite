/// A declarative SQLite schema builder for Dart.
/// 
/// This library provides a fluent interface for defining database schemas
/// and automatically migrating SQLite databases to match the declared schema.
/// 
/// Example usage:
/// ```dart
/// import 'package:declarative_sqlite/declarative_sqlite.dart';
/// 
/// final schema = SchemaBuilder()
///   .table('users', (table) => table
///     .autoIncrementPrimaryKey('id')
///     .text('name').notNull()
///     .text('email').unique()
///     .integer('age'))
///   .table('posts', (table) => table
///     .autoIncrementPrimaryKey('id')
///     .text('title').notNull()
///     .text('content')
///     .integer('user_id').notNull()
///     .index('idx_user_id', 'user_id'));
/// 
/// // Apply to database
/// final migrator = SchemaMigrator();
/// await migrator.migrate(database, schema);
/// ```
library declarative_sqlite;

// Export all public APIs
export 'src/schema_builder.dart';
export 'src/table_builder.dart';
export 'src/column_builder.dart';
export 'src/index_builder.dart';
export 'src/data_types.dart';
export 'src/migrator.dart';
