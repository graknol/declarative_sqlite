import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';
import '../models/order.dart';
import '../models/order_line.dart';
import '../models/note.dart';

/// Global database service for the shop floor demo app
/// Provides centralized access to the database with offline-first capabilities
/// Now featuring sophisticated dependency-based reactive streams!
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static DatabaseService get instance => _instance;
  
  DatabaseService._internal();
  
  Database? _database;
  DataAccess? _dataAccess;
  ReactiveDataAccess? _reactiveDataAccess;
  SchemaBuilder? _schema;
  
  Database get database {
    if (_database == null) {
      throw StateError('Database not initialized. Call initialize() first.');
    }
    return _database!;
  }
  
  DataAccess get dataAccess {
    if (_dataAccess == null) {
      throw StateError('DataAccess not initialized. Call initialize() first.');
    }
    return _dataAccess!;
  }
  
  ReactiveDataAccess get reactiveDataAccess {
    if (_reactiveDataAccess == null) {
      throw StateError('ReactiveDataAccess not initialized. Call initialize() first.');
    }
    return _reactiveDataAccess!;
  }
  
  /// Initialize the database with shop floor schema
  Future<void> initialize() async {
    if (_database != null) return; // Already initialized
    
    // Create the schema for shop floor application
    _schema = _createShopFloorSchema();
    
    // Open database
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'shop_floor_demo.db');
    
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Schema migration will be handled by SchemaMigrator
      },
    );
    
    // Apply schema migrations
    final migrator = SchemaMigrator();
    await migrator.migrate(_database!, _schema!);
    
    // Create data access layer with LWW support for conflict resolution
    _dataAccess = await DataAccess.create(
      database: _database!,
      schema: _schema!,
    );
    
    // Create reactive data access layer with dependency-based change detection
    _reactiveDataAccess = ReactiveDataAccess(
      dataAccess: _dataAccess!,
      schema: _schema!,
    );
    
    // Initialize with sample data if database is empty
    await _initializeSampleData();
  }
  
  /// Create the comprehensive shop floor schema
  SchemaBuilder _createShopFloorSchema() {
    return SchemaBuilder()
      // Orders table - main entity for tracking work orders
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
          // LWW columns for conflict resolution
          .text('status_lww_timestamp')
          .text('total_amount_lww_timestamp')
          .text('priority_lww_timestamp')
          .index('idx_order_status', ['status'])
          .index('idx_order_priority', ['priority'])
          .index('idx_order_due_date', ['due_date']))
      
      // Order Lines table - individual items within an order
      .table('order_lines', (table) => table
          .text('id', (col) => col.primaryKey()) // UUID for offline-first
          .text('order_id', (col) => col.notNull()) // Foreign key to orders
          .text('item_code', (col) => col.notNull())
          .text('item_name', (col) => col.notNull())
          .integer('quantity', (col) => col.notNull().withDefaultValue(1))
          .real('unit_price', (col) => col.notNull().withDefaultValue(0.0))
          .real('line_total', (col) => col.notNull().withDefaultValue(0.0))
          .text('status', (col) => col.withDefaultValue('pending'))
          .text('created_at', (col) => col.notNull())
          .text('updated_at', (col) => col.notNull())
          // LWW columns for conflict resolution
          .text('quantity_lww_timestamp')
          .text('status_lww_timestamp')
          .index('idx_order_line_order', ['order_id'])
          .index('idx_order_line_status', ['status'])
          .index('idx_order_line_item', ['item_code']))
      
      // Notes table - collaborative notes with offline-first GUID support
      .table('notes', (table) => table
          .text('id', (col) => col.primaryKey()) // UUID for offline-first
          .text('order_id', (col) => col.notNull()) // Foreign key to orders
          .text('content', (col) => col.notNull())
          .text('author', (col) => col.notNull())
          .text('note_type', (col) => col.withDefaultValue('general'))
          .text('created_at', (col) => col.notNull())
          .text('updated_at', (col) => col.notNull())
          .integer('is_synced', (col) => col.withDefaultValue(0)) // For offline tracking
          .text('created_on_device') // Track which device created it
          // LWW columns for conflict resolution
          .text('content_lww_timestamp')
          .index('idx_note_order', ['order_id'])
          .index('idx_note_type', ['note_type'])
          .index('idx_note_synced', ['is_synced']))
      
      // Sync tracking table for managing offline operations
      .table('sync_operations', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('table_name', (col) => col.notNull())
          .text('record_id', (col) => col.notNull())
          .text('operation', (col) => col.notNull()) // INSERT, UPDATE, DELETE
          .text('data') // JSON data for the operation
          .text('created_at', (col) => col.notNull())
          .integer('retry_count', (col) => col.withDefaultValue(0))
          .text('last_error')
          .index('idx_sync_table_record', ['table_name', 'record_id']));
  }
  
  /// Initialize sample data for demonstration
  Future<void> _initializeSampleData() async {
    final orderCount = await dataAccess.count('orders');
    if (orderCount > 0) return; // Already has data
    
    // Create sample orders
    final now = DateTime.now().toIso8601String();
    
    final order1Id = 'order-001-${DateTime.now().millisecondsSinceEpoch}';
    final order2Id = 'order-002-${DateTime.now().millisecondsSinceEpoch}';
    final order3Id = 'order-003-${DateTime.now().millisecondsSinceEpoch}';
    
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
    
    await dataAccess.insert('orders', {
      'id': order3Id,
      'order_number': 'WO-2024-003',
      'customer_name': 'Quality Tools Corp',
      'status': 'completed',
      'total_amount': 3200.00,
      'priority': 'low',
      'created_at': now,
      'updated_at': now,
      'due_date': DateTime.now().subtract(Duration(days: 2)).toIso8601String(),
      'description': 'Standard tool calibration and certification',
    });
    
    // Create sample order lines
    await dataAccess.insert('order_lines', {
      'id': 'line-001-${DateTime.now().millisecondsSinceEpoch}',
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
      'id': 'line-002-${DateTime.now().millisecondsSinceEpoch}',
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
    
    // Create sample notes
    await dataAccess.insert('notes', {
      'id': 'note-001-${DateTime.now().millisecondsSinceEpoch}',
      'order_id': order1Id,
      'content': 'Customer requested expedited delivery for critical production deadline.',
      'author': 'John Smith',
      'note_type': 'priority',
      'created_at': now,
      'updated_at': now,
      'is_synced': 1,
      'created_on_device': 'main-terminal',
    });
    
    await dataAccess.insert('notes', {
      'id': 'note-002-${DateTime.now().millisecondsSinceEpoch}',
      'order_id': order1Id,
      'content': 'Quality inspection passed - ready for final assembly.',
      'author': 'Sarah Johnson',
      'note_type': 'quality',
      'created_at': now,
      'updated_at': now,
      'is_synced': 1,
      'created_on_device': 'qc-tablet',
    });
  }
  
  /// Get all orders with optional filtering - now using reactive streams!
  Stream<List<Order>> watchOrders({
    String? statusFilter,
    String? priorityFilter,
    String? searchQuery,
  }) {
    final whereConditions = <String>[];
    final whereArgs = <dynamic>[];
    
    if (statusFilter != null && statusFilter.isNotEmpty) {
      whereConditions.add('status = ?');
      whereArgs.add(statusFilter);
    }
    
    if (priorityFilter != null && priorityFilter.isNotEmpty) {
      whereConditions.add('priority = ?');
      whereArgs.add(priorityFilter);
    }
    
    if (searchQuery != null && searchQuery.isNotEmpty) {
      whereConditions.add('(order_number LIKE ? OR customer_name LIKE ? OR description LIKE ?)');
      final searchPattern = '%$searchQuery%';
      whereArgs.addAll([searchPattern, searchPattern, searchPattern]);
    }
    
    final whereClause = whereConditions.isNotEmpty ? whereConditions.join(' AND ') : null;
    
    // Use reactive data access to create an intelligent stream
    // This will only update when actual changes affect the query results!
    return reactiveDataAccess.watchTable(
      'orders',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    ).map((rawOrders) => rawOrders.map((data) => Order.fromMap(data)).toList());
  }
  
  /// Legacy method for backwards compatibility
  Future<List<Order>> getOrders({
    String? statusFilter,
    String? priorityFilter,
    String? searchQuery,
  }) async {
    return await watchOrders(
      statusFilter: statusFilter,
      priorityFilter: priorityFilter,
      searchQuery: searchQuery,
    ).first;
  }
  
  /// Get order lines for a specific order - now using reactive streams!
  Stream<List<OrderLine>> watchOrderLines(String orderId) {
    return reactiveDataAccess.watchTable(
      'order_lines',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'created_at ASC',
    ).map((rawOrderLines) => rawOrderLines.map((data) => OrderLine.fromMap(data)).toList());
  }
  
  /// Legacy method for backwards compatibility
  Future<List<OrderLine>> getOrderLines(String orderId) async {
    return await watchOrderLines(orderId).first;
  }
  
  /// Get notes for a specific order - now using reactive streams!
  Stream<List<Note>> watchOrderNotes(String orderId) {
    return reactiveDataAccess.watchTable(
      'notes',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'created_at DESC',
    ).map((rawNotes) => rawNotes.map((data) => Note.fromMap(data)).toList());
  }
  
  /// Legacy method for backwards compatibility
  Future<List<Note>> getOrderNotes(String orderId) async {
    return await watchOrderNotes(orderId).first;
  }
  
  /// Update order status - now with automatic dependency-based stream updates!
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Use reactive data access - streams will be automatically updated
    // based on their dependencies!
    await reactiveDataAccess.updateByPrimaryKey('orders', orderId, {
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
      'status_lww_timestamp': timestamp,
    });
    
    // No need to manually refresh streams - they update automatically! 🎉
  }
  
  /// Add a new note - now with automatic dependency-based stream updates!
  Future<String> addNote(String orderId, String content, String author, {String noteType = 'general'}) async {
    final noteId = 'note-${DateTime.now().millisecondsSinceEpoch}-${orderId.hashCode}';
    final now = DateTime.now().toIso8601String();
    
    // Use reactive data access - streams will be automatically updated
    // based on their dependencies!
    await reactiveDataAccess.insert('notes', {
      'id': noteId,
      'order_id': orderId,
      'content': content,
      'author': author,
      'note_type': noteType,
      'created_at': now,
      'updated_at': now,
      'is_synced': 0, // Mark as not synced for offline-first
      'created_on_device': 'demo-app',
    });
    
    // No need to manually refresh streams - they update automatically! 🎉
    return noteId;
  }
  
  /// Watch order count by status - demonstrates aggregate reactive streams
  Stream<int> watchOrderCountByStatus(String status) {
    return reactiveDataAccess.watchCount(
      'orders',
      where: 'status = ?',
      whereArgs: [status],
    );
  }
  
  /// Watch total order value - demonstrates custom aggregate streams
  Stream<double> watchTotalOrderValue() {
    return reactiveDataAccess.watchAggregate<double>(
      'orders',
      () async {
        final result = await dataAccess.database.rawQuery(
          'SELECT SUM(total_amount) as total FROM orders'
        );
        return (result.first['total'] as num?)?.toDouble() ?? 0.0;
      },
      dependentColumns: ['total_amount'],
    );
  }
  
  /// Get dependency statistics for monitoring
  DependencyStats getDependencyStats() {
    return reactiveDataAccess.getDependencyStats();
  }
  
  /// Clean up resources
  void dispose() {
    _reactiveDataAccess?.dispose();
    _database?.close();
  }
}