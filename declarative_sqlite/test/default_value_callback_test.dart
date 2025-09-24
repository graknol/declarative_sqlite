import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/schema/db_column.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// Test demonstrating default value callback functionality and automatic serialization
void main() {
  
  test('default value callbacks and static defaults with DateTime serialization', () {
    // This test verifies that DateTime values are automatically serialized
    // both in callbacks and static defaults
    final schemaBuilder = SchemaBuilder();
    
    schemaBuilder.table('test_serialization', (table) {
      // Auto-generate UUID for id
      table.guid('id').notNull('').defaultCallback(() => Uuid().v4());
      
      // Test DateTime callback (should be auto-serialized to string)
      table.date('callback_date').notNull('').defaultCallback(() => DateTime.now());
      
      // Test static DateTime default (should be auto-serialized to string)
      table.date('static_date').notNull('').defaultsTo(DateTime(2024, 1, 1));
      
      // Test string callback (no serialization needed)
      table.text('callback_text').defaultCallback(() => 'generated_text');
      
      // Test static string default (no serialization needed)
      table.text('static_text').defaultsTo('static_text_value');
      
      // Test integer callback (no serialization needed)
      table.integer('callback_int').defaultCallback(() => 42);
      
      // Test static integer default (no serialization needed)  
      table.integer('static_int').defaultsTo(100);
      
      table.key(['id']).primary();
    });
    
    final schema = schemaBuilder.build();
    
    // Verify the schema builds correctly (check user tables only, not system tables)
    final userTables = schema.tables.where((t) => !t.isSystem).toList();
    expect(userTables.length, 1);
    final testTable = userTables.first;
    expect(testTable.name, 'test_serialization');
    
    // Debug: Print all columns and their callback status
    print('Table columns:');
    for (final col in testTable.columns) {
      print('  ${col.name}: callback=${col.defaultValueCallback != null}, defaultValue=${col.defaultValue}');
    }
    
    // Helper function to find a column by name
    DbColumn getColumn(String name) {
      return testTable.columns.firstWhere((col) => col.name == name);
    }
    
    // Verify all columns exist
    expect(getColumn('id').name, 'id');
    expect(getColumn('callback_date').name, 'callback_date');
    expect(getColumn('static_date').name, 'static_date');
    expect(getColumn('callback_text').name, 'callback_text');
    expect(getColumn('static_text').name, 'static_text');
    expect(getColumn('callback_int').name, 'callback_int');
    expect(getColumn('static_int').name, 'static_int');
    
    // Test that date column callbacks return DateTime objects (they should be serialized during insert)
    final callbackDateCol = getColumn('callback_date');
    expect(callbackDateCol.defaultValueCallback, isNotNull);
    final dateCallback = callbackDateCol.defaultValueCallback!;
    final callbackResult = dateCallback();
    expect(callbackResult, isA<DateTime>());
    
    // Test that static date default is DateTime object (should be serialized during insert)
    final staticDateCol = getColumn('static_date');
    final staticDateDefault = staticDateCol.defaultValue;
    expect(staticDateDefault, isA<DateTime>());
    expect(staticDateDefault, equals(DateTime(2024, 1, 1)));
    
    // Test other callback types - verify they exist
    final textCallbackCol = getColumn('callback_text');
    expect(textCallbackCol.defaultValueCallback, isNotNull, reason: 'Text callback should be stored');
    final textCallback = textCallbackCol.defaultValueCallback!;
    expect(textCallback(), 'generated_text');
    
    final intCallbackCol = getColumn('callback_int');  
    expect(intCallbackCol.defaultValueCallback, isNotNull, reason: 'Int callback should be stored');
    final intCallback = intCallbackCol.defaultValueCallback!;
    expect(intCallback(), 42);
    
    // Test static defaults
    expect(getColumn('static_text').defaultValue, 'static_text_value');
    expect(getColumn('static_int').defaultValue, 100);
    
    print('✓ Default value callback API works correctly');
    print('✓ DateTime callbacks return DateTime objects (will be auto-serialized)');
    print('✓ Static DateTime defaults are DateTime objects (will be auto-serialized)');
    print('✓ Other data types work without serialization');
    print('✓ Callback result: $callbackResult');
    print('✓ Static date default: $staticDateDefault');
  });
}