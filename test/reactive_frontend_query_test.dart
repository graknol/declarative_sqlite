import 'dart:async';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Test suite for frontend queries and views with reactive streams
/// Addressing @graknol's concerns about queries performed in the frontend and views
void main() {
  late Database database;
  late DataAccess dataAccess;
  late ReactiveDataAccess reactiveDataAccess;
  late SchemaBuilder schema;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(':memory:');
    
    schema = SchemaBuilder()
      .table('customers', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull())
          .text('email', (col) => col.unique())
          .text('city', (col) => col.notNull())
          .text('country', (col) => col.notNull())
          .integer('age')
          .text('status', (col) => col.notNull()))
      .table('orders', (table) => table
          .autoIncrementPrimaryKey('id')
          .integer('customer_id', (col) => col.notNull())
          .text('order_date', (col) => col.notNull())
          .real('total_amount', (col) => col.notNull())
          .text('status', (col) => col.notNull())
          .index('idx_customer_id', ['customer_id'])
          .index('idx_status', ['status']))
      .table('order_items', (table) => table
          .autoIncrementPrimaryKey('id')
          .integer('order_id', (col) => col.notNull())
          .text('product_name', (col) => col.notNull())
          .integer('quantity', (col) => col.notNull())
          .real('unit_price', (col) => col.notNull()));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = await DataAccess.create(database: database, schema: schema);
    reactiveDataAccess = ReactiveDataAccess(
      dataAccess: dataAccess,
      schema: schema,
    );

    // Insert test data
    await dataAccess.insert('customers', {
      'name': 'Alice Smith',
      'email': 'alice@example.com',
      'city': 'New York',
      'country': 'USA',
      'age': 30,
      'status': 'active',
    });

    await dataAccess.insert('customers', {
      'name': 'Bob Johnson',
      'email': 'bob@example.com',
      'city': 'Los Angeles',
      'country': 'USA',
      'age': 25,
      'status': 'active',
    });

    // Insert orders
    await dataAccess.insert('orders', {
      'customer_id': 1,
      'order_date': '2024-01-01',
      'total_amount': 100.0,
      'status': 'completed',
    });

    await dataAccess.insert('orders', {
      'customer_id': 2,
      'order_date': '2024-01-02',
      'total_amount': 50.0,
      'status': 'completed',
    });

    // Insert order items
    await dataAccess.insert('order_items', {
      'order_id': 1,
      'product_name': 'Laptop',
      'quantity': 1,
      'unit_price': 100.0,
    });

    await dataAccess.insert('order_items', {
      'order_id': 2,
      'product_name': 'Mouse',
      'quantity': 2,
      'unit_price': 25.0,
    });
  });

  tearDown(() async {
    await reactiveDataAccess.dispose();
    await database.close();
  });

  group('Frontend Raw Query Dependencies', () {
    test('should detect dependencies for simple SELECT queries', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      // Frontend query - simple customer list
      final subscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'customers',
        () => database.rawQuery('SELECT id, name, email FROM customers WHERE status = ?', ['active']),
      ).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Update customer status - should trigger because it affects the WHERE clause
      await reactiveDataAccess.updateByPrimaryKey('customers', 1, {'status': 'inactive'});

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(1)); // One less active customer

      await subscription.cancel();
    });

    test('should detect dependencies for JOIN queries', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      // Frontend query - customer orders with JOIN
      final subscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'customers', // Primary table for dependency tracking
        () => database.rawQuery('''
          SELECT c.name, c.email, COUNT(o.id) as order_count, COALESCE(SUM(o.total_amount), 0) as total_spent
          FROM customers c
          LEFT JOIN orders o ON c.id = o.customer_id
          WHERE c.status = 'active'
          GROUP BY c.id
          ORDER BY total_spent DESC
        '''),
      ).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Add new order - should trigger because it affects the JOIN results
      await reactiveDataAccess.insert('orders', {
        'customer_id': 1,
        'order_date': '2024-01-15',
        'total_amount': 250.0,
        'status': 'completed',
      });

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      
      // Find Alice's record and verify the new totals
      final aliceRecord = result.firstWhere((r) => r['email'] == 'alice@example.com');
      expect(aliceRecord['order_count'], equals(2)); // 1 initial + 1 new
      expect(aliceRecord['total_spent'], equals(350.0)); // 100 + 250

      await subscription.cancel();
    });

    test('should detect dependencies for aggregate queries', () async {
      final completer = Completer<Map<String, dynamic>>();
      var updateCount = 0;

      // Frontend query - daily revenue aggregate
      final subscription = reactiveDataAccess.watchAggregate<Map<String, dynamic>>(
        'orders',
        () async {
          final result = await database.rawQuery('''
            SELECT 
              order_date,
              COUNT(*) as order_count,
              SUM(total_amount) as daily_revenue,
              AVG(total_amount) as avg_order_value
            FROM orders 
            WHERE status = 'completed'
            GROUP BY order_date
            ORDER BY daily_revenue DESC
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

      // Add multiple orders for same date
      await Future.wait([
        reactiveDataAccess.insert('orders', {
          'customer_id': 1,
          'order_date': '2024-01-01',
          'total_amount': 500.0,
          'status': 'completed',
        }),
        reactiveDataAccess.insert('orders', {
          'customer_id': 2,
          'order_date': '2024-01-01',
          'total_amount': 300.0,
          'status': 'completed',
        }),
      ]);

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result['order_date'], equals('2024-01-01')); // Should be the highest revenue day
      expect(result['daily_revenue'], equals(900.0)); // 100 (existing) + 500 + 300

      await subscription.cancel();
    });

    test('should detect dependencies for subquery patterns', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      // Frontend query - customers with above-average order values
      final subscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'customers',
        () => database.rawQuery('''
          SELECT c.name, c.email, AVG(o.total_amount) as avg_order_value
          FROM customers c
          JOIN orders o ON c.id = o.customer_id
          WHERE o.total_amount > (
            SELECT AVG(total_amount) FROM orders WHERE status = 'completed'
          )
          GROUP BY c.id
          ORDER BY avg_order_value DESC
        '''),
      ).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Add a large order that should affect the subquery average
      await reactiveDataAccess.insert('orders', {
        'customer_id': 1,
        'order_date': '2024-01-20',
        'total_amount': 1000.0,
        'status': 'completed',
      });

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.isNotEmpty, isTrue);

      await subscription.cancel();
    });

    test('should detect dependencies for window function queries', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      // Frontend query - customer ranking by total spent
      final subscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'customers',
        () => database.rawQuery('''
          SELECT 
            c.name,
            c.email,
            SUM(o.total_amount) as total_spent,
            ROW_NUMBER() OVER (ORDER BY SUM(o.total_amount) DESC) as spending_rank
          FROM customers c
          LEFT JOIN orders o ON c.id = o.customer_id
          GROUP BY c.id
          ORDER BY total_spent DESC
        '''),
      ).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Add order that should change rankings
      await reactiveDataAccess.insert('orders', {
        'customer_id': 2, // Bob
        'order_date': '2024-01-25',
        'total_amount': 500.0,
        'status': 'completed',
      });

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(2)); // All customers with rankings

      await subscription.cancel();
    });

    test('should detect dependencies for CTE (Common Table Expression) queries', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      // Frontend query - CTE for complex customer analytics
      final subscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'customers',
        () => database.rawQuery('''
          WITH customer_stats AS (
            SELECT 
              c.id,
              c.name,
              c.email,
              COUNT(o.id) as order_count,
              COALESCE(SUM(o.total_amount), 0) as total_spent
            FROM customers c
            LEFT JOIN orders o ON c.id = o.customer_id AND o.status = 'completed'
            GROUP BY c.id
          ),
          avg_stats AS (
            SELECT AVG(total_spent) as avg_customer_spending
            FROM customer_stats
          )
          SELECT 
            cs.name,
            cs.email,
            cs.total_spent,
            CASE 
              WHEN cs.total_spent > avs.avg_customer_spending THEN 'high_value'
              ELSE 'regular'
            END as customer_tier
          FROM customer_stats cs
          CROSS JOIN avg_stats avs
          ORDER BY cs.total_spent DESC
        '''),
      ).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Add high-value order that should affect customer tiers
      await reactiveDataAccess.insert('orders', {
        'customer_id': 2,
        'order_date': '2024-01-30',
        'total_amount': 800.0,
        'status': 'completed',
      });

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(2));
      
      // Check that customer tiers were recalculated
      final hasHighValueCustomer = result.any((r) => r['customer_tier'] == 'high_value');
      expect(hasHighValueCustomer, isTrue);

      await subscription.cancel();
    });
  });

  group('Complex Frontend Application Patterns', () {
    test('should handle dashboard-style multi-metric queries', () async {
      final completer = Completer<Map<String, dynamic>>();
      var updateCount = 0;

      // Frontend query - dashboard metrics
      final subscription = reactiveDataAccess.watchAggregate<Map<String, dynamic>>(
        'orders', // Primary dependency table
        () async {
          final result = await database.rawQuery('''
            SELECT 
              COUNT(DISTINCT c.id) as total_customers,
              COUNT(o.id) as total_orders,
              SUM(o.total_amount) as total_revenue,
              AVG(o.total_amount) as avg_order_value,
              COUNT(CASE WHEN o.status = 'pending' THEN 1 END) as pending_orders,
              COUNT(CASE WHEN c.status = 'active' THEN 1 END) as active_customers
            FROM orders o
            JOIN customers c ON o.customer_id = c.id
          ''');
          return result.first;
        },
      ).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Add new customer and order
      final newCustomerId = await reactiveDataAccess.insert('customers', {
        'name': 'Charlie Brown',
        'email': 'charlie@example.com',
        'city': 'Chicago',
        'country': 'USA',
        'age': 35,
        'status': 'active',
      });

      await reactiveDataAccess.insert('orders', {
        'customer_id': newCustomerId,
        'order_date': '2024-02-01',
        'total_amount': 150.0,
        'status': 'pending',
      });

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result['total_customers'], equals(3)); // Alice, Bob, Charlie
      expect(result['pending_orders'], greaterThan(0));

      await subscription.cancel();
    });

    test('should handle search and filter patterns', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      // Frontend query - search customers by city with orders
      final subscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'customers',
        () => database.rawQuery('''
          SELECT 
            c.id,
            c.name,
            c.email,
            c.city,
            COUNT(o.id) as order_count,
            MAX(o.order_date) as last_order_date
          FROM customers c
          LEFT JOIN orders o ON c.id = o.customer_id
          WHERE c.city LIKE '%York%' OR c.city LIKE '%Angeles%'
          GROUP BY c.id
          HAVING COUNT(o.id) > 0
          ORDER BY last_order_date DESC
        '''),
      ).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Add customer in matching city
      final newCustomerId = await reactiveDataAccess.insert('customers', {
        'name': 'David York',
        'email': 'david@example.com',
        'city': 'New York',
        'country': 'USA',
        'age': 28,
        'status': 'active',
      });

      // Add order for this customer
      await reactiveDataAccess.insert('orders', {
        'customer_id': newCustomerId,
        'order_date': '2024-02-05',
        'total_amount': 75.0,
        'status': 'completed',
      });

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      
      // Should include the new customer with an order
      final hasNewYorkCustomer = result.any((r) => r['city'] == 'New York');
      expect(hasNewYorkCustomer, isTrue);

      await subscription.cancel();
    });

    test('should handle real-time reporting queries', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      // Frontend query - real-time sales report
      final subscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'orders',
        () => database.rawQuery('''
          SELECT 
            strftime('%Y-%m', order_date) as month,
            COUNT(*) as order_count,
            SUM(total_amount) as monthly_revenue,
            COUNT(DISTINCT customer_id) as unique_customers
          FROM orders
          WHERE status IN ('completed', 'shipped')
          GROUP BY strftime('%Y-%m', order_date)
          ORDER BY month DESC
        '''),
      ).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Add orders in new month
      await Future.wait([
        reactiveDataAccess.insert('orders', {
          'customer_id': 1,
          'order_date': '2024-02-10',
          'total_amount': 200.0,
          'status': 'completed',
        }),
        reactiveDataAccess.insert('orders', {
          'customer_id': 2,
          'order_date': '2024-02-15',
          'total_amount': 300.0,
          'status': 'shipped',
        }),
      ]);

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      
      // Should have data for February 2024
      final hasFebData = result.any((r) => r['month'] == '2024-02');
      expect(hasFebData, isTrue);

      await subscription.cancel();
    });
  });
}