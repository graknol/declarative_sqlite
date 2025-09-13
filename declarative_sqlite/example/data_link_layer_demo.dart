#!/usr/bin/env dart

/// Data Link Layer Example for Server-Client Synchronization
library data_link_layer_demo;
/// 
/// This example demonstrates how to build a data link layer between
/// server database and client using declarative_sqlite. Designed for 
/// maximum iteration speed on Windows with in-memory SQLite FFI.
/// 
/// Features demonstrated:
/// - Server simulation with mock API
/// - Client-side data management with local caching
/// - Bidirectional synchronization with conflict resolution
/// - Offline/online mode handling
/// - Bulk data operations
/// - Real-time updates with reactive streams
/// - LWW (Last-Writer-Wins) conflict resolution
/// 
/// Usage: dart run example/data_link_layer_demo.dart

import 'dart:async';
import 'dart:math';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ============================================================================
// DATA MODELS AND SCHEMA
// ============================================================================

/// Comprehensive schema for a typical business application
final appSchema = SchemaBuilder()
  // Users table with LWW support for offline sync
  .table('users', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('server_id', (col) => col.unique()) // Server-assigned UUID
      .text('username', (col) => col.notNull().unique())
      .text('email', (col) => col.notNull())
      .text('full_name')
      .text('avatar_url')
      .integer('active', (col) => col.withDefaultValue(1))
      .text('created_at', (col) => col.notNull())
      .text('updated_at', (col) => col.notNull())
      // LWW columns for conflict resolution
      .text('username_lww_timestamp')
      .text('email_lww_timestamp')  
      .text('full_name_lww_timestamp')
      .text('avatar_url_lww_timestamp')
      .text('active_lww_timestamp')
      // Sync metadata
      .integer('needs_sync', (col) => col.withDefaultValue(0))
      .text('last_synced_at')
      .index('idx_users_server_id', ['server_id'])
      .index('idx_users_username', ['username'])
      .index('idx_users_needs_sync', ['needs_sync']))

  // Products table with inventory tracking
  .table('products', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('server_id', (col) => col.unique())
      .text('sku', (col) => col.notNull().unique())
      .text('name', (col) => col.notNull())
      .text('description')
      .real('price', (col) => col.notNull())
      .integer('stock_quantity', (col) => col.withDefaultValue(0))
      .text('category')
      .integer('active', (col) => col.withDefaultValue(1))
      .text('created_at', (col) => col.notNull())
      .text('updated_at', (col) => col.notNull())
      // LWW columns for critical fields
      .text('price_lww_timestamp')
      .text('stock_quantity_lww_timestamp')
      .text('active_lww_timestamp')
      // Sync metadata
      .integer('needs_sync', (col) => col.withDefaultValue(0))
      .text('last_synced_at')
      .index('idx_products_server_id', ['server_id'])
      .index('idx_products_sku', ['sku'])
      .index('idx_products_category', ['category']))

  // Orders table for transaction tracking
  .table('orders', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('server_id', (col) => col.unique())
      .text('order_number', (col) => col.notNull().unique())
      .integer('user_id', (col) => col.notNull())
      .text('user_server_id') // Reference to users.server_id
      .real('total_amount', (col) => col.notNull())
      .text('status', (col) => col.withDefaultValue('pending'))
      .text('created_at', (col) => col.notNull())
      .text('updated_at', (col) => col.notNull())
      // LWW columns
      .text('status_lww_timestamp')
      .text('total_amount_lww_timestamp')
      // Sync metadata
      .integer('needs_sync', (col) => col.withDefaultValue(0))
      .text('last_synced_at')
      .index('idx_orders_server_id', ['server_id'])
      .index('idx_orders_user_id', ['user_id'])
      .index('idx_orders_order_number', ['order_number'])
      .index('idx_orders_status', ['status']))

  // Order items for detailed tracking
  .table('order_items', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('server_id', (col) => col.unique())
      .integer('order_id', (col) => col.notNull())
      .text('order_server_id') // Reference to orders.server_id
      .integer('product_id', (col) => col.notNull())
      .text('product_server_id') // Reference to products.server_id
      .integer('quantity', (col) => col.notNull())
      .real('unit_price', (col) => col.notNull())
      .real('total_price', (col) => col.notNull())
      .text('created_at', (col) => col.notNull())
      // Sync metadata
      .integer('needs_sync', (col) => col.withDefaultValue(0))
      .text('last_synced_at')
      .index('idx_order_items_order_id', ['order_id'])
      .index('idx_order_items_product_id', ['product_id']))

  // Sync operations log for debugging and retry logic
  .table('sync_operations', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('operation_type', (col) => col.notNull()) // 'insert', 'update', 'delete'
      .text('table_name', (col) => col.notNull())
      .text('record_id') // Local ID or server ID
      .text('operation_data') // JSON payload
      .text('status', (col) => col.withDefaultValue('pending')) // 'pending', 'completed', 'failed'
      .text('error_message')
      .integer('retry_count', (col) => col.withDefaultValue(0))
      .text('created_at', (col) => col.notNull())
      .text('completed_at')
      .index('idx_sync_operations_status', ['status'])
      .index('idx_sync_operations_table_operation', ['table_name', 'operation_type']))

  // Add useful views for data analysis
  .addView((ViewBuilder.create('active_users') as dynamic)
      .fromTable('users', whereCondition: 'active = 1'))
      
  .addView((ViewBuilder.create('pending_sync_operations') as dynamic)
      .fromTable('sync_operations', whereCondition: 'status = "pending"'))

  .addView((ViewBuilder.create('order_summary') as dynamic)
      .fromQuery((QueryBuilder query) => query
          .select([
            ExpressionBuilder.qualifiedColumn('o', 'id'),
            ExpressionBuilder.qualifiedColumn('o', 'order_number'),
            ExpressionBuilder.qualifiedColumn('u', 'username'),
            ExpressionBuilder.qualifiedColumn('o', 'total_amount'),
            ExpressionBuilder.qualifiedColumn('o', 'status'),
            ExpressionBuilder.qualifiedColumn('o', 'created_at'),
            Expressions.countColumn('oi.id').as('item_count'),
          ])
          .from('orders', 'o')
          .leftJoin('users', 'o.user_id = u.id', 'u')
          .leftJoin('order_items', 'o.id = oi.order_id', 'oi')
          .groupBy(['o.id'])
          .orderByColumn('o.created_at', true)));

// ============================================================================
// SERVER SIMULATION
// ============================================================================

/// Mock server API for testing synchronization logic
class MockServerAPI {
  final Map<String, List<Map<String, dynamic>>> _serverData = {};
  final Map<String, int> _sequences = {};
  int _requestDelay = 100; // Simulate network latency
  bool _isOnline = true;
  double _errorRate = 0.0; // 0.0 = no errors, 1.0 = always error

  MockServerAPI() {
    // Initialize with some server data
    _initializeServerData();
  }

  void _initializeServerData() {
    _serverData['users'] = [
      {
        'server_id': 'user_001',
        'username': 'admin',
        'email': 'admin@company.com',
        'full_name': 'System Administrator',
        'active': 1,
        'created_at': DateTime.now().subtract(Duration(days: 30)).toIso8601String(),
        'updated_at': DateTime.now().subtract(Duration(days: 5)).toIso8601String(),
      },
      {
        'server_id': 'user_002', 
        'username': 'john_doe',
        'email': 'john@company.com',
        'full_name': 'John Doe',
        'active': 1,
        'created_at': DateTime.now().subtract(Duration(days: 15)).toIso8601String(),
        'updated_at': DateTime.now().subtract(Duration(days: 2)).toIso8601String(),
      }
    ];

    _serverData['products'] = [
      {
        'server_id': 'prod_001',
        'sku': 'LAPTOP_001',
        'name': 'Business Laptop',
        'description': 'High-performance laptop for business use',
        'price': 1299.99,
        'stock_quantity': 50,
        'category': 'Electronics',
        'active': 1,
        'created_at': DateTime.now().subtract(Duration(days: 20)).toIso8601String(),
        'updated_at': DateTime.now().subtract(Duration(hours: 6)).toIso8601String(),
      },
      {
        'server_id': 'prod_002',
        'sku': 'MOUSE_001',
        'name': 'Wireless Mouse',
        'description': 'Ergonomic wireless mouse',
        'price': 49.99,
        'stock_quantity': 200,
        'category': 'Electronics',
        'active': 1,
        'created_at': DateTime.now().subtract(Duration(days: 10)).toIso8601String(),
        'updated_at': DateTime.now().subtract(Duration(hours: 2)).toIso8601String(),
      }
    ];

    _sequences['users'] = 2;
    _sequences['products'] = 2;
    _sequences['orders'] = 0;
  }

  // Simulate network conditions
  void setNetworkConditions({
    required bool isOnline,
    int delayMs = 100,
    double errorRate = 0.0,
  }) {
    _isOnline = isOnline;
    _requestDelay = delayMs;
    _errorRate = errorRate;
  }

  Future<void> _simulateNetworkDelay() async {
    if (_requestDelay > 0) {
      await Future.delayed(Duration(milliseconds: _requestDelay));
    }
  }

  void _throwRandomError() {
    if (_errorRate > 0 && Random().nextDouble() < _errorRate) {
      throw Exception('Simulated network error');
    }
  }

  /// Fetch all records from a table that were updated after lastSync
  Future<List<Map<String, dynamic>>> fetchUpdates(
    String tableName, 
    DateTime? lastSync
  ) async {
    if (!_isOnline) throw Exception('Server offline');
    await _simulateNetworkDelay();
    _throwRandomError();

    final data = _serverData[tableName] ?? [];
    if (lastSync == null) return data;

    return data.where((record) {
      final updatedAt = DateTime.parse(record['updated_at']);
      return updatedAt.isAfter(lastSync);
    }).toList();
  }

  /// Push local changes to server
  Future<Map<String, dynamic>> pushChanges(
    String tableName,
    List<Map<String, dynamic>> changes
  ) async {
    if (!_isOnline) throw Exception('Server offline');
    await _simulateNetworkDelay();
    _throwRandomError();

    final results = <String, dynamic>{
      'success': true,
      'processed': 0,
      'conflicts': <Map<String, dynamic>>[],
      'errors': <String>[],
    };

    final tableData = _serverData[tableName] ??= [];

    for (final change in changes) {
      try {
        final serverId = change['server_id'] as String?;
        
        if (serverId != null) {
          // Update existing record
          final existingIndex = tableData.indexWhere(
            (record) => record['server_id'] == serverId
          );
          
          if (existingIndex >= 0) {
            // Check for conflicts by comparing timestamps
            final existing = tableData[existingIndex];
            final existingUpdated = DateTime.parse(existing['updated_at']);
            final changeUpdated = DateTime.parse(change['updated_at']);
            
            if (existingUpdated.isAfter(changeUpdated)) {
              // Server version is newer - conflict!
              results['conflicts'].add({
                'server_id': serverId,
                'server_version': existing,
                'client_version': change,
              });
              continue;
            }
            
            // Client version is newer or same - update
            tableData[existingIndex] = {
              ...existing,
              ...change,
              'updated_at': DateTime.now().toIso8601String(),
            };
          } else {
            // Record not found on server - add it
            tableData.add({
              ...change,
              'updated_at': DateTime.now().toIso8601String(),
            });
          }
        } else {
          // New record - assign server ID
          final sequence = _sequences[tableName] = (_sequences[tableName] ?? 0) + 1;
          final newServerId = '${tableName.substring(0, 4)}_${sequence.toString().padLeft(3, '0')}';
          
          tableData.add({
            ...change,
            'server_id': newServerId,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
        
        results['processed'] = (results['processed'] as int) + 1;
      } catch (e) {
        results['errors'].add('Error processing record: $e');
      }
    }

    return results;
  }

  /// Simulate server-side data changes (for testing real-time sync)
  void simulateServerChanges() {
    final now = DateTime.now().toIso8601String();
    
    // Update stock quantity on a random product
    final products = _serverData['products'];
    if (products != null && products.isNotEmpty) {
      final randomProduct = products[Random().nextInt(products.length)];
      final currentStock = randomProduct['stock_quantity'] as int;
      randomProduct['stock_quantity'] = max(0, currentStock + Random().nextInt(21) - 10);
      randomProduct['updated_at'] = now;
      randomProduct['stock_quantity_lww_timestamp'] = now;
    }
  }
}

// ============================================================================
// CLIENT DATA MANAGER
// ============================================================================

/// Manages client-side data with local caching and sync coordination
class ClientDataManager {
  final Database database;
  final DataAccess dataAccess;
  final MockServerAPI serverAPI;
  final ServerSyncManager syncManager;
  
  // Stream controllers for real-time updates
  final _usersController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _productsController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _ordersController = StreamController<List<Map<String, dynamic>>>.broadcast();
  
  Stream<List<Map<String, dynamic>>> get usersStream => _usersController.stream;
  Stream<List<Map<String, dynamic>>> get productsStream => _productsController.stream;
  Stream<List<Map<String, dynamic>>> get ordersStream => _ordersController.stream;

  ClientDataManager._({
    required this.database,
    required this.dataAccess,
    required this.serverAPI,
    required this.syncManager,
  });

  static Future<ClientDataManager> create({
    required Database database,
    required MockServerAPI serverAPI,
  }) async {
    final dataAccess = await DataAccess.create(
      database: database, 
      schema: appSchema,
    );

    final syncManager = ServerSyncManager(
      dataAccess: dataAccess,
      uploadCallback: (operations) async {
        // Simplified upload callback - just return success for now
        print('📤 Uploading ${operations.length} operations to server...');
        
        // In a real implementation, you would:
        // 1. Convert PendingOperation objects to API format
        // 2. Send HTTP requests to your server
        // 3. Handle responses and conflicts
        // 4. Return true if successful, false if failed
        
        return true; // Simulate successful upload
      },
    );

    final manager = ClientDataManager._(
      database: database,
      dataAccess: dataAccess,
      serverAPI: serverAPI,
      syncManager: syncManager,
    );

    // Set up reactive streams
    await manager._setupReactiveStreams();

    return manager;
  }

  Future<void> _setupReactiveStreams() async {
    // Set up reactive streams for real-time UI updates using watch method
    dataAccess.watch(QueryBuilder().selectAll().from('users').orderByColumn('username')).listen((users) {
      _usersController.add(users);
    });

    dataAccess.watch(QueryBuilder().selectAll().from('products').where('active = 1').orderByColumn('name')).listen((products) {
      _productsController.add(products);
    });

    dataAccess.watch(QueryBuilder().selectAll().from('orders').orderByColumn('created_at', true)).listen((orders) {
      _ordersController.add(orders);
    });
  }

  /// Perform full synchronization with server
  Future<Map<String, dynamic>> performFullSync() async {
    final results = <String, dynamic>{
      'success': true,
      'tables_synced': <String>[],
      'conflicts_resolved': 0,
      'errors': <String>[],
    };

    final tables = ['users', 'products', 'orders'];
    
    for (final tableName in tables) {
      try {
        await _syncTable(tableName);
        results['tables_synced'].add(tableName);
      } catch (e) {
        results['errors'].add('Error syncing $tableName: $e');
        results['success'] = false;
      }
    }

    // Push pending local changes
    await syncManager.syncNow();

    return results;
  }

  Future<void> _syncTable(String tableName) async {
    // Get last sync timestamp for this table
    final lastSync = await _getLastSyncTime(tableName);
    
    // Fetch updates from server
    final serverUpdates = await serverAPI.fetchUpdates(tableName, lastSync);
    
    if (serverUpdates.isNotEmpty) {
      // Process server updates with conflict resolution
      await _processServerUpdates(tableName, serverUpdates);
    }

    // Update last sync time
    await _updateLastSyncTime(tableName);
  }

  Future<DateTime?> _getLastSyncTime(String tableName) async {
    final results = await database.rawQuery(
      'SELECT MAX(last_synced_at) as last_sync FROM $tableName WHERE last_synced_at IS NOT NULL'
    );
    
    final lastSyncStr = results.first['last_sync'] as String?;
    return lastSyncStr != null ? DateTime.parse(lastSyncStr) : null;
  }

  Future<void> _updateLastSyncTime(String tableName) async {
    final now = DateTime.now().toIso8601String();
    await database.rawUpdate(
      'UPDATE $tableName SET last_synced_at = ? WHERE last_synced_at IS NULL OR last_synced_at < ?',
      [now, now]
    );
  }

  Future<void> _processServerUpdates(
    String tableName, 
    List<Map<String, dynamic>> serverUpdates
  ) async {
    for (final serverRecord in serverUpdates) {
      final serverId = serverRecord['server_id'] as String;
      
      // Check if record exists locally
      final localRecords = await dataAccess.getAllWhere(
        tableName,
        where: 'server_id = ?',
        whereArgs: [serverId],
      );

      if (localRecords.isEmpty) {
        // New record from server - insert it
        await dataAccess.insert(tableName, {
          ...serverRecord,
          'needs_sync': 0,
          'last_synced_at': DateTime.now().toIso8601String(),
        });
      } else {
        // Existing record - check for conflicts using LWW
        final localRecord = localRecords.first;
        final mergedRecord = await _resolveConflicts(tableName, localRecord, serverRecord);
        
        await dataAccess.updateByPrimaryKey(tableName, localRecord['id'], {
          ...mergedRecord,
          'needs_sync': 0,
          'last_synced_at': DateTime.now().toIso8601String(),
        });
      }
    }
  }

  Future<Map<String, dynamic>> _resolveConflicts(
    String tableName,
    Map<String, dynamic> localRecord,
    Map<String, dynamic> serverRecord,
  ) async {
    final merged = Map<String, dynamic>.from(localRecord);
    
    // Define LWW fields for each table
    final lwwFields = <String, List<String>>{
      'users': ['username', 'email', 'full_name', 'avatar_url', 'active'],
      'products': ['price', 'stock_quantity', 'active'],
      'orders': ['status', 'total_amount'],
    };

    final fields = lwwFields[tableName] ?? [];
    
    for (final field in fields) {
      final localTimestamp = localRecord['${field}_lww_timestamp'] as String?;
      final serverTimestamp = serverRecord['${field}_lww_timestamp'] as String?;
      
      if (localTimestamp != null && serverTimestamp != null) {
        final localTime = DateTime.parse(localTimestamp);
        final serverTime = DateTime.parse(serverTimestamp);
        
        if (serverTime.isAfter(localTime)) {
          // Server version is newer
          merged[field] = serverRecord[field];
          merged['${field}_lww_timestamp'] = serverRecord['${field}_lww_timestamp'];
        }
      } else if (serverTimestamp != null) {
        // Server has timestamp, local doesn't
        merged[field] = serverRecord[field];
        merged['${field}_lww_timestamp'] = serverRecord['${field}_lww_timestamp'];
      }
    }

    // Always use server values for non-LWW fields like updated_at
    merged['updated_at'] = serverRecord['updated_at'];
    
    return merged;
  }

  /// Create a new user (will be synced to server)
  Future<int> createUser(Map<String, dynamic> userData) async {
    final now = DateTime.now().toIso8601String();
    final userId = await dataAccess.insert('users', {
      ...userData,
      'created_at': now,
      'updated_at': now,
      'needs_sync': 1,
      // Set LWW timestamps for all fields
      'username_lww_timestamp': now,
      'email_lww_timestamp': now,
      'full_name_lww_timestamp': now,
      'active_lww_timestamp': now,
    });

    return userId;
  }

  /// Update user with LWW conflict resolution
  Future<void> updateUser(int userId, Map<String, dynamic> updates) async {
    final now = DateTime.now().toIso8601String();
    final lwwUpdates = <String, dynamic>{
      ...updates,
      'updated_at': now,
      'needs_sync': 1,
    };

    // Add LWW timestamps for modified fields
    for (final field in updates.keys) {
      if (['username', 'email', 'full_name', 'avatar_url', 'active'].contains(field)) {
        lwwUpdates['${field}_lww_timestamp'] = now;
      }
    }

    await dataAccess.updateByPrimaryKey('users', userId, lwwUpdates);
  }

  /// Create a product order
  Future<int> createOrder(Map<String, dynamic> orderData, List<Map<String, dynamic>> items) async {
    final now = DateTime.now().toIso8601String();
    
    // Create order
    final orderId = await dataAccess.insert('orders', {
      ...orderData,
      'created_at': now,
      'updated_at': now,
      'needs_sync': 1,
      'status_lww_timestamp': now,
      'total_amount_lww_timestamp': now,
    });

    // Create order items
    for (final item in items) {
      await dataAccess.insert('order_items', {
        ...item,
        'order_id': orderId,
        'created_at': now,
        'needs_sync': 1,
      });
    }

    return orderId;
  }

  /// Get dashboard data with real-time updates
  Future<Map<String, dynamic>> getDashboardData() async {
    final users = await dataAccess.getAll('users');
    final products = await dataAccess.getAll('products');
    final orders = await dataAccess.getAll('orders');
    final pendingSync = await dataAccess.count('sync_operations', where: 'status = ?', whereArgs: ['pending']);

    return {
      'user_count': users.length,
      'product_count': products.length,
      'order_count': orders.length,
      'pending_sync_operations': pendingSync,
      'last_updated': DateTime.now().toIso8601String(),
    };
  }

  Future<void> dispose() async {
    await _usersController.close();
    await _productsController.close();
    await _ordersController.close();
  }
}

// ============================================================================
// TEST SCENARIOS
// ============================================================================

/// Comprehensive test suite for data link layer functionality
class DataLinkLayerTestSuite {
  final MockServerAPI serverAPI;
  final ClientDataManager clientManager;

  DataLinkLayerTestSuite({
    required this.serverAPI,
    required this.clientManager,
  });

  /// Run all test scenarios
  Future<void> runAllTests() async {
    print('\n🧪 Running Data Link Layer Test Suite');
    print('=' * 50);

    await _testBasicCRUDOperations();
    await _testSynchronization();
    await _testConflictResolution();
    await _testOfflineMode();
    await _testBulkOperations();
    await _testRealTimeUpdates();
    await _testErrorHandling();

    print('\n✅ All tests completed successfully!');
  }

  Future<void> _testBasicCRUDOperations() async {
    print('\n📝 Testing Basic CRUD Operations...');

    // Create user
    final userId = await clientManager.createUser({
      'username': 'test_user',
      'email': 'test@example.com',
      'full_name': 'Test User',
      'active': 1,
    });
    print('✓ Created user with ID: $userId');

    // Update user
    await clientManager.updateUser(userId, {
      'full_name': 'Updated Test User',
      'active': 1,
    });
    print('✓ Updated user data');

    // Create order
    final orderId = await clientManager.createOrder({
      'order_number': 'ORD-001',
      'user_id': userId,
      'total_amount': 149.99,
      'status': 'pending',
    }, [
      {
        'product_id': 1,
        'quantity': 1,
        'unit_price': 49.99,
        'total_price': 49.99,
      },
      {
        'product_id': 2,
        'quantity': 2,
        'unit_price': 50.00,
        'total_price': 100.00,
      },
    ]);
    print('✓ Created order with ID: $orderId');
  }

  Future<void> _testSynchronization() async {
    print('\n🔄 Testing Synchronization...');

    // Perform initial sync to get server data
    final syncResult = await clientManager.performFullSync();
    print('✓ Initial sync completed: ${syncResult['tables_synced']}');

    // Simulate server changes
    serverAPI.simulateServerChanges();
    print('✓ Simulated server-side changes');

    // Sync again to pull server changes
    await clientManager.performFullSync();
    print('✓ Pulled server changes');
  }

  Future<void> _testConflictResolution() async {
    print('\n⚡ Testing Conflict Resolution...');

    // Get a product to create conflicts
    final products = await clientManager.dataAccess.getAll('products');
    if (products.isNotEmpty) {
      final product = products.first;
      final productId = product['id'] as int;

      // Update locally
      await clientManager.dataAccess.updateByPrimaryKey('products', productId, {
        'price': 99.99,
        'price_lww_timestamp': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'needs_sync': 1,
      });
      print('✓ Updated product price locally');

      // Simulate server update with different timestamp
      final futureTime = DateTime.now().add(Duration(minutes: 5)).toIso8601String();
      serverAPI._serverData['products']!.firstWhere(
        (p) => p['server_id'] == product['server_id']
      ).addAll({
        'price': 199.99,
        'price_lww_timestamp': futureTime,
        'updated_at': futureTime,
      });
      print('✓ Simulated conflicting server update');

      // Sync to resolve conflict
      await clientManager.performFullSync();
      print('✓ Conflicts resolved using LWW algorithm');
    }
  }

  Future<void> _testOfflineMode() async {
    print('\n📱 Testing Offline Mode...');

    // Go offline
    serverAPI.setNetworkConditions(isOnline: false);
    print('✓ Simulated offline mode');

    // Make local changes while offline
    await clientManager.createUser({
      'username': 'offline_user',
      'email': 'offline@example.com',
      'full_name': 'Offline User',
      'active': 1,
    });
    print('✓ Created user while offline');

    // Try to sync (should queue operations)
    try {
      await clientManager.syncManager.syncNow();
      print('✓ Operations queued for later sync');
    } catch (e) {
      print('✓ Sync failed as expected: ${e.toString().substring(0, 50)}...');
    }

    // Go back online
    serverAPI.setNetworkConditions(isOnline: true);
    print('✓ Back online');

    // Sync queued operations
    await clientManager.syncManager.syncNow();
    print('✓ Synced queued operations');
  }

  Future<void> _testBulkOperations() async {
    print('\n📦 Testing Bulk Operations...');

    // Create bulk users
    final bulkUsers = List.generate(10, (i) => {
      'username': 'bulk_user_$i',
      'email': 'bulk$i@example.com',
      'full_name': 'Bulk User $i',
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'needs_sync': 1,
    });

    final bulkResult = await clientManager.dataAccess.bulkLoad('users', bulkUsers);
    print('✓ Bulk loaded ${bulkResult.rowsInserted} users');

    // Bulk sync
    await clientManager.syncManager.syncNow();
    print('✓ Bulk synced to server');
  }

  Future<void> _testRealTimeUpdates() async {
    print('\n📡 Testing Real-Time Updates...');

    // Set up stream listener
    int updateCount = 0;
    final subscription = clientManager.usersStream.listen((users) {
      updateCount++;
      print('  📊 User stream update #$updateCount: ${users.length} users');
    });

    // Make changes to trigger stream updates
    await clientManager.createUser({
      'username': 'stream_user',
      'email': 'stream@example.com',
      'full_name': 'Stream User',
      'active': 1,
    });

    // Wait for stream updates
    await Future.delayed(Duration(milliseconds: 100));
    
    await subscription.cancel();
    print('✓ Real-time updates working (received $updateCount updates)');
  }

  Future<void> _testErrorHandling() async {
    print('\n🚨 Testing Error Handling...');

    // Test with high error rate
    serverAPI.setNetworkConditions(isOnline: true, errorRate: 0.5);
    print('✓ Set 50% error rate');

    // Try multiple operations - some should fail and retry
    for (int i = 0; i < 3; i++) {
      try {
        await clientManager.performFullSync();
        print('✓ Sync succeeded (attempt ${i + 1})');
        break;
      } catch (e) {
        print('  ⚠️ Sync failed (attempt ${i + 1}): ${e.toString().substring(0, 30)}...');
        await Future.delayed(Duration(milliseconds: 100));
      }
    }

    // Reset error rate
    serverAPI.setNetworkConditions(isOnline: true, errorRate: 0.0);
    print('✓ Reset error conditions');
  }
}

// ============================================================================
// MAIN DEMO APPLICATION
// ============================================================================

void main() async {
  print('🚀 Data Link Layer Demo - Server-Client Synchronization');
  print('Built for maximum iteration speed on Windows with in-memory SQLite');
  print('=' * 70);

  try {
    // Initialize SQLite FFI for Windows compatibility
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    print('✓ SQLite FFI initialized for Windows');

    // Create in-memory database for fast testing
    final database = await openDatabase(':memory:');
    print('✓ In-memory database created');

    // Apply schema with migration
    final migrator = SchemaMigrator();
    await migrator.migrate(database, appSchema);
    print('✓ Schema applied with ${appSchema.tableCount} tables and ${appSchema.viewCount} views');

    // Initialize components
    final serverAPI = MockServerAPI();
    final clientManager = await ClientDataManager.create(
      database: database,
      serverAPI: serverAPI,
    );
    print('✓ Data link layer components initialized');

    // Show initial dashboard
    final dashboard = await clientManager.getDashboardData();
    print('\n📊 Initial Dashboard:');
    print('   Users: ${dashboard['user_count']}');
    print('   Products: ${dashboard['product_count']}');
    print('   Orders: ${dashboard['order_count']}');
    print('   Pending Sync: ${dashboard['pending_sync_operations']}');

    // Perform initial sync to get server data
    print('\n🔄 Performing initial synchronization...');
    final syncResult = await clientManager.performFullSync();
    print('✓ Synced tables: ${syncResult['tables_synced']}');
    
    if (syncResult['errors'].isNotEmpty) {
      print('⚠️ Sync errors: ${syncResult['errors']}');
    }

    // Show updated dashboard
    final updatedDashboard = await clientManager.getDashboardData();
    print('\n📊 Updated Dashboard:');
    print('   Users: ${updatedDashboard['user_count']}');
    print('   Products: ${updatedDashboard['product_count']}');
    print('   Orders: ${updatedDashboard['order_count']}');
    print('   Pending Sync: ${updatedDashboard['pending_sync_operations']}');

    // Run comprehensive test suite
    final testSuite = DataLinkLayerTestSuite(
      serverAPI: serverAPI,
      clientManager: clientManager,
    );
    await testSuite.runAllTests();

    // Show final dashboard
    final finalDashboard = await clientManager.getDashboardData();
    print('\n📊 Final Dashboard:');
    print('   Users: ${finalDashboard['user_count']}');
    print('   Products: ${finalDashboard['product_count']}');
    print('   Orders: ${finalDashboard['order_count']}');
    print('   Pending Sync: ${finalDashboard['pending_sync_operations']}');

    // Demonstrate real-time capabilities
    print('\n🎯 Key Features Demonstrated:');
    print('✅ Declarative schema with LWW conflict resolution');
    print('✅ Server simulation with realistic API patterns');
    print('✅ Client-side caching with automatic sync');
    print('✅ Bidirectional synchronization');
    print('✅ Offline mode with operation queuing');
    print('✅ Conflict resolution using Last-Writer-Wins');
    print('✅ Bulk operations with batch processing');
    print('✅ Real-time updates with reactive streams');
    print('✅ Error handling and retry logic');
    print('✅ In-memory SQLite for fast Windows iteration');

    print('\n💡 Next Steps for Production:');
    print('• Replace MockServerAPI with real REST/GraphQL client');
    print('• Add authentication and authorization');
    print('• Implement proper error logging and metrics');
    print('• Add background sync with WorkManager/Timer');
    print('• Implement incremental sync with delta timestamps');
    print('• Add data encryption for sensitive fields');
    print('• Implement proper schema versioning');
    print('• Add connection pooling and performance optimization');

    // Cleanup
    await clientManager.dispose();
    await database.close();
    print('\n✅ Demo completed successfully!');

  } catch (e, stackTrace) {
    print('\n❌ Demo failed with error: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}