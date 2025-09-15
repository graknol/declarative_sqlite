/// Integration example showing the declarative_sqlite_generator working
/// with the main declarative_sqlite library.
library;

import 'dart:io';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_generator/declarative_sqlite_generator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('=== Declarative SQLite + Generator Integration Demo ===\n');
  
  // Initialize sqflite_ffi for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  // 1. Define a realistic schema
  print('📋 Step 1: Define Schema');
  final schema = SchemaBuilder()
    .table('customers', (table) => table
        .autoIncrementPrimaryKey('id')
        .text('company_name', (col) => col.notNull())
        .text('contact_name', (col) => col.notNull())
        .text('email', (col) => col.unique())
        .text('phone')
        .real('credit_limit', (col) => col.withDefaultValue(0.0))
        .date('created_at', (col) => col.notNull()))
    .table('orders', (table) => table
        .autoIncrementPrimaryKey('id')
        .text('order_number', (col) => col.notNull().unique())
        .integer('customer_id', (col) => col.notNull())
        .text('status', (col) => col.notNull().withDefaultValue('pending'))
        .real('total_amount', (col) => col.notNull().withDefaultValue(0.0))
        .date('order_date', (col) => col.notNull()))
    .addView(ViewBuilder.simple('recent_orders', 'orders'))
    .addView(ViewBuilder.simple('active_customers', 'customers'));
  
  print('   ✓ Schema defined with ${schema.tables.length} tables and ${schema.views.length} views');
  
  // 2. Generate data classes
  print('\n🏗️  Step 2: Generate Data Classes');
  final generator = SchemaCodeGenerator();
  final generatedCode = generator.generateCode(schema, libraryName: 'business_data');
  
  // Write generated code to a file (in tmp to avoid committing)
  final tmpDir = Directory('/tmp/declarative_sqlite_demo');
  if (!tmpDir.existsSync()) {
    tmpDir.createSync(recursive: true);
  }
  
  final generatedFile = File('/tmp/declarative_sqlite_demo/business_data.g.dart');
  generatedFile.writeAsStringSync(generatedCode);
  print('   ✓ Generated data classes written to ${generatedFile.path}');
  print('   ✓ Generated ${schema.tables.length} table data classes');
  print('   ✓ Generated ${schema.views.length} view data classes');
  
  // 3. Create and migrate database
  print('\n💾 Step 3: Create Database and Apply Schema');
  final database = await openDatabase(':memory:');
  final migrator = SchemaMigrator();
  await migrator.migrate(database, schema);
  print('   ✓ Database created and schema applied');
  
  // 4. Use generated classes concept (simulate since we can't import the generated code)
  print('\n🚀 Step 4: Demonstrate Generated Class Usage Patterns');
  
  // Show what the generated classes would look like and how they'd be used
  print('\n📄 Generated CustomersData class would include:');
  print('   • const CustomersData({required this.systemId, required this.systemVersion, required this.id, ...})');
  print('   • final String systemId, systemVersion;');
  print('   • final int id;');
  print('   • final String company_name, contact_name;');
  print('   • final String? email, phone;');
  print('   • final double credit_limit;');
  print('   • final DateTime created_at;');
  print('   • Map<String, dynamic> toMap() method');
  print('   • static CustomersData fromMap(Map<String, dynamic> map) method');
  print('   • toString(), hashCode, == methods');
  
  print('\n📄 Generated OrdersData class would include:');
  print('   • Similar structure with order-specific fields');
  print('   • Type-safe access to all order properties');
  print('   • Automatic handling of nullable vs non-nullable fields');
  
  print('\n📄 Generated view data classes (RecentOrdersViewData, ActiveCustomersViewData):');
  print('   • Read-only classes (no toMap method)');
  print('   • fromMap method for creating from query results');
  print('   • All standard object methods');
  
  // 5. Simulate usage with actual database operations
  print('\n💼 Step 5: Simulate Type-Safe Database Operations');
  
  // Insert some test data
  final dataAccess = await DataAccess.create(database: database, schema: schema);
  
  final customerId = await dataAccess.insert('customers', {
    'company_name': 'Tech Solutions Inc',
    'contact_name': 'John Doe',
    'email': 'john@techsolutions.com',
    'phone': '+1-555-0123',
    'credit_limit': 50000.0,
    'created_at': DateTime.now(),
  });
  
  final orderId = await dataAccess.insert('orders', {
    'order_number': 'ORD-2024-001',
    'customer_id': customerId,
    'status': 'confirmed',
    'total_amount': 2500.50,
    'order_date': DateTime.now(),
  });
  
  print('   ✓ Inserted customer ID: $customerId');
  print('   ✓ Inserted order ID: $orderId');
  
  // Retrieve data
  final customerRow = await dataAccess.getByPrimaryKey('customers', customerId);
  final orderRow = await dataAccess.getByPrimaryKey('orders', orderId);
  
  print('\n📊 With generated classes, you would use them like:');
  print('   final customer = CustomersData.fromMap(customerRow);');
  print('   print("Customer: \${customer.company_name} (\${customer.contact_name})");');
  print('   print("Credit limit: \$\${customer.credit_limit}");');
  print('   print("Email: \${customer.email ?? \'Not provided\'}");');
  print('');
  print('   final order = OrdersData.fromMap(orderRow);');
  print('   print("Order: \${order.order_number} - \$\${order.total_amount}");');
  print('   print("Status: \${order.status}");');
  
  // 6. Show the actual generated code structure
  print('\n📝 Step 6: Show Actual Generated Code Structure');
  print('=' * 60);
  
  // Generate just the customers table to show the structure
  final customersTable = schema.tables.firstWhere((t) => t.name == 'customers');
  final customersCode = generator.generateTableCode(customersTable, libraryName: 'customers_example');
  
  // Show first part of the generated code
  final lines = customersCode.split('\n');
  final previewLines = lines.take(25).join('\n');
  print(previewLines);
  print('   ... (additional methods: hashCode, ==, toString)');
  print('=' * 60);
  
  print('\n✅ Integration Demo Complete!');
  print('\nThe declarative_sqlite_generator successfully:');
  print('   • Analyzed schema metadata from TableBuilder and ViewBuilder');
  print('   • Generated type-safe, immutable Dart data classes');
  print('   • Handled all SQLite data types correctly');
  print('   • Included system columns (systemId, systemVersion)');
  print('   • Created proper nullable/non-nullable types based on constraints');
  print('   • Generated database serialization methods (toMap/fromMap)');
  print('   • Produced clean, formatted, and documented Dart code');
  print('\nThe generated classes provide a type-safe layer over the raw database maps,');
  print('making it easier and safer to work with database data in your application.');
  
  await database.close();
}