import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Example demonstrating the new ReactiveRecordListBuilder and ReactiveRecordGridBuilder
/// 
/// These widgets provide the building blocks for reactive lists and grids where each
/// item has access to CRUD operations through RecordData wrappers.
class ReactiveRecordBuildersExample extends StatelessWidget {
  final DataAccess dataAccess;

  const ReactiveRecordBuildersExample({
    super.key,
    required this.dataAccess,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reactive Record Builders Example'),
      ),
      body: Column(
        children: [
          // Example 1: List of users with CRUD operations
          Expanded(
            flex: 2,
            child: Card(
              margin: const EdgeInsets.all(8),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Users List (ReactiveRecordListBuilder)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: ReactiveRecordListBuilder(
                      dataAccess: dataAccess,
                      tableName: 'users',
                      orderBy: 'name ASC',
                      itemBuilder: (context, recordData) {
                        return ListTile(
                          title: Text(recordData['name'] ?? 'Unknown'),
                          subtitle: Text(recordData['email'] ?? ''),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () async {
                                  // Update name with current timestamp
                                  final newName = 'Updated ${DateTime.now().millisecondsSinceEpoch}';
                                  await recordData.updateColumn('name', newName);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () async {
                                  // Delete this record
                                  await recordData.delete();
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Example 2: Grid of products with CRUD operations
          Expanded(
            flex: 3,
            child: Card(
              margin: const EdgeInsets.all(8),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Products Grid (ReactiveRecordGridBuilder)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: ReactiveRecordGridBuilder(
                      dataAccess: dataAccess,
                      tableName: 'products',
                      crossAxisCount: 2,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, recordData) {
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  recordData['name'] ?? 'Unknown Product',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '\$${(recordData['price'] as double?)?.toStringAsFixed(2) ?? '0.00'}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  recordData['description'] ?? '',
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () async {
                                          // Update price (simulate discount)
                                          final currentPrice = recordData['price'] as double? ?? 0.0;
                                          final newPrice = (currentPrice * 0.9).round().toDouble();
                                          await recordData.updateColumn('price', newPrice);
                                        },
                                        child: const Text('Discount'),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      onPressed: () async {
                                        // Delete this product
                                        await recordData.delete();
                                      },
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "add_user",
            onPressed: () async {
              // Add a new user
              await dataAccess.insert('users', {
                'name': 'User ${DateTime.now().millisecondsSinceEpoch}',
                'email': 'user${DateTime.now().millisecondsSinceEpoch}@example.com',
              });
            },
            child: const Icon(Icons.person_add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "add_product",
            onPressed: () async {
              // Add a new product
              await dataAccess.insert('products', {
                'name': 'Product ${DateTime.now().millisecondsSinceEpoch}',
                'price': (50 + (DateTime.now().millisecondsSinceEpoch % 100)).toDouble(),
                'description': 'A great product added at ${DateTime.now()}',
              });
            },
            child: const Icon(Icons.add_shopping_cart),
          ),
        ],
      ),
    );
  }
}

/// Usage example showing how to set up the data and use the example
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize SQLite for the platform
  // For actual usage, you would set up your database here
  // This is just showing the pattern
  
  /*
  final schema = SchemaBuilder()
    .table('users', (table) => table
        .autoIncrementPrimaryKey('id')
        .text('name', (col) => col.notNull())
        .text('email', (col) => col.unique())
        .index('idx_users_name', ['name']))
    .table('products', (table) => table
        .autoIncrementPrimaryKey('id')
        .text('name', (col) => col.notNull())
        .real('price', (col) => col.notNull())
        .text('description')
        .index('idx_products_name', ['name']));

  final database = await openDatabase('example.db');
  final migrator = SchemaMigrator();
  await migrator.migrate(database, schema);
  
  final dataAccess = DataAccess(database: database, schema: schema);
  
  runApp(MaterialApp(
    home: ReactiveRecordBuildersExample(dataAccess: dataAccess),
  ));
  */
}