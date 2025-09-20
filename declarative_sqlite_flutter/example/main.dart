import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Declarative SQLite Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: DatabaseProvider(
        schema: (builder) {
          builder.table('work_orders', (table) {
            table.guid('id').notNull();
            table.text('customer_id').notNull();
            table.real('total').notNull().min(0);
            table.date('start_date').notNull();
            table.key(['id']).primary();
          });
        },
        databaseName: 'demo.db',
        child: const WorkOrderListScreen(),
      ),
    );
  }
}

class WorkOrderListScreen extends StatelessWidget {
  const WorkOrderListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Orders'),
      ),
      body: QueryListView<WorkOrder>(
        database: DatabaseProvider.of(context),
        query: (q) => q.from('work_orders'),
        mapper: WorkOrder.fromMap,
        loadingBuilder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
        errorBuilder: (context, error) => Center(
          child: Text(
            'Error: $error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
        itemBuilder: (context, workOrder) => ListTile(
          title: Text('Order ${workOrder.id}'),
          subtitle: Text('Customer: ${workOrder.customerId}'),
          trailing: Text('\$${workOrder.total.toStringAsFixed(2)}'),
          onTap: () async {
            // Example of updating data through the database
            final db = DatabaseProvider.of(context);
            await db.update(
              'work_orders',
              {'total': workOrder.total + 100},
              where: 'id = ?',
              whereArgs: [workOrder.id],
            );
            
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Work order total updated!'),
                ),
              );
            }
          },
        ),
        // Example of using ListView properties
        padding: const EdgeInsets.all(8.0),
        physics: const BouncingScrollPhysics(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addWorkOrder(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addWorkOrder(BuildContext context) async {
    final db = DatabaseProvider.of(context);
    await db.insert('work_orders', {
      'id': 'WO-${DateTime.now().millisecondsSinceEpoch}',
      'customer_id': 'CUST-${DateTime.now().millisecondsSinceEpoch % 1000}',
      'total': 1000.0,
      'start_date': DateTime.now().toIso8601String(),
    });
  }
}

/// Example data model for work orders
class WorkOrder {
  final String id;
  final String customerId;
  final double total;
  final DateTime startDate;

  WorkOrder({
    required this.id,
    required this.customerId,
    required this.total,
    required this.startDate,
  });

  static WorkOrder fromMap(Map<String, Object?> map) {
    return WorkOrder(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      total: (map['total'] as num).toDouble(),
      startDate: DateTime.parse(map['start_date'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'total': total,
      'start_date': startDate.toIso8601String(),
    };
  }
}