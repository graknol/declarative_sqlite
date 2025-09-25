import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'in_memory_file_repository.dart';

// Mock data and schema for testing
void buildTestSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id');
    table.text('name');
    table.integer('age');
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Tests', () {
    test('can create and open database', () async {
      final schemaBuilder = SchemaBuilder();
      buildTestSchema(schemaBuilder);
      final schema = schemaBuilder.build();
      
      final db = await DeclarativeDatabase.open(
        ':memory:',
        schema: schema,
        databaseFactory: databaseFactory,
        fileRepository: InMemoryFileRepository(),
      );
      
      expect(db, isNotNull);
      
      // Test basic database operation
      await db.insert('users', {'id': '1', 'name': 'Alice', 'age': 30});
      final result = await db.query((q) => q.from('users'));
      expect(result, hasLength(1));
      expect(result.first['name'], equals('Alice'));
      
      await db.close();
    });
  });
}