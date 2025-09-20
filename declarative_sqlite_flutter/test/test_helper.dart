import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

bool _sqliteFfiInitialized = false;

/// Sets up sqflite_ffi for testing if not already initialized
void initializeSqliteFfi() {
  if (!_sqliteFfiInitialized) {
    sqfliteFfiInit();
    _sqliteFfiInitialized = true;
  }
}

/// Creates a test database with the given schema
Future<DeclarativeDatabase> createTestDatabase({required Schema schema}) async {
  initializeSqliteFfi();
  final dbName = Uuid().v4();
  return DeclarativeDatabase.open(
    'file:$dbName?mode=memory&cache=shared',
    schema: schema,
    databaseFactory: databaseFactoryFfi,
    isSingleInstance: false,
  );
}

/// Creates a simple test schema
Schema createTestSchema() {
  final schemaBuilder = SchemaBuilder();
  schemaBuilder.table('users', (table) {
    table.guid('id').notNull();
    table.text('name').notNull();
    table.text('email').notNull();
    table.integer('age').notNull(0);
    table.key(['id']).primary();
  });
  schemaBuilder.table('posts', (table) {
    table.guid('id').notNull();
    table.guid('user_id').notNull();
    table.text('title').notNull();
    table.text('content').notNull();
    table.key(['id']).primary();
  });
  return schemaBuilder.build();
}

/// Creates a test user data model
class TestUser {
  final String id;
  final String name;
  final String email;
  final int age;

  TestUser({
    required this.id,
    required this.name,
    required this.email,
    required this.age,
  });

  static TestUser fromMap(Map<String, Object?> map) {
    return TestUser(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      age: map['age'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'age': age,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          email == other.email &&
          age == other.age;

  @override
  int get hashCode =>
      id.hashCode ^ name.hashCode ^ email.hashCode ^ age.hashCode;
}

/// Test post data model
class TestPost {
  final String id;
  final String userId;
  final String title;
  final String content;

  TestPost({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
  });

  static TestPost fromMap(Map<String, Object?> map) {
    return TestPost(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'content': content,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestPost &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId &&
          title == other.title &&
          content == other.content;

  @override
  int get hashCode =>
      id.hashCode ^ userId.hashCode ^ title.hashCode ^ content.hashCode;
}

/// Clears all data from the test database
Future<void> clearTestDatabase(DeclarativeDatabase db) async {
  final tables = await db.db.query('sqlite_master',
      columns: ['name'], where: 'type = ?', whereArgs: ['table']);
  for (final table in tables) {
    final tableName = table['name'] as String;
    if (!tableName.startsWith('sqlite_') && !tableName.startsWith('__')) {
      await db.db.delete(tableName);
    }
  }
}

/// Waits for a given duration to allow async operations to complete
Future<void> waitForAsync([Duration duration = const Duration(milliseconds: 100)]) async {
  await Future.delayed(duration);
}