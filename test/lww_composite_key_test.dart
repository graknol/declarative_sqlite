import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  // Initialize sqflite for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  group('LWW Composite Primary Key Tests', () {
    late Database database;
    late SchemaBuilder schema;
    late LWWDataAccess dataAccess;

    setUpAll(() async {
      database = await databaseFactory.openDatabase(':memory:');
      
      // Create a table with composite primary key using string, integer, and date columns
      schema = SchemaBuilder()
        .table('order_items', (table) => table
          .text('order_id', (col) => col.notNull()) // String part of composite key
          .integer('product_id', (col) => col.notNull()) // Integer part of composite key  
          .date('delivery_date', (col) => col.notNull()) // Date part of composite key
          .compositeKey(['order_id', 'product_id', 'delivery_date'])
          .integer('quantity', (col) => col.lww()) // LWW column
          .real('unit_price', (col) => col.lww()) // LWW column
          .text('notes', (col) => col.lww())); // LWW column

      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);
      
      dataAccess = await LWWDataAccess.create(database: database, schema: schema);
    });

    tearDownAll(() async {
      await database.close();
    });

    setUp(() {
      // Clear operations before each test
      dataAccess.clearAllPendingOperations();
    });

    test('can insert and retrieve data with composite primary key', () async {
      // Insert an order item with composite primary key
      final compositeKey = {
        'order_id': 'ORD-2024-001',
        'product_id': 12345,
        'delivery_date': DateTime(2024, 1, 15),
      };
      
      final orderItemData = {
        ...compositeKey,
        'quantity': 5,
        'unit_price': 19.99,
        'notes': 'Initial order notes',
      };

      await dataAccess.insert('order_items', orderItemData);

      // Retrieve by composite primary key
      final retrieved = await dataAccess.getByPrimaryKey('order_items', compositeKey);
      expect(retrieved, isNotNull);
      expect(retrieved!['order_id'], equals('ORD-2024-001'));
      expect(retrieved['product_id'], equals(12345));
      // Compare dates by day since encoding/decoding might affect timezone representation
      final retrievedDate = retrieved['delivery_date'] as DateTime;
      expect(retrievedDate.year, equals(2024));
      expect(retrievedDate.month, equals(1));
      expect(retrievedDate.day, equals(15));
      expect(retrieved['quantity'], equals(5));
      expect(retrieved['unit_price'], equals(19.99));
      expect(retrieved['notes'], equals('Initial order notes'));
    });

    test('can update LWW columns with composite primary key', () async {
      // Insert initial data
      final compositeKey = {
        'order_id': 'ORD-2024-002', 
        'product_id': 67890,
        'delivery_date': DateTime(2024, 2, 20),
      };
      
      await dataAccess.insert('order_items', {
        ...compositeKey,
        'quantity': 3,
        'unit_price': 25.00,
        'notes': 'Original notes',
      });

      // Update LWW columns using composite key
      await dataAccess.updateLWWColumn('order_items', compositeKey, 'quantity', 8);
      await dataAccess.updateLWWColumn('order_items', compositeKey, 'unit_price', 22.50);
      await dataAccess.updateLWWColumn('order_items', compositeKey, 'notes', 'Updated notes');

      // Verify updates
      final quantity = await dataAccess.getLWWColumnValue('order_items', compositeKey, 'quantity');
      final price = await dataAccess.getLWWColumnValue('order_items', compositeKey, 'unit_price');
      final notes = await dataAccess.getLWWColumnValue('order_items', compositeKey, 'notes');

      expect(quantity, equals(8));
      expect(price, equals(22.50));
      expect(notes, equals('Updated notes'));
    });

    test('handles conflict resolution with composite primary key', () async {
      final compositeKey = {
        'order_id': 'ORD-2024-003',
        'product_id': 11111, 
        'delivery_date': DateTime(2024, 3, 10),
      };
      
      await dataAccess.insert('order_items', {
        ...compositeKey,
        'quantity': 10,
        'unit_price': 15.00,
        'notes': 'Initial notes',
      });

      // User makes an update (current timestamp)
      await dataAccess.updateLWWColumn('order_items', compositeKey, 'quantity', 15);
      
      // Simulate older server update (should be rejected)
      final olderTimestamp = (DateTime.now().microsecondsSinceEpoch - 10000).toString();
      await dataAccess.updateLWWColumn(
        'order_items', 
        compositeKey, 
        'quantity', 
        12,
        timestamp: olderTimestamp,
      );
      
      // User's value should win (15)
      final serverValue = await dataAccess.getLWWColumnValue('order_items', compositeKey, 'quantity');
      expect(serverValue, equals(15));
      
      // Simulate newer server update (should be accepted)
      final newerTimestamp = (DateTime.now().microsecondsSinceEpoch + 10000).toString();
      await dataAccess.updateLWWColumn(
        'order_items',
        compositeKey,
        'quantity', 
        20,
        timestamp: newerTimestamp,
      );
      
      // Server's newer value should win (20)
      final newerServerValue = await dataAccess.getLWWColumnValue('order_items', compositeKey, 'quantity');
      expect(newerServerValue, equals(20));
    });

    test('supports composite primary key with List format', () async {
      // Test with List format for composite primary key
      final compositeKeyList = [
        'ORD-2024-004',
        98765, 
        DateTime(2024, 4, 5),
      ];
      
      await dataAccess.insert('order_items', {
        'order_id': 'ORD-2024-004',
        'product_id': 98765,
        'delivery_date': DateTime(2024, 4, 5),
        'quantity': 7,
        'unit_price': 30.00,
        'notes': 'List format test',
      });

      // Update using List format for composite key
      await dataAccess.updateLWWColumn('order_items', compositeKeyList, 'quantity', 14);
      
      final quantity = await dataAccess.getLWWColumnValue('order_items', compositeKeyList, 'quantity');
      expect(quantity, equals(14));
    });

    test('handles app restart scenario with composite primary key', () async {
      final compositeKey = {
        'order_id': 'ORD-2024-005',
        'product_id': 55555,
        'delivery_date': DateTime(2024, 5, 15),
      };
      
      // Initial data
      await dataAccess.insert('order_items', {
        ...compositeKey,
        'quantity': 6,
        'unit_price': 45.00,
        'notes': 'Before restart',
      });

      // User update
      await dataAccess.updateLWWColumn('order_items', compositeKey, 'quantity', 9);
      
      // Simulate app restart by creating new LWWDataAccess instance
      final newDataAccess = await LWWDataAccess.create(database: database, schema: schema);
      
      // Should still get the correct value from DB + stored timestamps
      final quantity = await newDataAccess.getLWWColumnValue('order_items', compositeKey, 'quantity');
      expect(quantity, equals(9));
      
      // Verify server conflict resolution still works after restart
      final olderTimestamp = (DateTime.now().microsecondsSinceEpoch - 10000).toString();
      await newDataAccess.updateLWWColumn(
        'order_items',
        compositeKey,
        'quantity',
        6, // older value
        timestamp: olderTimestamp,
      );
      
      // User's value should still win
      final serverValue = await newDataAccess.getLWWColumnValue('order_items', compositeKey, 'quantity');
      expect(serverValue, equals(9));
    });

    test('validates error handling with malformed composite keys', () async {
      final compositeKey = {
        'order_id': 'ORD-2024-006',
        'product_id': 77777,
        'delivery_date': DateTime(2024, 6, 1),
      };
      
      await dataAccess.insert('order_items', {
        ...compositeKey,
        'quantity': 4,
        'unit_price': 12.00,
        'notes': 'Error test',
      });

      // Test with missing primary key column
      final malformedKey = {
        'order_id': 'ORD-2024-006',
        // missing product_id and delivery_date
      };
      
      expect(
        () => dataAccess.updateLWWColumn('order_items', malformedKey, 'quantity', 10),
        throwsA(isA<ArgumentError>()),
      );

      // Test with wrong list length
      expect(
        () => dataAccess.updateLWWColumn('order_items', ['ORD-2024-006'], 'quantity', 10),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('handles simultaneous user and server updates with different timestamps', () async {
      final compositeKey = {
        'order_id': 'ORD-2024-007',
        'product_id': 99999,
        'delivery_date': DateTime(2024, 7, 10),
      };
      
      // Insert initial data
      await dataAccess.insert('order_items', {
        ...compositeKey,
        'quantity': 5,
        'unit_price': 20.00,
        'notes': 'Multi-field test',
      });

      // Simulate rapid user updates with auto-generated timestamps
      await dataAccess.updateLWWColumn('order_items', compositeKey, 'quantity', 8);
      await Future.delayed(Duration(milliseconds: 1)); // Ensure different timestamps
      await dataAccess.updateLWWColumn('order_items', compositeKey, 'unit_price', 22.00);
      await Future.delayed(Duration(milliseconds: 1));
      await dataAccess.updateLWWColumn('order_items', compositeKey, 'notes', 'User updated notes');

      // Give some buffer time to ensure user timestamps are in the past
      await Future.delayed(Duration(milliseconds: 50));

      // Simulate server updates with explicit timestamps
      final currentTime = DateTime.now().microsecondsSinceEpoch;
      final serverTimestamp1 = (currentTime - 100000).toString(); // Definitely older
      final serverTimestamp2 = (currentTime + 5000).toString(); // Newer
      final serverTimestamp3 = (currentTime + 10000).toString(); // Newest

      // Server updates with different outcomes
      await dataAccess.updateLWWColumn(
        'order_items', compositeKey, 'quantity', 6,
        timestamp: serverTimestamp1,
      ); // Should lose to user (8)

      await dataAccess.updateLWWColumn(
        'order_items', compositeKey, 'unit_price', 25.00,
        timestamp: serverTimestamp2,
      ); // Should win over user (25.00)

      await dataAccess.updateLWWColumn(
        'order_items', compositeKey, 'notes', 'Server final notes',
        timestamp: serverTimestamp3,
      ); // Should win (newest timestamp)

      // Verify outcomes
      final quantityResult = await dataAccess.getLWWColumnValue('order_items', compositeKey, 'quantity');
      final priceResult = await dataAccess.getLWWColumnValue('order_items', compositeKey, 'unit_price');
      final notesResult = await dataAccess.getLWWColumnValue('order_items', compositeKey, 'notes');
      
      expect(quantityResult, equals(8)); // User won
      expect(priceResult, equals(25.00)); // Server won  
      expect(notesResult, equals('Server final notes')); // Server won

      // Verify through getByPrimaryKey as well
      final finalRow = await dataAccess.getByPrimaryKey('order_items', compositeKey);
      expect(finalRow!['quantity'], equals(8));
      expect(finalRow['unit_price'], equals(25.00));
      expect(finalRow['notes'], equals('Server final notes'));
    });
  });
}