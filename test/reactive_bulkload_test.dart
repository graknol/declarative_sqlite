import 'dart:async';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Comprehensive test suite for bulkLoad integration with reactive streams
/// This addresses @graknol's specific concerns about bulkLoad coverage
void main() {
  late Database database;
  
  late DataAccess dataAccess;
  late SchemaBuilder schema;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(':memory:');
    
    schema = SchemaBuilder()
      .table('products', (table) => table
          .text('id', (col) => col.primaryKey()) // String PK for bulk testing
          .text('name', (col) => col.notNull())
          .text('category', (col) => col.notNull())
          .real('price', (col) => col.notNull())
          .integer('stock_quantity')
          .text('description')
          .index('idx_category', ['category'])
          .index('idx_price', ['price']))
      .table('orders', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('order_number', (col) => col.notNull().unique())
          .text('customer_name', (col) => col.notNull())
          .text('status', (col) => col.notNull())
          .real('total_amount')
          .index('idx_status', ['status']));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = await DataAccess.create(database: database, schema: schema);
  });

  tearDown(() async {
    await dataAccess.dispose();
    await database.close();
  });

  group('BulkLoad Stream Integration', () {
    test('bulkLoad insert should trigger whole-table dependencies', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      // Watch the entire products table
      final subscription = dataAccess.watchTable('products').listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Bulk insert products
      await dataAccess.bulkLoad('products', [
        {'id': 'p1', 'name': 'Laptop', 'category': 'electronics', 'price': 999.99, 'stock_quantity': 10, 'description': 'Gaming laptop'},
        {'id': 'p2', 'name': 'Mouse', 'category': 'electronics', 'price': 29.99, 'stock_quantity': 50, 'description': 'Wireless mouse'},
        {'id': 'p3', 'name': 'Desk', 'category': 'furniture', 'price': 199.99, 'stock_quantity': 5, 'description': 'Standing desk'},
      ]);

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(3));

      await subscription.cancel();
    });

    test('bulkLoad upsert should trigger whole-table dependencies', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      // Pre-populate with some data
      await dataAccess.bulkLoad('products', [
        {'id': 'p1', 'name': 'Old Laptop', 'category': 'electronics', 'price': 799.99, 'stock_quantity': 5, 'description': 'Old model'},
      ]);

      // Watch the table
      final subscription = dataAccess.watchTable('products').listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Bulk upsert - should update existing and insert new
      await dataAccess.bulkLoad('products', [
        {'id': 'p1', 'name': 'New Laptop', 'category': 'electronics', 'price': 1199.99, 'stock_quantity': 8, 'description': 'Latest model'},
        {'id': 'p2', 'name': 'Keyboard', 'category': 'electronics', 'price': 89.99, 'stock_quantity': 25, 'description': 'Mechanical keyboard'},
      ], options: BulkLoadOptions(upsertMode: true));

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(2)); // 1 updated + 1 new

      // Verify the update happened
      final updatedProduct = result.firstWhere((p) => p['id'] == 'p1');
      expect(updatedProduct['name'], equals('New Laptop'));
      expect(updatedProduct['price'], equals(1199.99));

      await subscription.cancel();
    });

    test('bulkLoad should trigger where-clause dependencies correctly', () async {
      var electronicsUpdateCount = 0;
      var expensiveUpdateCount = 0;

      final electronicsCompleter = Completer<List<Map<String, dynamic>>>();
      final expensiveCompleter = Completer<List<Map<String, dynamic>>>();

      // Watch electronics products only
      final electronicsSubscription = dataAccess.watchTable(
        'products',
        where: 'category = ?',
        whereArgs: ['electronics'],
      ).listen((data) {
        electronicsUpdateCount++;
        // Complete when we have the expected data, regardless of update count
        if (data.length >= 2 && !electronicsCompleter.isCompleted) {
          electronicsCompleter.complete(data);
        }
      });

      // Watch expensive products only (> $500)
      final expensiveSubscription = dataAccess.watchTable(
        'products',
        where: 'price > ?',
        whereArgs: [500.0],
      ).listen((data) {
        expensiveUpdateCount++;
        // Complete when we have the expected data, regardless of update count
        if (data.length >= 2 && !expensiveCompleter.isCompleted) {
          expensiveCompleter.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Bulk load mixed data
      await dataAccess.bulkLoad('products', [
        {'id': 'p1', 'name': 'Smartphone', 'category': 'electronics', 'price': 699.99, 'stock_quantity': 20}, // Electronics + Expensive
        {'id': 'p2', 'name': 'Charger', 'category': 'electronics', 'price': 19.99, 'stock_quantity': 100}, // Electronics only
        {'id': 'p3', 'name': 'Sofa', 'category': 'furniture', 'price': 899.99, 'stock_quantity': 3}, // Expensive only
        {'id': 'p4', 'name': 'Book', 'category': 'books', 'price': 15.99, 'stock_quantity': 50}, // Neither
      ]);

      final electronicsResult = await electronicsCompleter.future.timeout(Duration(seconds: 3));
      final expensiveResult = await expensiveCompleter.future.timeout(Duration(seconds: 3));

      expect(electronicsUpdateCount, greaterThanOrEqualTo(1));
      expect(expensiveUpdateCount, greaterThanOrEqualTo(1));
      expect(electronicsResult.length, equals(2)); // smartphone + charger
      expect(expensiveResult.length, equals(2)); // smartphone + sofa

      await electronicsSubscription.cancel();
      await expensiveSubscription.cancel();
    });

    test('bulkLoad should trigger column-wise dependencies', () async {
      var priceUpdateCount = 0;
      var stockUpdateCount = 0;

      final priceCompleter = Completer<List<Map<String, dynamic>>>();
      final stockCompleter = Completer<List<Map<String, dynamic>>>();

      // Watch price-related changes only
      final priceSubscription = dataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'products',
        () async {
          final result = await dataAccess.getAllWhere('products');
          return result.map((row) => {'id': row['id'], 'price': row['price']}).toList();
        },
        dependentColumns: ['price'],
      ).listen((data) {
        priceUpdateCount++;
        if (priceUpdateCount == 2) {
          priceCompleter.complete(data);
        }
      });

      // Watch stock-related changes only
      final stockSubscription = dataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'products',
        () async {
          final result = await dataAccess.getAllWhere('products');
          return result.map((row) => {'id': row['id'], 'stock_quantity': row['stock_quantity']}).toList();
        },
        dependentColumns: ['stock_quantity'],
      ).listen((data) {
        stockUpdateCount++;
        if (stockUpdateCount == 2) {
          stockCompleter.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Bulk load affecting both columns
      await dataAccess.bulkLoad('products', [
        {'id': 'p1', 'name': 'Product 1', 'category': 'test', 'price': 100.0, 'stock_quantity': 10},
        {'id': 'p2', 'name': 'Product 2', 'category': 'test', 'price': 200.0, 'stock_quantity': 20},
      ]);

      final priceResult = await priceCompleter.future.timeout(Duration(seconds: 2));
      final stockResult = await stockCompleter.future.timeout(Duration(seconds: 2));

      expect(priceUpdateCount, equals(2));
      expect(stockUpdateCount, equals(2));
      expect(priceResult.length, equals(2));
      expect(stockResult.length, equals(2));

      await priceSubscription.cancel();
      await stockSubscription.cancel();
    });

    test('bulkLoad with batching should still trigger streams correctly', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      final subscription = dataAccess.watchTable('products').listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Large bulk load with small batch size to test batching
      final largeDataset = List.generate(100, (i) => {
        'id': 'bulk_$i',
        'name': 'Bulk Product $i',
        'category': i % 2 == 0 ? 'electronics' : 'furniture',
        'price': (i + 1) * 10.0,
        'stock_quantity': i + 1,
        'description': 'Bulk product description $i',
      });

      await dataAccess.bulkLoad(
        'products', 
        largeDataset,
        options: BulkLoadOptions(batchSize: 10), // Small batch size
      );

      final result = await completer.future.timeout(Duration(seconds: 5));
      expect(updateCount, equals(2));
      expect(result.length, equals(100));

      await subscription.cancel();
    });

    test('bulkLoad with errors should still trigger streams for successful rows', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      final subscription = dataAccess.watchTable('products').listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Bulk load with some invalid data (but allowPartialData enabled)
      try {
        await dataAccess.bulkLoad('products', [
          {'id': 'p1', 'name': 'Valid Product', 'category': 'electronics', 'price': 99.99, 'stock_quantity': 10},
          {'id': 'p2', 'name': 'Missing Category'}, // Missing required fields - should be skipped
          {'id': 'p3', 'name': 'Another Valid', 'category': 'furniture', 'price': 199.99, 'stock_quantity': 5},
        ], options: BulkLoadOptions(allowPartialData: true));
      } catch (e) {
        // Expected to have some errors due to missing required fields
      }

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      // Should have at least the valid products
      expect(result.length, greaterThanOrEqualTo(1));

      await subscription.cancel();
    });

    test('multiple bulkLoad operations should trigger streams for each operation', () async {
      final updates = <int>[];
      final completer = Completer<void>();

      final subscription = dataAccess.watchTable('products').listen((data) {
        updates.add(data.length);
        // Wait for at least 2 updates after the initial one (if any)
        if (updates.length >= 2 && updates.last >= 3) { 
          completer.complete();
        }
      });

      // Wait for potential initial update
      await Future.delayed(Duration(milliseconds: 200));

      // First bulk load
      await dataAccess.bulkLoad('products', [
        {'id': 'batch1_p1', 'name': 'Batch 1 Product 1', 'category': 'electronics', 'price': 100.0, 'stock_quantity': 10},
      ]);

      await Future.delayed(Duration(milliseconds: 100));

      // Second bulk load
      await dataAccess.bulkLoad('products', [
        {'id': 'batch2_p1', 'name': 'Batch 2 Product 1', 'category': 'furniture', 'price': 200.0, 'stock_quantity': 5},
        {'id': 'batch2_p2', 'name': 'Batch 2 Product 2', 'category': 'furniture', 'price': 300.0, 'stock_quantity': 3},
      ]);

      await completer.future.timeout(Duration(seconds: 3));

      expect(updates.length, greaterThanOrEqualTo(2));
      expect(updates.last, equals(3)); // Final count should be 3 products

      await subscription.cancel();
    });

    test('bulkLoad should work with complex aggregate streams', () async {
      final completer = Completer<Map<String, dynamic>>();
      var updateCount = 0;

      // Complex aggregate stream that depends on bulk-loaded data
      final subscription = dataAccess.watchAggregate<Map<String, dynamic>>(
        'products',
        () async {
          final result = await database.rawQuery('''
            SELECT 
              category,
              COUNT(*) as product_count,
              AVG(price) as avg_price,
              SUM(stock_quantity) as total_stock
            FROM products 
            WHERE price > 50
            GROUP BY category
            ORDER BY avg_price DESC
            LIMIT 1
          ''');
          return result.isNotEmpty ? result.first : {};
        },
      ).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Bulk load data that will affect the aggregate
      await dataAccess.bulkLoad('products', [
        {'id': 'luxury1', 'name': 'Premium Laptop', 'category': 'electronics', 'price': 2000.0, 'stock_quantity': 5},
        {'id': 'luxury2', 'name': 'Gaming Monitor', 'category': 'electronics', 'price': 800.0, 'stock_quantity': 10},
        {'id': 'luxury3', 'name': 'Designer Chair', 'category': 'furniture', 'price': 500.0, 'stock_quantity': 3},
        {'id': 'budget1', 'name': 'Cheap Pen', 'category': 'office', 'price': 5.0, 'stock_quantity': 100}, // Below threshold
      ]);

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result['category'], equals('electronics')); // Should have highest avg_price
      expect(result['product_count'], equals(2));

      await subscription.cancel();
    });
  });

  group('BulkLoad Performance and Edge Cases', () {
    test('rapid consecutive bulkLoad operations should be handled gracefully', () async {
      final updates = <int>[];
      final completer = Completer<void>();

      final subscription = dataAccess.watchTable('products').listen((data) {
        updates.add(data.length);
        // Wait for final count of 3 products
        if (data.length >= 3) {
          completer.complete();
        }
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Fire multiple bulk loads rapidly
      final futures = [
        dataAccess.bulkLoad('products', [
          {'id': 'rapid1', 'name': 'Rapid 1', 'category': 'test', 'price': 10.0, 'stock_quantity': 1},
        ]),
        dataAccess.bulkLoad('products', [
          {'id': 'rapid2', 'name': 'Rapid 2', 'category': 'test', 'price': 20.0, 'stock_quantity': 2},
        ]),
        dataAccess.bulkLoad('products', [
          {'id': 'rapid3', 'name': 'Rapid 3', 'category': 'test', 'price': 30.0, 'stock_quantity': 3},
        ]),
      ];

      await Future.wait(futures);
      await completer.future.timeout(Duration(seconds: 5));

      expect(updates.length, greaterThanOrEqualTo(1));
      expect(updates.last, equals(3)); // Final count should be 3

      await subscription.cancel();
    });

    test('bulkLoad should maintain stream consistency under concurrent operations', () async {
      final updates = <List<Map<String, dynamic>>>[];
      final completer = Completer<void>();

      final subscription = dataAccess.watchTable('products').listen((data) {
        updates.add(List.from(data));
        // Wait for final count of 3 products
        if (data.length >= 3) {
          completer.complete();
        }
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Concurrent bulk load and regular operations
      await Future.wait([
        dataAccess.bulkLoad('products', [
          {'id': 'concurrent1', 'name': 'Concurrent 1', 'category': 'test', 'price': 100.0, 'stock_quantity': 10},
          {'id': 'concurrent2', 'name': 'Concurrent 2', 'category': 'test', 'price': 200.0, 'stock_quantity': 20},
        ]),
        dataAccess.insert('products', {
          'id': 'regular1',
          'name': 'Regular Insert',
          'category': 'test',
          'price': 50.0,
          'stock_quantity': 5,
        }),
      ]);

      await completer.future.timeout(Duration(seconds: 5));

      expect(updates.length, greaterThanOrEqualTo(1));
      expect(updates.last.length, equals(3)); // 2 bulk + 1 regular

      await subscription.cancel();
    });
  });
}