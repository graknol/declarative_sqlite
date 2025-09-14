import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Standalone demo showcasing offline-first collaborative data sync
/// This demonstrates the same concepts as the Flutter app but in a console application
void main() async {
  print('🏭 Shop Floor Demo - Declarative SQLite\n');
  print('Demonstrating offline-first collaborative data sync\n');
  
  // Initialize FFI for desktop Dart
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final demo = ShopFloorDemo();
  await demo.runDemo();
}

class ShopFloorDemo {
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
    await _initializeDatabase();
    
    print('📊 Database initialized with shop floor schema\n');
    
    // Demonstrate different scenarios
    await _demonstrateOrderManagement();
    await _demonstrateCollaborativeNotes();
    await _demonstrateConflictResolution();
    await _demonstrateOfflineFirstWorkflow();
    
    print('\n✅ Demo completed successfully!');
    print('📚 This demonstrates the power of declarative_sqlite for offline-first applications.');
    
    await database.close();
  }
  
  Future<void> _initializeDatabase() async {
    // Create comprehensive shop floor schema
    schema = SchemaBuilder()
      // Orders table with GUID primary keys for offline-first
      .table('orders', (table) => table
          .text('id', (col) => col.primaryKey()) // UUID for offline-first
          .text('order_number', (col) => col.notNull().unique())
          .text('customer_name', (col) => col.notNull())
          .text('status', (col) => col.notNull().withDefaultValue('pending'))
          .real('total_amount', (col) => col.withDefaultValue(0.0))
          .text('priority', (col) => col.withDefaultValue('medium'))
          .text('created_at', (col) => col.notNull())
          .text('updated_at', (col) => col.notNull())
          .text('due_date')
          .text('description')
          .index('idx_order_status', ['status'])
          .index('idx_order_priority', ['priority']))
      
      // Order lines with relationship to orders
      .table('order_lines', (table) => table
          .text('id', (col) => col.primaryKey()) // UUID for offline-first
          .text('order_id', (col) => col.notNull())
          .text('item_code', (col) => col.notNull())
          .text('item_name', (col) => col.notNull())
          .integer('quantity', (col) => col.notNull().withDefaultValue(1))
          .real('unit_price', (col) => col.notNull().withDefaultValue(0.0))
          .real('line_total', (col) => col.notNull().withDefaultValue(0.0))
          .text('status', (col) => col.withDefaultValue('pending'))
          .text('created_at', (col) => col.notNull())
          .text('updated_at', (col) => col.notNull())
          .index('idx_order_line_order', ['order_id']))
      
      // Notes with GUID support for offline-first collaborative editing
      .table('notes', (table) => table
          .text('id', (col) => col.primaryKey()) // UUID for offline-first
          .text('order_id', (col) => col.notNull())
          .text('content', (col) => col.notNull())
          .text('author', (col) => col.notNull())
          .text('note_type', (col) => col.withDefaultValue('general'))
          .text('created_at', (col) => col.notNull())
          .text('updated_at', (col) => col.notNull())
          .integer('is_synced', (col) => col.withDefaultValue(0))
          .text('created_on_device')
          .index('idx_note_order', ['order_id']))
      
      // Sync operations tracking for offline scenarios
      .table('sync_operations', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('table_name', (col) => col.notNull())
          .text('record_id', (col) => col.notNull())
          .text('operation', (col) => col.notNull())
          .text('data')
          .text('created_at', (col) => col.notNull())
          .integer('retry_count', (col) => col.withDefaultValue(0))
          .index('idx_sync_table_record', ['table_name', 'record_id']));
    
    // Open in-memory database for demo
    database = await openDatabase(':memory:');
    
    // Apply schema migration
    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);
    
    // Create data access layer
    dataAccess = await DataAccess.create(database: database, schema: schema);
    
    await _createSampleData();
  }
  
  Future<void> _createSampleData() async {
    final now = DateTime.now().toIso8601String();
    
    // Create sample orders with GUIDs
    final order1Id = generateGuid();
    final order2Id = generateGuid();
    
    await dataAccess.insert('orders', {
      'id': order1Id,
      'order_number': 'WO-2024-001',
      'customer_name': 'ABC Manufacturing',
      'status': 'in_progress',
      'total_amount': 15250.00,
      'priority': 'high',
      'created_at': now,
      'updated_at': now,
      'due_date': DateTime.now().add(Duration(days: 7)).toIso8601String(),
      'description': 'Custom machine parts for production line upgrade',
    });
    
    await dataAccess.insert('orders', {
      'id': order2Id,
      'order_number': 'WO-2024-002',
      'customer_name': 'XYZ Industries',
      'status': 'pending',
      'total_amount': 8750.00,
      'priority': 'medium',
      'created_at': now,
      'updated_at': now,
      'due_date': DateTime.now().add(Duration(days: 14)).toIso8601String(),
      'description': 'Replacement components for machinery maintenance',
    });
    
    // Create order lines
    await dataAccess.insert('order_lines', {
      'id': generateGuid(),
      'order_id': order1Id,
      'item_code': 'GEAR-450',
      'item_name': 'Precision Gear Assembly',
      'quantity': 10,
      'unit_price': 1250.00,
      'line_total': 12500.00,
      'status': 'in_progress',
      'created_at': now,
      'updated_at': now,
    });
    
    await dataAccess.insert('order_lines', {
      'id': generateGuid(),
      'order_id': order1Id,
      'item_code': 'BEARING-780',
      'item_name': 'High-Temperature Bearing',
      'quantity': 5,
      'unit_price': 550.00,
      'line_total': 2750.00,
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
    });
  }
  
  Future<void> _demonstrateOrderManagement() async {
    print('🔄 Demonstrating Order Management with Query Builder\n');
    
    // Get all orders
    final allOrders = await dataAccess.getAll('orders');
    print('📋 Total orders: ${allOrders.length}');
    
    for (final order in allOrders) {
      print('   • ${order['order_number']} - ${order['customer_name']} (${order['status']})');
    }
    
    // Demonstrate filtering with query builder concepts
    final highPriorityOrders = await dataAccess.getAllWhere(
      'orders', 
      where: 'priority = ?', 
      whereArgs: ['high']
    );
    print('\\n🔥 High priority orders: ${highPriorityOrders.length}');
    
    final inProgressOrders = await dataAccess.getAllWhere(
      'orders',
      where: 'status = ?',
      whereArgs: ['in_progress']
    );
    print('⚙️  In-progress orders: ${inProgressOrders.length}');
    
    // Demonstrate search functionality  
    final searchResults = await dataAccess.getAllWhere(
      'orders',
      where: 'customer_name LIKE ? OR description LIKE ?',
      whereArgs: ['%Manufacturing%', '%machine%']
    );
    print('🔍 Search results for "Manufacturing" or "machine": ${searchResults.length}');
    
    print('');
  }
  
  Future<void> _demonstrateCollaborativeNotes() async {
    print('📝 Demonstrating Collaborative Notes with GUID Support\\n');
    
    // Get first order for demo
    final orders = await dataAccess.getAll('orders');
    final orderId = orders.first['id'] as String;
    
    // Simulate multiple users adding notes offline with GUIDs
    await _addNote(orderId, 'Quality inspection passed - ready for final assembly', 'Sarah Johnson', 'quality', 'qc-tablet');
    await _addNote(orderId, 'Customer requested expedited delivery for critical deadline', 'John Smith', 'priority', 'main-terminal');
    await _addNote(orderId, 'Material shortage detected - sourcing alternatives', 'Mike Wilson', 'issue', 'mobile-device');
    await _addNote(orderId, 'Assembly completed ahead of schedule', 'Sarah Johnson', 'general', 'qc-tablet');
    
    // Show all notes for the order
    final notes = await dataAccess.getAllWhere(
      'notes',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'created_at DESC'
    );
    
    print('💬 Notes for order ${orders.first['order_number']}:');
    for (final note in notes) {
      final syncStatus = note['is_synced'] == 1 ? '✅ SYNCED' : '⏳ PENDING';
      print('   [${note['note_type'].toString().toUpperCase()}] $syncStatus');
      print('   ${note['content']}');
      print('   — ${note['author']} (${note['created_on_device']})\\n');
    }
  }
  
  Future<void> _demonstrateConflictResolution() async {
    print('⚔️  Demonstrating Conflict Resolution Scenarios\\n');
    
    final orders = await dataAccess.getAll('orders');
    final orderId = orders.first['id'] as String;
    
    print('📊 Original order status: ${orders.first['status']}');
    
    // Simulate concurrent updates from different devices/users
    print('\\n🔄 Simulating concurrent status updates:');
    
    // Update 1: Device A updates to 'completed'
    await dataAccess.updateByPrimaryKey('orders', orderId, {
      'status': 'completed',
      'updated_at': DateTime.now().toIso8601String(),
    });
    print('   Device A: Updated status to "completed"');
    
    // Small delay to ensure different timestamp
    await Future.delayed(Duration(milliseconds: 100));
    
    // Update 2: Device B updates to 'on_hold' (should win due to later timestamp)
    await dataAccess.updateByPrimaryKey('orders', orderId, {
      'status': 'on_hold',  
      'updated_at': DateTime.now().toIso8601String(),
    });
    print('   Device B: Updated status to "on_hold" (later timestamp)');
    
    // Check final result
    final updatedOrder = await dataAccess.getByPrimaryKey('orders', orderId);
    print('\\n✅ Final status after conflict resolution: ${updatedOrder!['status']}');
    print('   (Last-Write-Wins: Device B\'s update prevailed)');
    
    print('');
  }
  
  Future<void> _demonstrateOfflineFirstWorkflow() async {
    print('🌐 Demonstrating Offline-First Workflow\\n');
    
    // Simulate offline operations with sync tracking
    final offlineOrderId = generateGuid();
    final now = DateTime.now().toIso8601String();
    
    print('📱 Simulating offline order creation:');
    
    // Create order offline with GUID
    await dataAccess.insert('orders', {
      'id': offlineOrderId,
      'order_number': 'WO-2024-OFFLINE-001',
      'customer_name': 'Offline Customer Corp',
      'status': 'pending',
      'total_amount': 5500.00,
      'priority': 'medium',
      'created_at': now,
      'updated_at': now,
      'description': 'Order created while offline',
    });
    
    // Track sync operation
    await dataAccess.insert('sync_operations', {
      'table_name': 'orders',
      'record_id': offlineOrderId,
      'operation': 'INSERT',
      'data': '{"offline_created": true}',
      'created_at': now,
      'retry_count': 0,
    });
    
    print('   ✅ Order created with GUID: $offlineOrderId');
    print('   📋 Sync operation tracked for later server upload');
    
    // Add offline notes
    await _addNote(offlineOrderId, 'Created while disconnected from server', 'Field Technician', 'general', 'field-tablet', synced: false);
    await _addNote(offlineOrderId, 'Urgent - needs immediate attention when online', 'Field Technician', 'priority', 'field-tablet', synced: false);
    
    // Show pending sync operations
    final pendingSyncOps = await dataAccess.getAllWhere(
      'sync_operations',
      where: 'retry_count < ?',
      whereArgs: [3], // Show operations with less than 3 retries
    );
    
    final pendingNotes = await dataAccess.getAllWhere(
      'notes',
      where: 'is_synced = ?',
      whereArgs: [0],
    );
    
    print('\\n📊 Offline-first statistics:');
    print('   🔄 Pending sync operations: ${pendingSyncOps.length}');
    print('   📝 Unsynced notes: ${pendingNotes.length}');
    print('   🆔 All records use GUIDs to prevent ID conflicts');
    
    // Simulate successful sync
    print('\\n🌐 Simulating successful sync to server:');
    
    // Mark notes as synced
    for (final note in pendingNotes) {
      await dataAccess.updateByPrimaryKey('notes', note['id'], {
        'is_synced': 1,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
    
    // Remove completed sync operations
    await database.delete('sync_operations', where: 'record_id = ?', whereArgs: [offlineOrderId]);
    
    print('   ✅ All offline data successfully synced to server');
    print('   🗑️  Sync operations cleaned up');
    
    print('');
  }
  
  Future<void> _addNote(String orderId, String content, String author, String noteType, String device, {bool synced = true}) async {
    await dataAccess.insert('notes', {
      'id': generateGuid(),
      'order_id': orderId,
      'content': content,
      'author': author,
      'note_type': noteType,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'is_synced': synced ? 1 : 0,
      'created_on_device': device,
    });
  }
}