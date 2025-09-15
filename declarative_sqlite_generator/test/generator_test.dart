import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_generator/declarative_sqlite_generator.dart';
import 'package:test/test.dart';

void main() {
  group('TableDataClassGenerator', () {
    late TableDataClassGenerator generator;
    
    setUp(() {
      generator = TableDataClassGenerator();
    });

    test('generates basic data class for simple table', () {
      final table = TableBuilder('users')
          .text('name', (col) => col.notNull())
          .text('email', (col) => col.unique())
          .integer('age');

      final dataClass = generator.generateDataClass(table);
      
      expect(dataClass.name, equals('UsersData'));
      expect(dataClass.fields.length, equals(5)); // 3 user fields + 2 system fields
      
      // Check that system fields are included
      final fieldNames = dataClass.fields.map((f) => f.name).toList();
      expect(fieldNames, contains('systemId'));
      expect(fieldNames, contains('systemVersion'));
      expect(fieldNames, contains('name'));
      expect(fieldNames, contains('email'));
      expect(fieldNames, contains('age'));
    });

    test('generates class with proper constructor parameters', () {
      final table = TableBuilder('products')
          .text('name', (col) => col.notNull())
          .real('price', (col) => col.notNull())
          .text('description');

      final dataClass = generator.generateDataClass(table);
      final constructor = dataClass.constructors.first;
      
      expect(constructor.constant, isTrue);
      expect(constructor.optionalParameters.length, equals(5)); // 3 user + 2 system
      
      // Check required parameters (notNull columns + system columns)
      final requiredParams = constructor.optionalParameters
          .where((p) => p.required)
          .map((p) => p.name)
          .toList();
      expect(requiredParams, contains('systemId'));
      expect(requiredParams, contains('systemVersion'));
      expect(requiredParams, contains('name'));
      expect(requiredParams, contains('price'));
      expect(requiredParams, isNot(contains('description'))); // nullable
    });

    test('generates methods for data class', () {
      final table = TableBuilder('simple')
          .text('data', (col) => col.notNull());

      final dataClass = generator.generateDataClass(table);
      final methodNames = dataClass.methods.map((m) => m.name).toList();
      
      expect(methodNames, contains('toMap'));
      expect(methodNames, contains('fromMap'));
      expect(methodNames, contains('toString'));
      expect(methodNames, contains('hashCode'));
      expect(methodNames, contains('operator =='));
    });

    test('handles different SQLite data types', () {
      final table = TableBuilder('data_types')
          .integer('int_col', (col) => col.notNull())
          .real('real_col', (col) => col.notNull())
          .text('text_col', (col) => col.notNull())
          .blob('blob_col', (col) => col.notNull())
          .date('date_col', (col) => col.notNull())
          .fileset('fileset_col', (col) => col.notNull());

      final dataClass = generator.generateDataClass(table);
      
      // Check that we have the expected number of fields
      expect(dataClass.fields.length, equals(8)); // 6 user + 2 system
      
      // Verify the class was generated without throwing
      expect(dataClass.name, equals('DataTypesData'));
      
      // Check that fileset column is mapped to FilesetField
      final filesetField = dataClass.fields.firstWhere((f) => f.name == 'fileset_col');
      expect(filesetField.type?.symbol, equals('FilesetField'));
    });

    test('generates proper serialization methods for fileset columns', () {
      final table = TableBuilder('documents')
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .fileset('attachments', (col) => col.notNull())
          .fileset('gallery'); // nullable

      final dataClass = generator.generateDataClass(table);
      
      // Find the toMap method
      final toMapMethod = dataClass.methods.firstWhere((m) => m.name == 'toMap');
      expect(toMapMethod, isNotNull);
      
      // Find the fromMap method
      final fromMapMethod = dataClass.methods.firstWhere((m) => m.name == 'fromMap');
      expect(fromMapMethod, isNotNull);
      
      // fromMap should have manager parameter since table has fileset columns
      expect(fromMapMethod.requiredParameters.length, equals(2)); // map + manager
      expect(fromMapMethod.requiredParameters.last.name, equals('manager'));
      expect(fromMapMethod.requiredParameters.last.type?.symbol, equals('FilesetManager'));
    });

    test('converts table names to proper class names', () {
      final tables = [
        TableBuilder('user_profiles'),
        TableBuilder('orderItems'),
        TableBuilder('simple'),
        TableBuilder('multi_word_table_name'),
      ];

      final classNames = tables.map((table) => 
        generator.generateDataClass(table).name
      ).toList();

      expect(classNames, equals([
        'UserProfilesData',
        'OrderitemsData',
        'SimpleData',
        'MultiWordTableNameData',
      ]));
    });
  });

  group('ViewDataClassGenerator', () {
    late ViewDataClassGenerator generator;
    late SchemaBuilder schema;
    
    setUp(() {
      generator = ViewDataClassGenerator();
      schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull())
              .text('email', (col) => col.unique()));
    });

    test('generates basic data class for view', () {
      final view = ViewBuilder.simple('user_view', 'users');
      
      final dataClass = generator.generateDataClass(view, schema);
      
      expect(dataClass.name, equals('UserViewViewData'));
      expect(dataClass.fields.isNotEmpty, isTrue);
    });

    test('generates view data class without toMap method', () {
      final view = ViewBuilder.simple('readonly_view', 'users');
      
      final dataClass = generator.generateDataClass(view, schema);
      final methodNames = dataClass.methods.map((m) => m.name).toList();
      
      // Views are read-only, so no toMap method
      expect(methodNames, isNot(contains('toMap')));
      expect(methodNames, contains('fromMap'));
      expect(methodNames, contains('toString'));
      expect(methodNames, contains('hashCode'));
      expect(methodNames, contains('operator =='));
    });
  });

  group('SchemaCodeGenerator', () {
    late SchemaCodeGenerator generator;
    
    setUp(() {
      generator = SchemaCodeGenerator();
    });

    test('generates code for complete schema', () {
      final schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull())
              .text('email', (col) => col.unique()))
          .table('posts', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('title', (col) => col.notNull())
              .integer('user_id', (col) => col.notNull()));

      final code = generator.generateCode(schema, libraryName: 'test_schema');
      
      expect(code, contains('class UsersData'));
      expect(code, contains('class PostsData'));
      expect(code, contains('Generated data classes for declarative_sqlite schema'));
      expect(code, isNot(isEmpty));
    });

    test('generates code for single table', () {
      final table = TableBuilder('products')
          .text('name', (col) => col.notNull())
          .real('price', (col) => col.notNull());

      final code = generator.generateTableCode(table, libraryName: 'products');
      
      expect(code, contains('class ProductsData'));
      expect(code, contains('Generated data class for products table'));
      expect(code, isNot(isEmpty));
    });

    test('generates formatted Dart code', () {
      final table = TableBuilder('simple')
          .text('data', (col) => col.notNull());

      final code = generator.generateTableCode(table);
      
      // Check that the code is properly formatted and contains expected elements
      expect(code, contains('class SimpleData {'));
      expect(code, contains('final String data;'));
      expect(code, contains('Map<String, dynamic> toMap()'));
      expect(code, contains('static SimpleData fromMap'));
      expect(code, isNot(isEmpty));
    });
  });
}