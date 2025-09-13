import 'dart:async';
import 'dart:math';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Advanced Query Builder Demo showcasing complex query scenarios
/// This demonstrates the power of declarative_sqlite's query building capabilities
void main() async {
  print('🔍 Advanced Query Builder Demo - Declarative SQLite\n');
  print('Demonstrating complex queries, joins, aggregations, and views\n');
  
  // Initialize FFI for desktop Dart
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final demo = QueryBuilderDemo();
  await demo.runDemo();
}

class QueryBuilderDemo {
  late Database database;
  late DataAccess dataAccess;
  late SchemaBuilder schema;
  final _random = Random();
  
  /// Simple GUID generation for demo purposes
  String generateGuid() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart = _random.nextInt(999999).toString().padLeft(6, '0');
    return 'guid-$timestamp-$randomPart';
  }
  
  Future<void> runDemo() async {
    await _initializeAdvancedSchema();
    await _createComprehensiveTestData();
    
    print('📊 Database initialized with advanced schema and test data\n');
    
    // Demonstrate progressively complex query scenarios
    await _demonstrateBasicFiltering();
    await _demonstrateAdvancedFiltering();
    await _demonstrateAggregationQueries();
    await _demonstrateJoinOperations();
    await _demonstrateSubqueryPatterns();
    await _demonstrateViewQueries();
    
    print('\n✅ Advanced Query Builder Demo completed!');
    print('📚 This showcases the full power of declarative_sqlite\'s query capabilities.');
    
    await database.close();
  }
  
  Future<void> _initializeAdvancedSchema() async {
    // Create advanced schema with multiple related tables for complex queries
    schema = SchemaBuilder()
      // Customers table
      .table('customers', (table) => table
          .text('id', (col) => col.primaryKey())
          .text('company_name', (col) => col.notNull())
          .text('contact_name', (col) => col.notNull())
          .text('industry', (col) => col.notNull())
          .text('region', (col) => col.notNull())
          .real('credit_limit', (col) => col.withDefaultValue(10000.0))
          .text('status', (col) => col.withDefaultValue('active'))
          .text('created_at', (col) => col.notNull())
          .index('idx_customer_industry', ['industry'])
          .index('idx_customer_region', ['region'])
          .index('idx_customer_status', ['status']))
      
      // Orders table with customer relationship
      .table('orders', (table) => table
          .text('id', (col) => col.primaryKey())
          .text('order_number', (col) => col.notNull().unique())
          .text('customer_id', (col) => col.notNull())
          .text('status', (col) => col.notNull())
          .text('priority', (col) => col.notNull())
          .real('total_amount', (col) => col.withDefaultValue(0.0))
          .text('order_date', (col) => col.notNull())
          .text('due_date')
          .text('completed_date')
          .text('sales_rep', (col) => col.notNull())
          .index('idx_order_customer', ['customer_id'])
          .index('idx_order_status', ['status'])
          .index('idx_order_date', ['order_date'])
          .index('idx_order_sales_rep', ['sales_rep']))
      
      // Order lines with detailed product information
      .table('order_lines', (table) => table
          .text('id', (col) => col.primaryKey())
          .text('order_id', (col) => col.notNull())
          .text('product_code', (col) => col.notNull())
          .text('product_name', (col) => col.notNull())
          .text('category', (col) => col.notNull())
          .integer('quantity', (col) => col.notNull())
          .real('unit_price', (col) => col.notNull())
          .real('discount_percent', (col) => col.withDefaultValue(0.0))
          .real('line_total', (col) => col.notNull())
          .text('status', (col) => col.withDefaultValue('pending'))
          .index('idx_order_line_order', ['order_id'])
          .index('idx_order_line_product', ['product_code'])
          .index('idx_order_line_category', ['category']))
      
      // Products catalog
      .table('products', (table) => table
          .text('code', (col) => col.primaryKey())
          .text('name', (col) => col.notNull())
          .text('category', (col) => col.notNull())
          .text('subcategory', (col) => col.notNull())
          .real('standard_price', (col) => col.notNull())
          .real('cost', (col) => col.notNull())
          .integer('stock_quantity', (col) => col.withDefaultValue(0))
          .integer('reorder_level', (col) => col.withDefaultValue(10))
          .text('supplier', (col) => col.notNull())
          .text('status', (col) => col.withDefaultValue('active'))
          .index('idx_product_category', ['category', 'subcategory'])
          .index('idx_product_supplier', ['supplier']))
      
      // Sales representatives
      .table('sales_reps', (table) => table
          .text('id', (col) => col.primaryKey())
          .text('name', (col) => col.notNull())
          .text('territory', (col) => col.notNull())
          .real('quota', (col) => col.withDefaultValue(100000.0))
          .text('manager', (col) => col.notNull())
          .text('hire_date', (col) => col.notNull())
          .index('idx_sales_rep_territory', ['territory'])
          .index('idx_sales_rep_manager', ['manager']));
    
    // Open in-memory database for demo
    database = await openDatabase(':memory:');
    
    // Apply schema migration
    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);
    
    // Create data access layer
    dataAccess = await DataAccess.create(database: database, schema: schema);
  }
  
  Future<void> _createComprehensiveTestData() async {
    final now = DateTime.now();
    
    // Create sales representatives
    final salesReps = [
      {'id': 'sr-001', 'name': 'Alice Johnson', 'territory': 'North', 'quota': 150000.0, 'manager': 'Director A', 'hire_date': '2022-01-15'},
      {'id': 'sr-002', 'name': 'Bob Smith', 'territory': 'South', 'quota': 120000.0, 'manager': 'Director B', 'hire_date': '2021-06-10'},
      {'id': 'sr-003', 'name': 'Carol Davis', 'territory': 'East', 'quota': 180000.0, 'manager': 'Director A', 'hire_date': '2020-03-22'},
      {'id': 'sr-004', 'name': 'David Wilson', 'territory': 'West', 'quota': 140000.0, 'manager': 'Director C', 'hire_date': '2023-02-01'},
    ];
    
    for (final rep in salesReps) {
      await dataAccess.insert('sales_reps', rep);
    }
    
    // Create customers
    final customers = [
      {'id': generateGuid(), 'company_name': 'TechCorp Industries', 'contact_name': 'John Manager', 'industry': 'Technology', 'region': 'North', 'credit_limit': 50000.0, 'status': 'active', 'created_at': now.subtract(Duration(days: 365)).toIso8601String()},
      {'id': generateGuid(), 'company_name': 'Manufacturing Solutions', 'contact_name': 'Sarah Director', 'industry': 'Manufacturing', 'region': 'South', 'credit_limit': 75000.0, 'status': 'active', 'created_at': now.subtract(Duration(days: 200)).toIso8601String()},
      {'id': generateGuid(), 'company_name': 'Healthcare Systems', 'contact_name': 'Mike VP', 'industry': 'Healthcare', 'region': 'East', 'credit_limit': 100000.0, 'status': 'active', 'created_at': now.subtract(Duration(days: 150)).toIso8601String()},
      {'id': generateGuid(), 'company_name': 'Retail Chain Co', 'contact_name': 'Lisa CEO', 'industry': 'Retail', 'region': 'West', 'credit_limit': 25000.0, 'status': 'active', 'created_at': now.subtract(Duration(days: 80)).toIso8601String()},
      {'id': generateGuid(), 'company_name': 'Financial Services Ltd', 'contact_name': 'Tom CFO', 'industry': 'Finance', 'region': 'North', 'credit_limit': 200000.0, 'status': 'premium', 'created_at': now.subtract(Duration(days: 300)).toIso8601String()},
    ];
    
    final customerIds = <String>[];
    for (final customer in customers) {
      customerIds.add(customer['id'] as String);
      await dataAccess.insert('customers', customer);
    }
    
    // Create products
    final products = [
      {'code': 'TECH-001', 'name': 'Advanced Server Module', 'category': 'Hardware', 'subcategory': 'Servers', 'standard_price': 5000.0, 'cost': 3000.0, 'stock_quantity': 25, 'reorder_level': 5, 'supplier': 'TechSupply Co', 'status': 'active'},
      {'code': 'TECH-002', 'name': 'Network Switch Pro', 'category': 'Hardware', 'subcategory': 'Networking', 'standard_price': 2500.0, 'cost': 1500.0, 'stock_quantity': 50, 'reorder_level': 10, 'supplier': 'NetCorp', 'status': 'active'},
      {'code': 'SOFT-001', 'name': 'Enterprise Software License', 'category': 'Software', 'subcategory': 'Enterprise', 'standard_price': 10000.0, 'cost': 2000.0, 'stock_quantity': 100, 'reorder_level': 20, 'supplier': 'SoftDev Inc', 'status': 'active'},
      {'code': 'MACH-001', 'name': 'Industrial CNC Machine', 'category': 'Machinery', 'subcategory': 'Manufacturing', 'standard_price': 150000.0, 'cost': 100000.0, 'stock_quantity': 3, 'reorder_level': 1, 'supplier': 'MachCorp', 'status': 'active'},
      {'code': 'SERV-001', 'name': 'Professional Consulting', 'category': 'Services', 'subcategory': 'Consulting', 'standard_price': 200.0, 'cost': 100.0, 'stock_quantity': 0, 'reorder_level': 0, 'supplier': 'Internal', 'status': 'active'},
    ];
    
    for (final product in products) {
      await dataAccess.insert('products', product);
    }
    
    // Create orders with varying complexity
    final orders = <Map<String, dynamic>>[];
    for (int i = 0; i < 20; i++) {
      final customerId = customerIds[_random.nextInt(customerIds.length)];
      final salesRep = salesReps[_random.nextInt(salesReps.length)]['id'] as String;
      final orderDate = now.subtract(Duration(days: _random.nextInt(90)));
      final dueDate = orderDate.add(Duration(days: _random.nextInt(30) + 7));
      
      final order = {
        'id': generateGuid(),
        'order_number': 'ORD-2024-${(i + 1).toString().padLeft(3, '0')}',
        'customer_id': customerId,
        'status': ['pending', 'in_progress', 'completed', 'cancelled'][_random.nextInt(4)],
        'priority': ['low', 'medium', 'high', 'urgent'][_random.nextInt(4)],
        'total_amount': 0.0, // Will be calculated from order lines
        'order_date': orderDate.toIso8601String(),
        'due_date': dueDate.toIso8601String(),
        'completed_date': orderDate.add(Duration(days: _random.nextInt(20))).toIso8601String(),
        'sales_rep': salesRep,
      };
      
      orders.add(order);
      await dataAccess.insert('orders', order);
      
      // Create 1-5 order lines per order
      final numLines = _random.nextInt(5) + 1;
      double orderTotal = 0.0;
      
      for (int j = 0; j < numLines; j++) {
        final product = products[_random.nextInt(products.length)];
        final quantity = _random.nextInt(10) + 1;
        final unitPrice = (product['standard_price'] as double) * (0.8 + _random.nextDouble() * 0.4); // Some price variation
        final discount = _random.nextDouble() * 0.15; // Up to 15% discount
        final lineTotal = quantity * unitPrice * (1 - discount);
        orderTotal += lineTotal;
        
        await dataAccess.insert('order_lines', {
          'id': generateGuid(),
          'order_id': order['id'],
          'product_code': product['code'],
          'product_name': product['name'],
          'category': product['category'],
          'quantity': quantity,
          'unit_price': unitPrice,
          'discount_percent': discount * 100,
          'line_total': lineTotal,
          'status': ['pending', 'processing', 'shipped', 'delivered'][_random.nextInt(4)],
        });
      }
      
      // Update order total
      await dataAccess.updateByPrimaryKey('orders', order['id'], {
        'total_amount': orderTotal,
      });
    }
  }
  
  Future<void> _demonstrateBasicFiltering() async {
    print('🔍 Basic Filtering Examples\n');
    
    // Simple status filter
    final pendingOrders = await dataAccess.getAllWhere(
      'orders',
      where: 'status = ?',
      whereArgs: ['pending']
    );
    print('📋 Pending orders: ${pendingOrders.length}');
    
    // Priority filter with multiple conditions
    final urgentOrders = await dataAccess.getAllWhere(
      'orders',
      where: 'priority IN (?, ?)',
      whereArgs: ['high', 'urgent']
    );
    print('🔥 High/Urgent priority orders: ${urgentOrders.length}');
    
    // Date range filtering
    final recentOrders = await dataAccess.getAllWhere(
      'orders',
      where: 'order_date >= ?',
      whereArgs: [DateTime.now().subtract(Duration(days: 30)).toIso8601String()]
    );
    print('📅 Orders from last 30 days: ${recentOrders.length}');
    
    // Amount range filtering
    final largeOrders = await dataAccess.getAllWhere(
      'orders',
      where: 'total_amount > ?',
      whereArgs: [50000.0]
    );
    print('💰 Large orders (>\$50k): ${largeOrders.length}');
    
    print('');
  }
  
  Future<void> _demonstrateAdvancedFiltering() async {
    print('🎯 Advanced Filtering Examples\n');
    
    // Complex multi-condition filtering
    final complexFilter = await dataAccess.getAllWhere(
      'orders',
      where: '''
        status IN (?, ?) 
        AND total_amount > ? 
        AND priority != ?
        AND order_date >= ?
      ''',
      whereArgs: [
        'in_progress', 
        'completed', 
        20000.0, 
        'low',
        DateTime.now().subtract(Duration(days: 60)).toIso8601String()
      ]
    );
    print('🎛️  Complex filter (in_progress/completed, >\$20k, not low priority, last 60 days): ${complexFilter.length}');
    
    // Pattern matching with LIKE
    final patternSearch = await dataAccess.getAllWhere(
      'customers',
      where: 'company_name LIKE ? OR contact_name LIKE ?',
      whereArgs: ['%Tech%', '%Manager%']
    );
    print('🔍 Pattern search (Tech companies or Manager contacts): ${patternSearch.length}');
    
    // Subquery-style filtering using EXISTS pattern
    final customersWithOrders = await database.rawQuery('''
      SELECT DISTINCT c.company_name, c.industry
      FROM customers c
      WHERE EXISTS (
        SELECT 1 FROM orders o 
        WHERE o.customer_id = c.id 
        AND o.status = 'completed'
      )
      ORDER BY c.company_name
    ''');
    print('🏢 Customers with completed orders: ${customersWithOrders.length}');
    
    for (final customer in customersWithOrders) {
      print('   • ${customer['company_name']} (${customer['industry']})');
    }
    
    print('');
  }
  
  Future<void> _demonstrateAggregationQueries() async {
    print('📊 Aggregation Query Examples\n');
    
    // Basic aggregations
    final orderStats = await database.rawQuery('''
      SELECT 
        COUNT(*) as total_orders,
        SUM(total_amount) as total_revenue,
        AVG(total_amount) as average_order_value,
        MIN(total_amount) as smallest_order,
        MAX(total_amount) as largest_order
      FROM orders
      WHERE status != 'cancelled'
    ''');
    
    final stats = orderStats.first;
    print('💼 Order Statistics:');
    print('   📈 Total orders: ${stats['total_orders']}');
    print('   💰 Total revenue: \$${(stats['total_revenue'] as double).toStringAsFixed(2)}');
    print('   📊 Average order value: \$${(stats['average_order_value'] as double).toStringAsFixed(2)}');
    print('   📉 Smallest order: \$${(stats['smallest_order'] as double).toStringAsFixed(2)}');
    print('   📈 Largest order: \$${(stats['largest_order'] as double).toStringAsFixed(2)}');
    
    // Group by aggregations
    final revenueByRegion = await database.rawQuery('''
      SELECT 
        c.region,
        COUNT(o.id) as order_count,
        SUM(o.total_amount) as total_revenue,
        AVG(o.total_amount) as avg_order_value
      FROM customers c
      JOIN orders o ON c.id = o.customer_id
      WHERE o.status = 'completed'
      GROUP BY c.region
      ORDER BY total_revenue DESC
    ''');
    
    print('\\n🌍 Revenue by Region:');
    for (final region in revenueByRegion) {
      print('   ${region['region']}: ${region['order_count']} orders, \$${(region['total_revenue'] as double).toStringAsFixed(2)} revenue');
    }
    
    // Product category performance
    final categoryStats = await database.rawQuery('''
      SELECT 
        ol.category,
        COUNT(*) as line_count,
        SUM(ol.quantity) as total_quantity,
        SUM(ol.line_total) as category_revenue,
        AVG(ol.unit_price) as avg_unit_price
      FROM order_lines ol
      JOIN orders o ON ol.order_id = o.id
      WHERE o.status = 'completed'
      GROUP BY ol.category
      ORDER BY category_revenue DESC
    ''');
    
    print('\\n📦 Product Category Performance:');
    for (final category in categoryStats) {
      print('   ${category['category']}: ${category['line_count']} lines, \$${(category['category_revenue'] as double).toStringAsFixed(2)} revenue');
    }
    
    print('');
  }
  
  Future<void> _demonstrateJoinOperations() async {
    print('🔗 Join Operation Examples\n');
    
    // INNER JOIN: Orders with customer information
    final ordersWithCustomers = await database.rawQuery('''
      SELECT 
        o.order_number,
        o.status,
        o.total_amount,
        c.company_name,
        c.industry,
        c.region
      FROM orders o
      INNER JOIN customers c ON o.customer_id = c.id
      WHERE o.status = 'completed'
      ORDER BY o.total_amount DESC
      LIMIT 5
    ''');
    
    print('🤝 Top 5 Completed Orders with Customer Info:');
    for (final order in ordersWithCustomers) {
      print('   ${order['order_number']}: ${order['company_name']} (${order['industry']}) - \$${(order['total_amount'] as double).toStringAsFixed(2)}');
    }
    
    // LEFT JOIN: Customers with their order counts (including those with no orders)
    final customerOrderCounts = await database.rawQuery('''
      SELECT 
        c.company_name,
        c.industry,
        COUNT(o.id) as order_count,
        COALESCE(SUM(o.total_amount), 0) as total_spent
      FROM customers c
      LEFT JOIN orders o ON c.id = o.customer_id AND o.status != 'cancelled'
      GROUP BY c.id, c.company_name, c.industry
      ORDER BY order_count DESC
    ''');
    
    print('\\n👥 Customer Order Summary:');
    for (final customer in customerOrderCounts) {
      print('   ${customer['company_name']}: ${customer['order_count']} orders, \$${(customer['total_spent'] as double).toStringAsFixed(2)} total');
    }
    
    // Three-way JOIN: Order lines with product and order information
    final detailedOrderLines = await database.rawQuery('''
      SELECT 
        o.order_number,
        ol.product_name,
        ol.quantity,
        ol.unit_price,
        ol.line_total,
        p.category,
        p.supplier,
        c.company_name
      FROM order_lines ol
      INNER JOIN orders o ON ol.order_id = o.id
      INNER JOIN products p ON ol.product_code = p.code
      INNER JOIN customers c ON o.customer_id = c.id
      WHERE ol.line_total > 10000
      ORDER BY ol.line_total DESC
      LIMIT 5
    ''');
    
    print('\\n💎 Top Order Lines (>\$10k):');
    for (final line in detailedOrderLines) {
      print('   ${line['order_number']}: ${line['product_name']} x${line['quantity']} = \$${(line['line_total'] as double).toStringAsFixed(2)}');
      print('      Customer: ${line['company_name']}, Supplier: ${line['supplier']}');
    }
    
    print('');
  }
  
  Future<void> _demonstrateSubqueryPatterns() async {
    print('🔍 Subquery Pattern Examples\n');
    
    // Subquery in WHERE clause
    final topCustomers = await database.rawQuery('''
      SELECT 
        company_name,
        industry,
        region
      FROM customers
      WHERE id IN (
        SELECT customer_id 
        FROM orders 
        WHERE total_amount > (
          SELECT AVG(total_amount) FROM orders WHERE status = 'completed'
        )
      )
      ORDER BY company_name
    ''');
    
    print('🌟 Customers with above-average orders:');
    for (final customer in topCustomers) {
      print('   ${customer['company_name']} (${customer['industry']}, ${customer['region']})');
    }
    
    // Correlated subquery
    final customersWithMultipleOrders = await database.rawQuery('''
      SELECT 
        c.company_name,
        c.industry,
        (SELECT COUNT(*) FROM orders o WHERE o.customer_id = c.id) as order_count,
        (SELECT MAX(o.total_amount) FROM orders o WHERE o.customer_id = c.id) as largest_order
      FROM customers c
      WHERE (SELECT COUNT(*) FROM orders o WHERE o.customer_id = c.id) > 2
      ORDER BY order_count DESC
    ''');
    
    print('\\n🔄 Customers with Multiple Orders:');
    for (final customer in customersWithMultipleOrders) {
      print('   ${customer['company_name']}: ${customer['order_count']} orders, largest: \$${(customer['largest_order'] as double?)?.toStringAsFixed(2) ?? 'N/A'}');
    }
    
    // EXISTS subquery
    final productsInHighValueOrders = await database.rawQuery('''
      SELECT DISTINCT
        p.name,
        p.category,
        p.standard_price
      FROM products p
      WHERE EXISTS (
        SELECT 1 
        FROM order_lines ol
        JOIN orders o ON ol.order_id = o.id
        WHERE ol.product_code = p.code 
        AND o.total_amount > 50000
      )
      ORDER BY p.standard_price DESC
    ''');
    
    print('\\n💰 Products in High-Value Orders (>\$50k):');
    for (final product in productsInHighValueOrders) {
      print('   ${product['name']} (${product['category']}) - \$${(product['standard_price'] as double).toStringAsFixed(2)}');
    }
    
    print('');
  }
  
  Future<void> _demonstrateViewQueries() async {
    print('👁️  View and Complex Query Examples\n');
    
    // Simulate a view: Sales performance summary
    final salesPerformance = await database.rawQuery('''
      SELECT 
        sr.name as sales_rep,
        sr.territory,
        sr.quota,
        COUNT(o.id) as orders_count,
        COALESCE(SUM(o.total_amount), 0) as total_sales,
        ROUND(COALESCE(SUM(o.total_amount), 0) / sr.quota * 100, 2) as quota_achievement
      FROM sales_reps sr
      LEFT JOIN orders o ON sr.id = o.sales_rep AND o.status = 'completed'
      GROUP BY sr.id, sr.name, sr.territory, sr.quota
      ORDER BY quota_achievement DESC
    ''');
    
    print('🎯 Sales Representative Performance:');
    for (final rep in salesPerformance) {
      final achievement = rep['quota_achievement'];
      final achievementValue = achievement is int ? achievement.toDouble() : achievement as double;
      final status = achievementValue >= 100 ? '✅ EXCEEDED' : achievementValue >= 80 ? '⚠️  ON TRACK' : '❌ BEHIND';
      final totalSales = rep['total_sales'];
      final salesValue = totalSales is int ? totalSales.toDouble() : totalSales as double;
      print('   ${rep['sales_rep']} (${rep['territory']}): ${achievementValue}% of quota $status');
      print('      ${rep['orders_count']} orders, \$${salesValue.toStringAsFixed(2)} sales');
    }
    
    // Complex analytical query: Customer segmentation
    final customerSegmentation = await database.rawQuery('''
      WITH customer_metrics AS (
        SELECT 
          c.id,
          c.company_name,
          c.industry,
          COUNT(o.id) as order_count,
          COALESCE(SUM(o.total_amount), 0) as total_revenue,
          COALESCE(AVG(o.total_amount), 0) as avg_order_value,
          MAX(o.order_date) as last_order_date
        FROM customers c
        LEFT JOIN orders o ON c.id = o.customer_id AND o.status = 'completed'
        GROUP BY c.id, c.company_name, c.industry
      )
      SELECT 
        company_name,
        industry,
        order_count,
        total_revenue,
        avg_order_value,
        CASE 
          WHEN total_revenue > 100000 THEN 'VIP'
          WHEN total_revenue > 50000 THEN 'Premium'
          WHEN total_revenue > 10000 THEN 'Standard'
          ELSE 'Basic'
        END as customer_tier
      FROM customer_metrics
      ORDER BY total_revenue DESC
    ''');
    
    print('\\n🏆 Customer Segmentation:');
    for (final customer in customerSegmentation) {
      final revenue = customer['total_revenue'];
      final revenueValue = revenue is int ? revenue.toDouble() : revenue as double;
      print('   ${customer['company_name']} [${customer['customer_tier']}]: \$${revenueValue.toStringAsFixed(2)} total');
    }
    
    // Product inventory analysis
    final inventoryAnalysis = await database.rawQuery('''
      SELECT 
        p.name,
        p.category,
        p.stock_quantity,
        p.reorder_level,
        COALESCE(recent_demand.total_sold, 0) as recent_demand,
        CASE 
          WHEN p.stock_quantity <= p.reorder_level THEN 'REORDER NEEDED'
          WHEN p.stock_quantity <= p.reorder_level * 2 THEN 'LOW STOCK'
          ELSE 'ADEQUATE'
        END as stock_status
      FROM products p
      LEFT JOIN (
        SELECT 
          ol.product_code,
          SUM(ol.quantity) as total_sold
        FROM order_lines ol
        JOIN orders o ON ol.order_id = o.id
        WHERE o.order_date >= date('now', '-30 days')
        GROUP BY ol.product_code
      ) recent_demand ON p.code = recent_demand.product_code
      ORDER BY p.stock_quantity ASC
    ''');
    
    print('\\n📦 Inventory Status Analysis:');
    for (final item in inventoryAnalysis) {
      final status = item['stock_status'] as String;
      final icon = status == 'REORDER NEEDED' ? '🚨' : status == 'LOW STOCK' ? '⚠️' : '✅';
      print('   $icon ${item['name']}: ${item['stock_quantity']} units ($status)');
    }
    
    print('');
  }
}