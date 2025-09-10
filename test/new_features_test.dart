import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('New Features Tests', () {
    late Database database;
    late DataAccess dataAccess;

    setUpAll(() {
      // Initialize FFI for SQLite
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Create in-memory database for each test
      database = await openDatabase(inMemoryDatabasePath);
    });

    tearDown(() async {
      await database.close();
    });

    group('Date Datatype Support', () {
      late SchemaBuilder schema;

      setUp(() async {
        // Create schema with date columns
        schema = SchemaBuilder()
            .table('events', (table) => table
                .autoIncrementPrimaryKey('id')
                .text('name', (col) => col.notNull())
                .date('created_at', (col) => col.notNull())
                .date('updated_at')
                .text('description'));

        final migrator = SchemaMigrator();
        await migrator.migrate(database, schema);
        dataAccess = DataAccess(database: database, schema: schema);
      });

      test('can create table with date columns', () async {
        // Verify table structure includes date columns with TEXT affinity
        final columns = await database.rawQuery('PRAGMA table_info(events)');
        final dateColumns = columns.where((c) => 
            c['name'] == 'created_at' || c['name'] == 'updated_at').toList();
        
        expect(dateColumns, hasLength(2));
        for (final col in dateColumns) {
          expect(col['type'], equals('TEXT')); // DATE type maps to TEXT in SQLite
        }
      });

      test('can insert and retrieve with DateTime objects', () async {
        final now = DateTime.now();
        final tomorrow = now.add(Duration(days: 1));

        final eventId = await dataAccess.insert('events', {
          'name': 'Test Event',
          'created_at': now,
          'updated_at': tomorrow,
          'description': 'A test event',
        });

        final event = await dataAccess.getByPrimaryKey('events', eventId);
        expect(event, isNotNull);
        expect(event!['name'], equals('Test Event'));
        
        // Verify dates are returned as DateTime objects
        expect(event['created_at'], isA<DateTime>());
        expect(event['updated_at'], isA<DateTime>());
        
        // Check values (allow for slight precision differences)
        final retrievedCreated = event['created_at'] as DateTime;
        final retrievedUpdated = event['updated_at'] as DateTime;
        expect(retrievedCreated.difference(now).inSeconds, lessThan(1));
        expect(retrievedUpdated.difference(tomorrow).inSeconds, lessThan(1));
      });

      test('can insert and retrieve with ISO8601 strings', () async {
        final isoString = '2024-01-15T10:30:00.000Z';
        
        final eventId = await dataAccess.insert('events', {
          'name': 'String Date Event',
          'created_at': isoString,
          'description': 'Event with string date',
        });

        final event = await dataAccess.getByPrimaryKey('events', eventId);
        expect(event, isNotNull);
        
        // Verify date is returned as DateTime object
        expect(event!['created_at'], isA<DateTime>());
        final retrievedDate = event['created_at'] as DateTime;
        expect(retrievedDate.toIso8601String(), equals(isoString));
      });

      test('validates invalid date formats', () async {
        expect(() async => await dataAccess.insert('events', {
          'name': 'Invalid Date Event',
          'created_at': 'not-a-date',
          'description': 'Event with invalid date',
        }), throwsArgumentError);
      });

      test('works with bulkLoad for date columns', () async {
        final dataset = [
          {
            'name': 'Event 1',
            'created_at': DateTime.now(),
            'description': 'First event',
          },
          {
            'name': 'Event 2',
            'created_at': '2024-01-01T00:00:00.000Z',
            'description': 'Second event',
          },
        ];

        final result = await dataAccess.bulkLoad('events', dataset);
        expect(result.rowsInserted, equals(2));
        expect(result.rowsSkipped, equals(0));

        final events = await dataAccess.getAll('events');
        expect(events, hasLength(2));
        
        for (final event in events) {
          expect(event['created_at'], isA<DateTime>());
        }
      });
    });

    group('Composite Primary Keys', () {
      late SchemaBuilder schema;

      setUp(() async {
        // Create schema with composite primary key
        schema = SchemaBuilder()
            .table('user_permissions', (table) => table
                .integer('user_id', (col) => col.notNull())
                .text('permission', (col) => col.notNull())
                .text('granted_by', (col) => col.notNull())
                .date('granted_at', (col) => col.notNull())
                .compositeKey(['user_id', 'permission']));

        final migrator = SchemaMigrator();
        await migrator.migrate(database, schema);
        dataAccess = DataAccess(database: database, schema: schema);
      });

      test('can create table with composite primary key', () async {
        // Verify SQL includes composite primary key constraint
        final schema = await database.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='user_permissions'");
        final sql = schema.first['sql'] as String;
        expect(sql, contains('PRIMARY KEY (user_id, permission)'));
      });

      test('can insert and retrieve by composite primary key', () async {
        await dataAccess.insert('user_permissions', {
          'user_id': 1,
          'permission': 'read',
          'granted_by': 'admin',
          'granted_at': DateTime.now(),
        });

        // Test with Map for composite key
        final permission1 = await dataAccess.getByPrimaryKey('user_permissions', {
          'user_id': 1,
          'permission': 'read',
        });
        expect(permission1, isNotNull);
        expect(permission1!['granted_by'], equals('admin'));

        // Test with List for composite key
        final permission2 = await dataAccess.getByPrimaryKey('user_permissions', [1, 'read']);
        expect(permission2, isNotNull);
        expect(permission2!['granted_by'], equals('admin'));
      });

      test('can update by composite primary key', () async {
        await dataAccess.insert('user_permissions', {
          'user_id': 1,
          'permission': 'read',
          'granted_by': 'admin',
          'granted_at': DateTime.now(),
        });

        final updateCount = await dataAccess.updateByPrimaryKey('user_permissions', {
          'user_id': 1,
          'permission': 'read',
        }, {
          'granted_by': 'superadmin',
        });

        expect(updateCount, equals(1));

        final updated = await dataAccess.getByPrimaryKey('user_permissions', [1, 'read']);
        expect(updated!['granted_by'], equals('superadmin'));
      });

      test('can delete by composite primary key', () async {
        await dataAccess.insert('user_permissions', {
          'user_id': 1,
          'permission': 'read',
          'granted_by': 'admin',
          'granted_at': DateTime.now(),
        });

        final deleteCount = await dataAccess.deleteByPrimaryKey('user_permissions', {
          'user_id': 1,
          'permission': 'read',
        });

        expect(deleteCount, equals(1));

        final deleted = await dataAccess.getByPrimaryKey('user_permissions', [1, 'read']);
        expect(deleted, isNull);
      });

      test('validates composite primary key arguments', () async {
        await dataAccess.insert('user_permissions', {
          'user_id': 1,
          'permission': 'read',
          'granted_by': 'admin',
          'granted_at': DateTime.now(),
        });

        // Test invalid Map - missing column
        expect(() async => await dataAccess.getByPrimaryKey('user_permissions', {
          'user_id': 1,
          // missing 'permission'
        }), throwsArgumentError);

        // Test invalid List - wrong length
        expect(() async => await dataAccess.getByPrimaryKey('user_permissions', [1]), 
               throwsArgumentError);

        // Test invalid type for composite key
        expect(() async => await dataAccess.getByPrimaryKey('user_permissions', 'invalid'), 
               throwsArgumentError);
      });
    });

    group('System Metacolumns', () {
      late SchemaBuilder schema;

      setUp(() async {
        schema = SchemaBuilder()
            .table('products', (table) => table
                .autoIncrementPrimaryKey('id')
                .text('name', (col) => col.notNull())
                .real('price', (col) => col.notNull()));

        final migrator = SchemaMigrator();
        await migrator.migrate(database, schema);
        dataAccess = DataAccess(database: database, schema: schema);
      });

      test('automatically adds systemId and systemVersion columns', () async {
        final columns = await database.rawQuery('PRAGMA table_info(products)');
        final columnNames = columns.map((c) => c['name']).toList();
        
        expect(columnNames, contains('systemId'));
        expect(columnNames, contains('systemVersion'));
        
        // Verify constraints
        final systemIdCol = columns.firstWhere((c) => c['name'] == 'systemId');
        final systemVersionCol = columns.firstWhere((c) => c['name'] == 'systemVersion');
        
        expect(systemIdCol['notnull'], equals(1)); // NOT NULL
        expect(systemVersionCol['notnull'], equals(1)); // NOT NULL
      });

      test('prevents manual specification of system columns', () async {
        expect(() {
          SchemaBuilder()
              .table('test', (table) => table
                  .autoIncrementPrimaryKey('id')
                  .text('systemId', (col) => col.notNull())); // Should throw
        }, throwsArgumentError);

        expect(() {
          SchemaBuilder()
              .table('test', (table) => table
                  .autoIncrementPrimaryKey('id')
                  .text('systemVersion', (col) => col.notNull())); // Should throw
        }, throwsArgumentError);
      });

      test('automatically populates system columns on insert', () async {
        final productId = await dataAccess.insert('products', {
          'name': 'Test Product',
          'price': 19.99,
        });

        final product = await dataAccess.getByPrimaryKey('products', productId);
        expect(product, isNotNull);
        expect(product!['systemId'], isNotNull);
        expect(product['systemVersion'], isNotNull);
        
        // Verify systemId is a valid GUID format
        final systemId = product['systemId'] as String;
        final guidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
        expect(guidPattern.hasMatch(systemId), isTrue);
        
        // Verify systemVersion is a timestamp
        final systemVersion = product['systemVersion'] as String;
        expect(int.tryParse(systemVersion), isNotNull);
      });

      test('updates systemVersion on update operations', () async {
        final productId = await dataAccess.insert('products', {
          'name': 'Test Product',
          'price': 19.99,
        });

        final original = await dataAccess.getByPrimaryKey('products', productId);
        final originalVersion = original!['systemVersion'] as String;

        // Wait a moment to ensure different timestamp
        await Future.delayed(Duration(milliseconds: 1));

        await dataAccess.updateByPrimaryKey('products', productId, {
          'price': 24.99,
        });

        final updated = await dataAccess.getByPrimaryKey('products', productId);
        final updatedVersion = updated!['systemVersion'] as String;

        expect(updatedVersion, isNot(equals(originalVersion)));
        expect(int.parse(updatedVersion) > int.parse(originalVersion), isTrue);
      });

      test('allows importing systemId in bulkLoad', () async {
        final customSystemId = '12345678-1234-4123-8123-123456789012';
        
        final dataset = [
          {
            'name': 'Product 1',
            'price': 10.00,
            'systemId': customSystemId,
          },
          {
            'name': 'Product 2',
            'price': 20.00,
            // No systemId provided - should auto-generate
          },
        ];

        final result = await dataAccess.bulkLoad('products', dataset);
        expect(result.rowsInserted, equals(2));

        final products = await dataAccess.getAll('products');
        expect(products, hasLength(2));
        
        final product1 = products.firstWhere((p) => p['name'] == 'Product 1');
        final product2 = products.firstWhere((p) => p['name'] == 'Product 2');
        
        expect(product1['systemId'], equals(customSystemId));
        expect(product2['systemId'], isNot(equals(customSystemId)));
      });
    });

    group('Enhanced BulkLoad with Upsert', () {
      late SchemaBuilder schema;

      setUp(() async {
        schema = SchemaBuilder()
            .table('inventory', (table) => table
                .text('sku', (col) => col.notNull().primaryKey())
                .text('name', (col) => col.notNull())
                .integer('quantity', (col) => col.notNull())
                .real('price', (col) => col.notNull()));

        final migrator = SchemaMigrator();
        await migrator.migrate(database, schema);
        dataAccess = DataAccess(database: database, schema: schema);
      });

      test('can use upsert mode to insert new rows', () async {
        final dataset = [
          {
            'sku': 'WIDGET-001',
            'name': 'Widget',
            'quantity': 10,
            'price': 19.99,
          },
          {
            'sku': 'GADGET-001',
            'name': 'Gadget',
            'quantity': 5,
            'price': 29.99,
          },
        ];

        final result = await dataAccess.bulkLoad('inventory', dataset, 
            options: BulkLoadOptions(upsertMode: true));
        
        expect(result.rowsInserted, equals(2));
        expect(result.rowsUpdated, equals(0));
        expect(result.rowsSkipped, equals(0));

        final items = await dataAccess.getAll('inventory');
        expect(items, hasLength(2));
      });

      test('can use upsert mode to update existing rows', () async {
        // Insert initial data
        await dataAccess.insert('inventory', {
          'sku': 'WIDGET-001',
          'name': 'Widget',
          'quantity': 10,
          'price': 19.99,
        });

        // Upsert with updated data
        final dataset = [
          {
            'sku': 'WIDGET-001', // Existing SKU
            'name': 'Updated Widget',
            'quantity': 15,
            'price': 22.99,
          },
          {
            'sku': 'GADGET-001', // New SKU
            'name': 'Gadget',
            'quantity': 5,
            'price': 29.99,
          },
        ];

        final result = await dataAccess.bulkLoad('inventory', dataset, 
            options: BulkLoadOptions(upsertMode: true));
        
        expect(result.rowsInserted, equals(1)); // GADGET-001
        expect(result.rowsUpdated, equals(1));  // WIDGET-001
        expect(result.rowsSkipped, equals(0));

        final widget = await dataAccess.getByPrimaryKey('inventory', 'WIDGET-001');
        expect(widget!['name'], equals('Updated Widget'));
        expect(widget['quantity'], equals(15));
        expect(widget['price'], equals(22.99));
      });

      test('can clear table before loading', () async {
        // Insert initial data
        await dataAccess.insert('inventory', {
          'sku': 'OLD-ITEM',
          'name': 'Old Item',
          'quantity': 1,
          'price': 1.00,
        });

        final dataset = [
          {
            'sku': 'NEW-ITEM',
            'name': 'New Item',
            'quantity': 10,
            'price': 10.00,
          },
        ];

        final result = await dataAccess.bulkLoad('inventory', dataset, 
            options: BulkLoadOptions(clearTableFirst: true));
        
        expect(result.rowsInserted, equals(1));
        
        final allItems = await dataAccess.getAll('inventory');
        expect(allItems, hasLength(1));
        expect(allItems.first['sku'], equals('NEW-ITEM'));
      });

      test('validates upsert mode requires primary key', () async {
        // Create table without primary key
        final noPkSchema = SchemaBuilder()
            .table('logs', (table) => table
                .text('message', (col) => col.notNull())
                .integer('timestamp', (col) => col.notNull()));

        final migrator = SchemaMigrator();
        await migrator.migrate(database, noPkSchema);
        final noPkDataAccess = DataAccess(database: database, schema: noPkSchema);

        final dataset = [{'message': 'test', 'timestamp': 123}];

        expect(() async => await noPkDataAccess.bulkLoad('logs', dataset, 
            options: BulkLoadOptions(upsertMode: true)), throwsArgumentError);
      });

      test('works with composite primary keys in upsert mode', () async {
        final compSchema = SchemaBuilder()
            .table('order_items', (table) => table
                .integer('order_id', (col) => col.notNull())
                .text('product_sku', (col) => col.notNull())
                .integer('quantity', (col) => col.notNull())
                .real('unit_price', (col) => col.notNull())
                .compositeKey(['order_id', 'product_sku']));

        final migrator = SchemaMigrator();
        await migrator.migrate(database, compSchema);
        final compDataAccess = DataAccess(database: database, schema: compSchema);

        // Insert initial data
        await compDataAccess.insert('order_items', {
          'order_id': 1,
          'product_sku': 'WIDGET-001',
          'quantity': 2,
          'unit_price': 19.99,
        });

        final dataset = [
          {
            'order_id': 1,
            'product_sku': 'WIDGET-001', // Existing combination
            'quantity': 3, // Updated quantity
            'unit_price': 18.99, // Updated price
          },
          {
            'order_id': 1,
            'product_sku': 'GADGET-001', // New combination
            'quantity': 1,
            'unit_price': 29.99,
          },
        ];

        final result = await compDataAccess.bulkLoad('order_items', dataset, 
            options: BulkLoadOptions(upsertMode: true));
        
        expect(result.rowsInserted, equals(1));
        expect(result.rowsUpdated, equals(1));

        final items = await compDataAccess.getAll('order_items');
        expect(items, hasLength(2));
      });
    });
  });
}