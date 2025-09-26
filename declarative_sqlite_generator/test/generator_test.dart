import 'dart:convert';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('Schema Generation', () {
    test('creates valid schema from builder', () {
      final builder = SchemaBuilder();
      builder.table('users', (table) {
        table.guid('id');
        table.text('name');
        table.integer('age');
      });
      
      final schema = builder.build();
      expect(schema.tables.length, equals(4)); // 1 user table + 3 system tables
      
      // Find the user table (system tables have names starting with __)
      final userTable = schema.tables.firstWhere((t) => t.name == 'users');
      expect(userTable.name, equals('users'));
      expect(userTable.columns.length, equals(6)); // 3 user + 3 system columns
    });

    test('schema can be serialized to JSON', () {
      final builder = SchemaBuilder();
      builder.table('users', (table) {
        table.guid('id');
        table.text('name');
        table.integer('age');
      });
      
      final schema = builder.build();
      final json = schema.toJson();
      expect(json['tables'], isA<List>());
      expect(json['tables'], hasLength(4)); // 1 user + 3 system tables
      
      // Check that the users table is in the JSON
      final tables = json['tables'] as List;
      final usersTable = tables.firstWhere((t) => t['name'] == 'users');
      expect(usersTable['name'], equals('users'));
    });

    test('schema can be deserialized from JSON', () {
      final builder = SchemaBuilder();
      builder.table('users', (table) {
        table.guid('id');
        table.text('name');
        table.integer('age');
      });
      
      final originalSchema = builder.build();
      final json = originalSchema.toJson();
      final deserializedSchema = Schema.fromJson(json);
      
      expect(deserializedSchema.tables.length, equals(originalSchema.tables.length));
      
      // Find the users table in the deserialized schema
      final usersTable = deserializedSchema.tables.firstWhere((t) => t.name == 'users');
      expect(usersTable.name, equals('users'));
    });
  });

  group('Code Generation Logic', () {
    test('validates table exists in schema', () {
      final builder = SchemaBuilder();
      builder.table('posts', (table) {
        table.guid('id');
        table.text('title');
      });
      
      final schema = builder.build();
      
      // Should find 'posts' table
      final postsTable = schema.tables.firstWhere(
        (t) => t.name == 'posts',
        orElse: () => throw Exception('Table not found'),
      );
      expect(postsTable.name, equals('posts'));
      
      // Should not find 'users' table
      expect(
        () => schema.tables.firstWhere(
          (t) => t.name == 'users',
          orElse: () => throw Exception('Table not found'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('generates correct column types', () {
      final builder = SchemaBuilder();
      builder.table('users', (table) {
        table.guid('id');
        table.text('name');
        table.integer('age');
        table.real('height');
        table.date('created_at');
      });
      
      final schema = builder.build();
      final table = schema.tables.first;
      
      final idCol = table.columns.firstWhere((c) => c.name == 'id');
      final nameCol = table.columns.firstWhere((c) => c.name == 'name');
      final ageCol = table.columns.firstWhere((c) => c.name == 'age');
      final heightCol = table.columns.firstWhere((c) => c.name == 'height');
      final createdCol = table.columns.firstWhere((c) => c.name == 'created_at');
      
      expect(idCol.logicalType, equals('guid'));
      expect(nameCol.logicalType, equals('text'));
      expect(ageCol.logicalType, equals('integer'));
      expect(heightCol.logicalType, equals('real'));
      expect(createdCol.logicalType, equals('date'));
    });

    test('handles LWW columns correctly', () {
      final builder = SchemaBuilder();
      builder.table('posts', (table) {
        table.guid('id');
        table.text('title').lww();
        table.text('content').lww();
      });
      
      final schema = builder.build();
      final table = schema.tables.first;
      
      final titleCol = table.columns.firstWhere((c) => c.name == 'title');
      final contentCol = table.columns.firstWhere((c) => c.name == 'content');
      
      expect(titleCol.isLww, isTrue);
      expect(contentCol.isLww, isTrue);
    });
  });

  group('Build System Integration', () {
    test('can create schema cache content', () {
      final builder = SchemaBuilder();
      builder.table('users', (table) {
        table.guid('id');
        table.text('name');
        table.integer('age');
      });
      
      final schema = builder.build();
      final json = jsonEncode(schema.toJson());
      
      // Verify the JSON contains expected structure
      expect(json, contains('"tables"'));
      expect(json, contains('"users"'));
      expect(json, contains('"name"'));
      expect(json, contains('"age"'));
    });
  });
}
