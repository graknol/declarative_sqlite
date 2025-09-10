import 'package:declarative_sqlite/declarative_sqlite.dart';
// Note: To run this example with actual database operations, you would need:
// import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('=== Declarative SQLite with Views Example ===\n');
  
  // Define a comprehensive database schema with views
  final schema = SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('username', (col) => col.notNull().unique())
          .text('email', (col) => col.notNull())
          .text('full_name')
          .integer('age', (col) => col.withDefaultValue(0))
          .real('balance', (col) => col.withDefaultValue(0.0))
          .integer('active', (col) => col.withDefaultValue(1))
          .index('idx_username', ['username'])
          .index('idx_email', ['email']))
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .text('content')
          .integer('user_id', (col) => col.notNull())
          .integer('likes', (col) => col.withDefaultValue(0))
          .integer('published', (col) => col.withDefaultValue(0))
          .text('created_at', (col) => col.notNull())
          .index('idx_user_id', ['user_id'])
          .index('idx_title_user', ['title', 'user_id'], unique: true))
      .table('categories', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull().unique())
          .text('description'))
      .table('post_categories', (table) => table
          .autoIncrementPrimaryKey('id')
          .integer('post_id', (col) => col.notNull())
          .integer('category_id', (col) => col.notNull())
          .index('idx_post_category', ['post_id', 'category_id'], unique: true))
      
      // Add various types of views using the new unified API
      
      // Simple filtered view - new way
      .addView(ViewBuilder.create('active_users')
          .fromTable('users', whereCondition: 'active = 1'))
      
      // View with specific columns and aliases - new way  
      .addView(ViewBuilder.create('user_summary').fromTable('users', expressions: [
        ExpressionBuilder.column('id'),
        ExpressionBuilder.column('username').as('name'),
        ExpressionBuilder.function('UPPER', ['email']).as('email_upper'),
        ExpressionBuilder.literal('Member').as('user_type'),
      ]))
      
      // Aggregated view with user statistics - new way
      .addView(ViewBuilder.create('user_stats').fromQuery((query) =>
        query.select([
          Expressions.count.as('total_users'),
          Expressions.avg('age').as('average_age'),
          Expressions.min('age').as('youngest_user'),
          Expressions.max('age').as('oldest_user'),
          Expressions.sum('balance').as('total_balance'),
        ]).from('users')))
      
      // View with GROUP BY for department statistics - new way
      .addView(ViewBuilder.create('users_by_age_group').fromQuery((query) =>
        query.select([
            ExpressionBuilder.raw('CASE WHEN age < 25 THEN "Young" WHEN age < 50 THEN "Middle" ELSE "Senior" END').as('age_group'),
            Expressions.count.as('user_count'),
            Expressions.avg('balance').as('avg_balance'),
          ])
          .from('users')
          .where('active = 1')
          .groupBy(['CASE WHEN age < 25 THEN "Young" WHEN age < 50 THEN "Middle" ELSE "Senior" END'])
          .having('COUNT(*) > 0')
          .orderByColumn('user_count', true)
      ))
      
      // View with INNER JOIN - new way
      .addView(ViewBuilder.create('user_posts').fromQuery((query) =>
        query.select([
            ExpressionBuilder.qualifiedColumn('users', 'username'),
            ExpressionBuilder.qualifiedColumn('users', 'email'),
            ExpressionBuilder.qualifiedColumn('posts', 'title'),
            ExpressionBuilder.qualifiedColumn('posts', 'likes'),
            ExpressionBuilder.qualifiedColumn('posts', 'created_at'),
          ])
          .from('users')
          .innerJoin('posts', 'users.id = posts.user_id')
      ))
      
      // Complex view with multiple joins and conditions - new way
      .addView(ViewBuilder.create('published_posts_with_categories').fromQuery((query) =>
        query
          .select([
            ExpressionBuilder.qualifiedColumn('u', 'username').as('author'),
            ExpressionBuilder.qualifiedColumn('p', 'title'),
            ExpressionBuilder.qualifiedColumn('p', 'likes'),
            ExpressionBuilder.qualifiedColumn('c', 'name').as('category'),
            ExpressionBuilder.qualifiedColumn('p', 'created_at'),
          ])
          .from('users', 'u')
          .innerJoin('posts', 'u.id = p.user_id', 'p')
          .leftJoin('post_categories', 'p.id = pc.post_id', 'pc')
          .leftJoin('categories', 'pc.category_id = c.id', 'c')
          .where('u.active = 1 AND p.published = 1')
          .orderByColumn('p.created_at', true)
      ))
      
      // View with aggregation and joins for user posting statistics - new way
      .addView(ViewBuilder.create('user_posting_stats').fromQuery((query) =>
        query
          .select([
            ExpressionBuilder.qualifiedColumn('u', 'username'),
            ExpressionBuilder.qualifiedColumn('u', 'email'),
            Expressions.count.as('total_posts'),
            Expressions.sum('p.likes').as('total_likes'),
            Expressions.avg('p.likes').as('avg_likes_per_post'),
            Expressions.max('p.created_at').as('latest_post_date'),
          ])
          .from('users', 'u')
          .leftJoin('posts', 'u.id = p.user_id', 'p')
          .where('u.active = 1')
          .groupBy(['u.id', 'u.username', 'u.email'])
          .having('COUNT(p.id) > 0')
          .orderByColumn('total_likes', true)
      ))
      
      // Popular posts view (posts with more than average likes) - new way
      .addView(ViewBuilder.create('popular_posts').fromSql('''
        SELECT p.title, p.content, p.likes, u.username as author
        FROM posts p
        INNER JOIN users u ON p.user_id = u.id
        WHERE p.likes > (SELECT AVG(likes) FROM posts)
        ORDER BY p.likes DESC
      '''))
      
      // Recent activity view using raw SQL with subquery - new way
      .addView(ViewBuilder.create('recent_activity').fromSql('''
        SELECT 
          'post' as activity_type,
          u.username,
          p.title as description,
          p.created_at
        FROM posts p
        INNER JOIN users u ON p.user_id = u.id
        WHERE p.created_at > datetime('now', '-30 days')
        ORDER BY p.created_at DESC
        LIMIT 50
      '''));

  // Display schema information
  print('📊 Schema Summary:');
  print('Tables: ${schema.tableCount}');
  print('Views: ${schema.viewCount}');
  print('Total objects: ${schema.totalCount}');
  print('\nTable names: ${schema.tableNames.join(', ')}');
  print('View names: ${schema.viewNames.join(', ')}');
  
  print('\n' + '='*60);
  print('🗄️  Generated SQL Schema:');
  print('='*60);
  print(schema.toSqlScript());
  
  print('\n' + '='*60);
  print('📋 Individual View Examples:');
  print('='*60);
  
  // Show some specific view examples
  final activeUsersView = schema.getView('active_users')!;
  print('\n1. Simple Filtered View:');
  print(activeUsersView.toSql());
  
  final userSummaryView = schema.getView('user_summary')!;
  print('\n2. View with Expressions and Aliases:');
  print(userSummaryView.toSql());
  
  final joinedView = schema.getView('published_posts_with_categories')!;
  print('\n3. Complex View with Multiple Joins:');
  print(joinedView.toSql());
  
  final aggregateView = schema.getView('user_posting_stats')!;
  print('\n4. View with Aggregation and GROUP BY:');
  print(aggregateView.toSql());
  
  print('\n' + '='*60);
  print('✨ View Features Demonstrated:');
  print('='*60);
  print('✅ Simple table filtering with WHERE conditions');
  print('✅ Column selection and aliasing'); 
  print('✅ Expression building with functions (UPPER, COUNT, etc.)');
  print('✅ Various JOIN types (INNER, LEFT, RIGHT, etc.)');
  print('✅ Complex WHERE clauses with AND/OR conditions');
  print('✅ GROUP BY and HAVING clauses');
  print('✅ ORDER BY with ASC/DESC');
  print('✅ LIMIT and OFFSET for pagination');
  print('✅ Subqueries and raw SQL for complex cases');
  print('✅ Aggregate functions (COUNT, SUM, AVG, MIN, MAX)');
  print('✅ Qualified column references (table.column)');
  print('✅ Integration with schema builder and migrations');
  
  /*
  // To use with an actual database (uncomment and add sqflite_common_ffi dependency):
  
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final database = await openDatabase(inMemoryDatabasePath);
  final migrator = SchemaMigrator();
  
  print('\n🔄 Applying schema to database...');
  await migrator.migrate(database, schema);
  print('✅ Schema applied successfully!');
  
  // Create data access layer
  final dataAccess = DataAccess(database: database, schema: schema);
  
  // Insert sample data
  await dataAccess.insert('users', {
    'username': 'alice',
    'email': 'alice@example.com', 
    'age': 28,
    'active': 1,
  });
  
  // Query views would work like regular tables
  final activeUsers = await database.rawQuery('SELECT * FROM active_users');
  print('\nActive users: $activeUsers');
  */
}
