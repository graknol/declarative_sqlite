/// A Dart package for declaratively creating SQLite tables, views, and automatically migrating them.
/// 
/// This library provides a fluent interface for defining database schemas
/// with tables, views, columns, indices, constraints, and **relationships**. It automatically 
/// migrates SQLite databases to match the declared schema and includes a 
/// comprehensive data access layer for type-safe database operations.
/// 
/// ## Key Features
/// - **Declarative Schema Definition**: Use a fluent builder pattern to define your database schema
/// - **Relationship Modeling**: Define one-to-many and many-to-many relationships without foreign keys
/// - **Cascading Operations**: Delete parent records with automatic child cleanup following relationship tree
/// - **Proxy Queries**: Navigate relationships without manual joins or complex WHERE clauses
/// - **SQL Views Support**: Create views with complex queries, joins, aggregations, and subqueries  
/// - **Automatic Migration**: Create missing tables, views, and indices automatically
/// - **Data Access Abstraction**: Type-safe CRUD operations with schema metadata integration
/// - **Bulk Data Loading**: Efficiently load large datasets with flexible validation and error handling
/// - **SQLite Data Types**: Full support for SQLite affinities (INTEGER, REAL, TEXT, BLOB)
/// - **Constraints**: Support for Primary Key, Unique, and Not Null constraints
/// - **Indices**: Single-column and composite indices with unique option
/// - **Type Safe**: Built with null safety and immutable builders
/// 
/// ## Relationship Modeling Example
/// ```dart
/// import 'package:declarative_sqlite/declarative_sqlite.dart';
/// 
/// final schema = SchemaBuilder()
///   .table('users', (table) => table
///     .autoIncrementPrimaryKey('id')
///     .text('username', (col) => col.notNull().unique())
///     .text('email', (col) => col.notNull()))
///   .table('posts', (table) => table
///     .autoIncrementPrimaryKey('id')
///     .text('title', (col) => col.notNull())
///     .text('content')
///     .integer('user_id', (col) => col.notNull()))
///   .table('categories', (table) => table
///     .autoIncrementPrimaryKey('id')
///     .text('name', (col) => col.notNull().unique()))
///   .table('post_categories', (table) => table
///     .autoIncrementPrimaryKey('id')
///     .integer('post_id', (col) => col.notNull())
///     .integer('category_id', (col) => col.notNull()))
///   // Define relationships without database foreign keys
///   .oneToMany('user_posts', 'users', 'posts',
///       parentColumn: 'id', childColumn: 'user_id',
///       onDelete: CascadeAction.cascade)
///   .manyToMany('post_categories_rel', 'posts', 'categories', 'post_categories',
///       parentColumn: 'id', childColumn: 'id',
///       junctionParentColumn: 'post_id', junctionChildColumn: 'category_id');
/// 
/// // Create relationship-aware data access layer
/// final dataAccess = RelatedDataAccess(database: database, schema: schema);
/// 
/// // Navigate relationships without manual joins
/// final userPosts = await dataAccess.getRelated('user_posts', userId);
/// 
/// // Manage many-to-many relationships  
/// await dataAccess.linkManyToMany('post_categories_rel', postId, categoryId);
/// 
/// // Delete with cascading cleanup (deletes user, posts, comments, etc.)
/// await dataAccess.deleteWithChildren('users', userId);
/// ```
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
export 'src/relationship_builder.dart';
export 'src/data_types.dart';
export 'src/migrator.dart';
export 'src/data_access.dart';
export 'src/related_data_access.dart';
export 'src/lww_types.dart';
export 'src/lww_data_access.dart';
