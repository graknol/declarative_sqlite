import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

// Mock generated code to test the new structure
part 'enhanced_generator_test.g.dart';

/// Test for the enhanced generator features:
/// - @RegisterFactory annotation
/// - Generated factory methods
/// - Generated registration functions
/// - Minimal developer boilerplate
void main() {
  late DeclarativeDatabase db;

  // Mock generated classes with new structure
  @GenerateDbRecord('users')
  @RegisterFactory()
  class User extends DbRecord {
    User(Map<String, Object?> data, DeclarativeDatabase database)
        : super(data, 'users', database);
  }

  @GenerateDbRecord('posts')
  @RegisterFactory()
  class Post extends DbRecord {
    Post(Map<String, Object?> data, DeclarativeDatabase database)
        : super(data, 'posts', database);
  }

  Schema getSchema() {
    final schemaBuilder = SchemaBuilder();
    schemaBuilder.table('users', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.text('email').notNull('');
      table.integer('age').notNull(0);
      table.date('created_at').notNull(DateTime.now());
      table.key(['id']).primary();
    });
    schemaBuilder.table('posts', (table) {
      table.integer('id').notNull(0);
      table.integer('user_id').notNull(0);
      table.text('title').notNull('');
      table.text('content');
      table.date('published_at');
      table.key(['id']).primary();
    });
    return schemaBuilder.build();
  }

  setUpAll(() async {
    db = await setupTestDatabase(schema: getSchema());
  });

  setUp(() async {
    await clearDatabase(db.db);
    RecordMapFactoryRegistry.clear();
  });

  tearDownAll(() async {
    await db.close();
  });

  group('Enhanced Generator Features', () {
    test('Generated fromMap extension works', () {
      final userData = {
        'id': 1,
        'name': 'Test User',
        'email': 'test@example.com',
        'age': 25,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      // Use the generated fromMap from extension
      final user = UserGenerated.fromMap(userData, db);
      expect(user, isA<User>());
      expect(user.name, 'Test User');
      expect(user.age, 25);
    });

    test('Generated factory methods work', () {
      final userData = {
        'id': 1,
        'name': 'Factory User',
        'email': 'factory@example.com',
        'age': 30,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      // Use the generated factory directly
      final user = UserGenerated.fromMap(userData, db);
      expect(user, isA<User>());
      expect(user.name, 'Factory User');
    });

    test('Generated factory registration works', () {
      // This would test the generated registerAllFactories function
      expect(RecordMapFactoryRegistry.hasFactory<User>(), false);
      expect(RecordMapFactoryRegistry.hasFactory<Post>(), false);
      
      // Call generated registration function
      registerAllFactories(db);
      
      expect(RecordMapFactoryRegistry.hasFactory<User>(), true);
      expect(RecordMapFactoryRegistry.hasFactory<Post>(), true);
    });

    test('Individual factory registration works', () {
      expect(RecordMapFactoryRegistry.hasFactory<User>(), false);
      
      // Use generated registration (simplified - no individual functions in new approach)
      RecordMapFactoryRegistry.register<User>((data) => UserGenerated.fromMap(data, db));
      
      expect(RecordMapFactoryRegistry.hasFactory<User>(), true);
      expect(RecordMapFactoryRegistry.hasFactory<Post>(), false);
    });

    test('Generated typed properties work', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Property Test',
        'email': 'property@example.com',
        'age': 35,
        'created_at': DateTime.now().toIso8601String(),
      });
      
      final userData = await db.queryFirst('users', where: 'id = ?', whereArgs: [1]);
      final user = UserGenerated.fromMap(userData!, db);
      
      // Test generated getters
      expect(user.id, 1);
      expect(user.name, 'Property Test');
      expect(user.email, 'property@example.com');
      expect(user.age, 35);
      
      // Test generated setters
      user.name = 'Updated Name';
      user.age = 36;
      
      await user.save();
      
      final updatedData = await db.queryFirst('users', where: 'id = ?', whereArgs: [1]);
      expect(updatedData!['name'], 'Updated Name');
      expect(updatedData['age'], 36);
    });

    test('Multiple record types work together', () {
      final userData = {
        'id': 1,
        'name': 'Author',
        'email': 'author@example.com',
        'age': 40,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      final postData = {
        'id': 1,
        'user_id': 1,
        'title': 'Test Post',
        'content': 'This is a test post',
        'published_at': DateTime.now().toIso8601String(),
      };
      
      final user = UserGenerated.fromMap(userData, db);
      final post = PostGenerated.fromMap(postData, db);
      
      expect(user, isA<User>());
      expect(post, isA<Post>());
      expect(user.name, 'Author');
      expect(post.title, 'Test Post');
    });
  });

  group('Backwards Compatibility', () {
    test('Old manual registration still works', () {
      // Manual registration should still work alongside generated
      RecordMapFactoryRegistry.register<User>((data) => UserGenerated.fromMap(data, db));
      
      expect(RecordMapFactoryRegistry.hasFactory<User>(), true);
      
      final userData = {
        'id': 1,
        'name': 'Manual User',
        'email': 'manual@example.com',
        'age': 45,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      final user = RecordMapFactoryRegistry.create<User>(userData);
      expect(user, isA<User>());
      expect(user.name, 'Manual User');
    });
  });
}

// Mock generated code (this would be produced by the actual generator)
// In a real scenario, this would be in the .g.dart file

// Mock generated extensions for testing
extension UserGenerated on User {
  int get id => getIntegerNotNull('id');
  String get name => getTextNotNull('name');
  String? get email => getText('email');
  int? get age => getInteger('age');
  DateTime get createdAt => getDateTimeNotNull('created_at');
  
  set name(String value) => setText('name', value);
  set email(String? value) => setText('email', value);
  set age(int? value) => setInteger('age', value);
  set createdAt(DateTime value) => setDateTime('created_at', value);
  
  // Generated fromMap method
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return User(data, database);
  }
}

extension PostGenerated on Post {
  int get id => getIntegerNotNull('id');
  int get userId => getIntegerNotNull('user_id');
  String get title => getTextNotNull('title');
  String? get content => getText('content');
  DateTime? get publishedAt => getDateTime('published_at');
  
  set title(String value) => setText('title', value);
  set content(String? value) => setText('content', value);
  set publishedAt(DateTime? value) => setDateTime('published_at', value);
  
  // Generated fromMap method
  static Post fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return Post(data, database);
  }
}

void registerAllFactories(DeclarativeDatabase database) {
  RecordMapFactoryRegistry.register<User>((data) => UserGenerated.fromMap(data, database));
  RecordMapFactoryRegistry.register<Post>((data) => PostGenerated.fromMap(data, database));
}