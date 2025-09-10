/// A declarative SQLite schema builder for Dart.
/// 
/// This library provides a fluent interface for defining database schemas
/// with tables, views, columns, indices, and constraints. It automatically 
/// migrates SQLite databases to match the declared schema and includes a 
/// comprehensive data access layer for type-safe database operations.
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
///     .integer('active', (col) => col.withDefaultValue(1))
///     .index('idx_username', ['username']))
///   .table('posts', (table) => table
///     .autoIncrementPrimaryKey('id')
///     .text('title', (col) => col.notNull())
///     .text('content')
///     .integer('user_id', (col) => col.notNull())
///     .index('idx_user_id', ['user_id']))
///   .addView(Views.filtered('active_users', 'users', 'active = 1'))
///   .addView(Views.joined('user_posts', 'users', 'posts', 
///     'users.id = posts.user_id', [
///       ExpressionBuilder.qualifiedColumn('users', 'username'),
///       ExpressionBuilder.qualifiedColumn('posts', 'title'),
///       ExpressionBuilder.qualifiedColumn('posts', 'created_at'),
///     ]));
/// ```
/// 
/// ## View Examples
/// ```dart
/// // Simple filtered view - unified API
/// final activeUsersView = ViewBuilder.create('active_users')
///   .fromTable('users', whereCondition: 'active = 1');
/// 
/// // View with specific columns and aliases - unified API
/// final userSummaryView = ViewBuilder.create('user_summary')
///   .fromTable('users', expressions: [
///     ExpressionBuilder.column('id'),
///     ExpressionBuilder.column('username').as('name'),
///     ExpressionBuilder.function('UPPER', ['email']).as('email_upper'),
///   ]);
/// 
/// // Complex view with joins and aggregation - unified API
/// final userStatsView = ViewBuilder.create('user_post_stats')
///   .fromQuery((query) => query
///     .select([
///       ExpressionBuilder.qualifiedColumn('u', 'username'),
///       Expressions.count.as('post_count'),
///       Expressions.max('p.created_at').as('latest_post'),
///     ])
///     .from('users', 'u')
///     .leftJoin('posts', 'u.id = p.user_id', 'p')
///     .groupBy(['u.id', 'u.username'])
///     .having('COUNT(p.id) > 0')
///     .orderByColumn('post_count', true)
///   );
/// 
/// // View from raw SQL for complex cases - unified API
/// final customView = ViewBuilder.create('recent_activity')
///   .fromSql('''
///     SELECT u.username, p.title, p.created_at
///     FROM users u
///     INNER JOIN posts p ON u.id = p.user_id
///     WHERE p.created_at > datetime('now', '-7 days')
///     ORDER BY p.created_at DESC
///   ''');
/// ```
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
export 'src/view_builder.dart';
export 'src/query_builder.dart';
export 'src/expression_builder.dart';
export 'src/join_builder.dart';
export 'src/data_types.dart';
export 'src/migrator.dart';
export 'src/data_access.dart';
