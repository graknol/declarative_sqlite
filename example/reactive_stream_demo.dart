import 'dart:async';
import 'dart:io';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Comprehensive demo showcasing the sophisticated dependency-based 
/// stream change detection system for reactive database applications
void main() async {
  print('🎯 Reactive Stream Demo - Dependency-Based Change Detection\n');
  print('Demonstrating sophisticated, robust dependency-based change detection for streams\n');
  
  // Initialize FFI for desktop Dart
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final demo = ReactiveStreamDemo();
  await demo.runDemo();
}

class ReactiveStreamDemo {
  late Database database;
  late DataAccess dataAccess;
  late ReactiveDataAccess reactiveDataAccess;
  late SchemaBuilder schema;
  
  final streamListeners = <StreamSubscription>[];
  
  Future<void> runDemo() async {
    await _initializeDatabase();
    
    print('📊 Database initialized with comprehensive schema\n');
    
    // Demonstrate different types of dependencies
    await _demonstrateWholeTableDependencies();
    await _demonstrateColumnWiseDependencies();
    await _demonstrateWhereClauseDependencies();
    await _demonstrateRelatedTableDependencies();
    await _demonstrateAggregateStreamDependencies();
    await _showDependencyStatistics();
    
    // Clean up
    await _cleanup();
    
    print('\n✅ Reactive stream demo completed successfully!');
    print('📚 This demonstrates the power of dependency-based change detection');
    print('   for building highly efficient reactive database applications.');
  }
  
  Future<void> _initializeDatabase() async {
    // Create comprehensive schema for testing dependencies
    schema = SchemaBuilder()
      // Users table
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('username', (col) => col.notNull().unique())
          .text('email', (col) => col.notNull())
          .integer('age')
          .text('status', (col) => col.withDefaultValue('active'))
          .text('created_at', (col) => col.notNull())
          .index('idx_users_status', ['status'])
          .index('idx_users_age', ['age']))
      
      // Posts table
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .text('content')
          .integer('user_id', (col) => col.notNull())
          .text('category', (col) => col.withDefaultValue('general'))
          .integer('likes', (col) => col.withDefaultValue(0))
          .text('created_at', (col) => col.notNull())
          .index('idx_posts_user', ['user_id'])
          .index('idx_posts_category', ['category'])
          .index('idx_posts_likes', ['likes']))
      
      // Comments table
      .table('comments', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('content', (col) => col.notNull())
          .integer('post_id', (col) => col.notNull())
          .integer('user_id', (col) => col.notNull())
          .text('created_at', (col) => col.notNull())
          .index('idx_comments_post', ['post_id'])
          .index('idx_comments_user', ['user_id']))
      
      // Categories table
      .table('categories', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull().unique())
          .text('description')
          .integer('post_count', (col) => col.withDefaultValue(0)))
      
      // Define relationships
      .oneToMany('users', 'posts',
          parentColumns: ['id'], childColumns: ['user_id'],
          onDelete: CascadeAction.cascade)
      .oneToMany('posts', 'comments',
          parentColumns: ['id'], childColumns: ['post_id'],
          onDelete: CascadeAction.cascade)
      .oneToMany('users', 'comments',
          parentColumns: ['id'], childColumns: ['user_id'],
          onDelete: CascadeAction.cascade);
    
    // Open in-memory database
    database = await openDatabase(':memory:');
    
    // Apply schema
    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);
    
    // Create data access layers
    dataAccess = await DataAccess.create(database: database, schema: schema);
    reactiveDataAccess = ReactiveDataAccess(dataAccess: dataAccess, schema: schema);
    
    // Insert sample data
    await _insertSampleData();
  }
  
  Future<void> _insertSampleData() async {
    final now = DateTime.now().toIso8601String();
    
    // Insert users
    final userId1 = await dataAccess.insert('users', {
      'username': 'alice',
      'email': 'alice@example.com',
      'age': 25,
      'status': 'active',
      'created_at': now,
    });
    
    final userId2 = await dataAccess.insert('users', {
      'username': 'bob',
      'email': 'bob@example.com',
      'age': 30,
      'status': 'active',
      'created_at': now,
    });
    
    final userId3 = await dataAccess.insert('users', {
      'username': 'charlie',
      'email': 'charlie@example.com',
      'age': 22,
      'status': 'inactive',
      'created_at': now,
    });
    
    // Insert posts
    final postId1 = await dataAccess.insert('posts', {
      'title': 'Introduction to Reactive Streams',
      'content': 'Reactive streams provide a powerful way to handle data changes...',
      'user_id': userId1,
      'category': 'programming',
      'likes': 15,
      'created_at': now,
    });
    
    final postId2 = await dataAccess.insert('posts', {
      'title': 'Database Dependencies Explained',
      'content': 'Understanding how data dependencies work is crucial...',
      'user_id': userId2,
      'category': 'database',
      'likes': 8,
      'created_at': now,
    });
    
    final postId3 = await dataAccess.insert('posts', {
      'title': 'Getting Started with Flutter',
      'content': 'Flutter makes building beautiful apps easy...',
      'user_id': userId1,
      'category': 'mobile',
      'likes': 25,
      'created_at': now,
    });
    
    // Insert comments
    await dataAccess.insert('comments', {
      'content': 'Great article! Very informative.',
      'post_id': postId1,
      'user_id': userId2,
      'created_at': now,
    });
    
    await dataAccess.insert('comments', {
      'content': 'I learned a lot from this. Thanks!',
      'post_id': postId1,
      'user_id': userId3,
      'created_at': now,
    });
    
    await dataAccess.insert('comments', {
      'content': 'Could you provide more examples?',
      'post_id': postId2,
      'user_id': userId1,
      'created_at': now,
    });
    
    // Insert categories
    await dataAccess.insert('categories', {
      'name': 'Programming',
      'description': 'Software development topics',
      'post_count': 1,
    });
    
    await dataAccess.insert('categories', {
      'name': 'Database',
      'description': 'Database design and optimization',
      'post_count': 1,
    });
    
    await dataAccess.insert('categories', {
      'name': 'Mobile',
      'description': 'Mobile app development',
      'post_count': 1,
    });
  }
  
  Future<void> _demonstrateWholeTableDependencies() async {
    print('🟦 Demonstrating WHOLE-TABLE Dependencies');
    print('   Any change to the table invalidates the dependent stream\n');
    
    // Create a stream that depends on the entire users table
    final usersStream = reactiveDataAccess.watchTable('users');
    
    var updateCount = 0;
    final subscription = usersStream.listen((users) {
      updateCount++;
      print('   📡 Users stream updated (#$updateCount): ${users.length} users');
      for (final user in users) {
        print('      - ${user['username']} (${user['status']})');
      }
      print('');
    });
    streamListeners.add(subscription);
    
    // Wait for initial data
    await Future.delayed(Duration(milliseconds: 200));
    
    print('   🔧 Inserting new user...');
    await reactiveDataAccess.insert('users', {
      'username': 'david',
      'email': 'david@example.com',
      'age': 28,
      'status': 'active',
      'created_at': DateTime.now().toIso8601String(),
    });
    
    await Future.delayed(Duration(milliseconds: 200));
    
    print('   🔧 Updating user status...');
    await reactiveDataAccess.updateWhere('users', {'status': 'inactive'}, 
        where: 'username = ?', whereArgs: ['david']);
    
    await Future.delayed(Duration(milliseconds: 200));
    
    print('   🔧 Deleting user...');
    await reactiveDataAccess.deleteWhere('users', 
        where: 'username = ?', whereArgs: ['david']);
    
    await Future.delayed(Duration(milliseconds: 500));
    print('   ✅ Whole-table dependency demo complete\n');
  }
  
  Future<void> _demonstrateColumnWiseDependencies() async {
    print('🟩 Demonstrating COLUMN-WISE Dependencies');
    print('   Only changes to specific columns invalidate the stream\n');
    
    // Create a stream that only depends on specific columns
    final userEmailsStream = reactiveDataAccess.watchAggregate<List<String>>(
      'users',
      () async {
        final result = await dataAccess.database.rawQuery(
          'SELECT email FROM users WHERE status = ?', ['active']
        );
        return result.map((row) => row['email'] as String).toList();
      },
      dependentColumns: ['email', 'status'], // Only these columns matter
    );
    
    var updateCount = 0;
    final subscription = userEmailsStream.listen((emails) {
      updateCount++;
      print('   📡 Email stream updated (#$updateCount): ${emails.join(', ')}');
    });
    streamListeners.add(subscription);
    
    // Wait for initial data
    await Future.delayed(Duration(milliseconds: 200));
    
    print('   🔧 Updating user age (should NOT trigger update)...');
    await reactiveDataAccess.updateWhere('users', {'age': 26}, 
        where: 'username = ?', whereArgs: ['alice']);
    
    await Future.delayed(Duration(milliseconds: 300));
    
    print('   🔧 Updating user email (SHOULD trigger update)...');
    await reactiveDataAccess.updateWhere('users', {'email': 'alice.new@example.com'}, 
        where: 'username = ?', whereArgs: ['alice']);
    
    await Future.delayed(Duration(milliseconds: 300));
    
    print('   🔧 Updating user status (SHOULD trigger update)...');
    await reactiveDataAccess.updateWhere('users', {'status': 'inactive'}, 
        where: 'username = ?', whereArgs: ['bob']);
    
    await Future.delayed(Duration(milliseconds: 500));
    print('   ✅ Column-wise dependency demo complete\n');
  }
  
  Future<void> _demonstrateWhereClauseDependencies() async {
    print('🟨 Demonstrating WHERE-CLAUSE Dependencies');
    print('   Only changes matching specific conditions invalidate the stream\n');
    
    // Create streams with specific WHERE clause dependencies
    final activePosts = reactiveDataAccess.watchTable(
      'posts',
      where: 'category = ? AND likes > ?',
      whereArgs: ['programming', 10],
    );
    
    var updateCount = 0;
    final subscription = activePosts.listen((posts) {
      updateCount++;
      print('   📡 Programming posts with >10 likes updated (#$updateCount): ${posts.length} posts');
      for (final post in posts) {
        print('      - "${post['title']}" (${post['likes']} likes)');
      }
      print('');
    });
    streamListeners.add(subscription);
    
    // Wait for initial data
    await Future.delayed(Duration(milliseconds: 200));
    
    print('   🔧 Adding post in different category (should NOT trigger)...');
    await reactiveDataAccess.insert('posts', {
      'title': 'Cooking Tips',
      'content': 'How to make perfect pasta...',
      'user_id': 1,
      'category': 'cooking',
      'likes': 20,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    await Future.delayed(Duration(milliseconds: 300));
    
    print('   🔧 Adding programming post with low likes (should NOT trigger)...');
    await reactiveDataAccess.insert('posts', {
      'title': 'Advanced Algorithms',
      'content': 'Deep dive into sorting algorithms...',
      'user_id': 2,
      'category': 'programming',
      'likes': 5,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    await Future.delayed(Duration(milliseconds: 300));
    
    print('   🔧 Adding programming post with high likes (SHOULD trigger)...');
    await reactiveDataAccess.insert('posts', {
      'title': 'Design Patterns',
      'content': 'Essential patterns every developer should know...',
      'user_id': 1,
      'category': 'programming',
      'likes': 30,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    await Future.delayed(Duration(milliseconds: 500));
    print('   ✅ Where-clause dependency demo complete\n');
  }
  
  Future<void> _demonstrateRelatedTableDependencies() async {
    print('🟪 Demonstrating RELATED-TABLE Dependencies');
    print('   Changes to related tables affect streams through relationships\n');
    
    // Create a stream that aggregates data across related tables
    final userPostStats = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
      'users',
      () async {
        final result = await dataAccess.database.rawQuery('''
          SELECT u.username, COUNT(p.id) as post_count, 
                 COALESCE(SUM(p.likes), 0) as total_likes
          FROM users u
          LEFT JOIN posts p ON u.id = p.user_id
          WHERE u.status = 'active'
          GROUP BY u.id, u.username
          ORDER BY total_likes DESC
        ''');
        return result;
      },
    );
    
    var updateCount = 0;
    final subscription = userPostStats.listen((stats) {
      updateCount++;
      print('   📡 User post statistics updated (#$updateCount):');
      for (final stat in stats) {
        print('      - ${stat['username']}: ${stat['post_count']} posts, ${stat['total_likes']} likes');
      }
      print('');
    });
    streamListeners.add(subscription);
    
    // Wait for initial data
    await Future.delayed(Duration(milliseconds: 200));
    
    print('   🔧 Adding new post (affects related user stats)...');
    await reactiveDataAccess.insert('posts', {
      'title': 'Machine Learning Basics',
      'content': 'Introduction to ML concepts...',
      'user_id': 2, // Bob
      'category': 'ai',
      'likes': 40,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    await Future.delayed(Duration(milliseconds: 300));
    
    print('   🔧 Updating post likes (affects user stats through aggregation)...');
    await reactiveDataAccess.updateWhere('posts', {'likes': 50}, 
        where: 'title = ?', whereArgs: ['Introduction to Reactive Streams']);
    
    await Future.delayed(Duration(milliseconds: 300));
    
    print('   🔧 Deactivating user (removes them from stats)...');
    await reactiveDataAccess.updateWhere('users', {'status': 'inactive'}, 
        where: 'username = ?', whereArgs: ['charlie']);
    
    await Future.delayed(Duration(milliseconds: 500));
    print('   ✅ Related-table dependency demo complete\n');
  }
  
  Future<void> _demonstrateAggregateStreamDependencies() async {
    print('🟧 Demonstrating AGGREGATE Stream Dependencies');
    print('   Sophisticated aggregation streams with smart invalidation\n');
    
    // Count streams for different categories
    final programmingPostCount = reactiveDataAccess.watchCount(
      'posts',
      where: 'category = ?',
      whereArgs: ['programming'],
    );
    
    final totalLikes = reactiveDataAccess.watchAggregate<int>(
      'posts',
      () async {
        final result = await dataAccess.database.rawQuery(
          'SELECT SUM(likes) as total FROM posts'
        );
        return (result.first['total'] as int?) ?? 0;
      },
      dependentColumns: ['likes'],
    );
    
    final avgUserAge = reactiveDataAccess.watchAggregate<double>(
      'users',
      () async {
        final result = await dataAccess.database.rawQuery(
          'SELECT AVG(age) as avg_age FROM users WHERE status = ?', ['active']
        );
        return (result.first['avg_age'] as num?)?.toDouble() ?? 0.0;
      },
      where: 'status = ?',
      whereArgs: ['active'],
      dependentColumns: ['age', 'status'],
    );
    
    var progCountUpdates = 0;
    var likesUpdates = 0;
    var ageUpdates = 0;
    
    final sub1 = programmingPostCount.listen((count) {
      progCountUpdates++;
      print('   📊 Programming posts count (#$progCountUpdates): $count');
    });
    
    final sub2 = totalLikes.listen((likes) {
      likesUpdates++;
      print('   💖 Total likes (#$likesUpdates): $likes');
    });
    
    final sub3 = avgUserAge.listen((age) {
      ageUpdates++;
      print('   👥 Average user age (#$ageUpdates): ${age.toStringAsFixed(1)}');
    });
    
    streamListeners.addAll([sub1, sub2, sub3]);
    
    // Wait for initial data
    await Future.delayed(Duration(milliseconds: 200));
    print('');
    
    print('   🔧 Adding programming post (affects count only)...');
    await reactiveDataAccess.insert('posts', {
      'title': 'Functional Programming',
      'content': 'Exploring functional paradigms...',
      'user_id': 1,
      'category': 'programming',
      'likes': 12,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    await Future.delayed(Duration(milliseconds: 300));
    
    print('   🔧 Updating post likes (affects total likes only)...');
    await reactiveDataAccess.updateWhere('posts', {'likes': 25}, 
        where: 'title = ?', whereArgs: ['Functional Programming']);
    
    await Future.delayed(Duration(milliseconds: 300));
    
    print('   🔧 Adding new active user (affects average age only)...');
    await reactiveDataAccess.insert('users', {
      'username': 'eve',
      'email': 'eve@example.com',
      'age': 35,
      'status': 'active',
      'created_at': DateTime.now().toIso8601String(),
    });
    
    await Future.delayed(Duration(milliseconds: 500));
    print('   ✅ Aggregate dependency demo complete\n');
  }
  
  Future<void> _showDependencyStatistics() async {
    print('📈 Dependency Tracking Statistics');
    
    final stats = reactiveDataAccess.getDependencyStats();
    
    print('   Total active streams: ${stats.totalStreams}');
    print('   Total dependencies: ${stats.totalDependencies}');
    print('   Whole-table dependencies: ${stats.wholeTableDependencies}');
    print('   Column-wise dependencies: ${stats.columnWiseDependencies}');
    print('   Where-clause dependencies: ${stats.whereClauseDependencies}');
    print('   Related-table dependencies: ${stats.relatedTableDependencies}');
    print('   Tables being monitored: ${stats.totalTables}');
    print('');
    
    // Test dependency optimization
    print('🎯 Dependency Optimization Test');
    print('   Creating multiple streams on same table to test efficiency...\n');
    
    // Create multiple streams that should share dependencies intelligently
    final stream1 = reactiveDataAccess.watchTable('users', where: 'status = ?', whereArgs: ['active']);
    final stream2 = reactiveDataAccess.watchTable('users', where: 'age > ?', whereArgs: [25]);
    final stream3 = reactiveDataAccess.watchCount('users');
    
    // Quick listeners to activate the streams
    final subs = [
      stream1.listen((_) {}),
      stream2.listen((_) {}),
      stream3.listen((_) {}),
    ];
    streamListeners.addAll(subs);
    
    await Future.delayed(Duration(milliseconds: 200));
    
    final newStats = reactiveDataAccess.getDependencyStats();
    print('   After adding 3 more streams:');
    print('   Total active streams: ${newStats.totalStreams}');
    print('   Total dependencies: ${newStats.totalDependencies}');
    print('   Average dependencies per stream: ${(newStats.totalDependencies / newStats.totalStreams).toStringAsFixed(2)}');
    print('');
  }
  
  Future<void> _cleanup() async {
    print('🧹 Cleaning up resources...');
    
    // Cancel all stream subscriptions
    for (final subscription in streamListeners) {
      await subscription.cancel();
    }
    
    // Dispose reactive data access
    await reactiveDataAccess.dispose();
    
    // Close database
    await database.close();
    
    print('   ✅ Cleanup complete');
  }
}