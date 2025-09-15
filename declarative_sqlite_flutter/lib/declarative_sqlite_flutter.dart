/// A Flutter package that provides seamless integration of declarative_sqlite 
/// with Flutter widgets, forms, and UI patterns.
/// 
/// This library builds upon the declarative_sqlite package to provide:
/// - Reactive ListView widgets that automatically update when database changes
/// - Reactive list and grid builders with per-item CRUD operations
/// - Enhanced auto-generated forms with modern reactive patterns
/// - Query builder widgets with faceted search capabilities
/// - Hot-swappable queries with proper subscription management
/// - Stream-based UI updates using reactive database functionality
/// - Low-level record builder widgets for custom reactive components
/// 
/// ## Quick Start
/// 
/// ### Option 1: Using DataAccessProvider (Recommended)
/// 
/// Wrap your app with DataAccessProvider to make DataAccess available throughout the widget tree:
/// 
/// ```dart
/// import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
/// 
/// // Setup provider at app root
/// DataAccessProvider(
///   dataAccess: dataAccess,
///   child: MaterialApp(
///     home: MyHomePage(),
///   ),
/// )
/// 
/// // Then use widgets without specifying dataAccess
/// ReactiveListView.builder(
///   tableName: 'users',
///   itemBuilder: (context, user) => ListTile(
///     title: Text(user['name']),
///     subtitle: Text(user['email']),
///   ),
/// )
/// ```
/// 
/// ### Enhanced Reactive Forms (New!)
/// ```dart
/// // Enhanced form with live preview, computed fields, and conditional visibility
/// AutoForm(
///   query: QueryBuilder().selectAll().from('orders'),
///   fields: [
///     AutoFormField.text('customer_name', required: true),
///     AutoFormField.related('customer_id', 
///       relatedTable: 'customers',
///       relatedValueColumn: 'id',
///       relatedDisplayColumn: 'name'),
///     AutoFormField.computed('total_amount',
///       computation: (formData) => 
///         (formData['quantity'] ?? 0) * (formData['unit_price'] ?? 0)),
///     AutoFormField.text('notes', 
///       visibilityCondition: (formData) => formData['customer_type'] == 'premium'),
///   ],
///   livePreview: true, // Updates database immediately
///   onSave: (data) => print('Order saved: $data'),
/// )
/// 
/// // Batch editing for multiple records
/// AutoFormBatch(
///   query: QueryBuilder().selectAll().from('products').where((cb) => cb.eq('category', 'electronics')),
///   fields: [
///     AutoFormField.text('price'),
///     AutoFormField.text('discount_percentage'),
///   ],
///   onBatchSave: (records) => print('Updated ${records.length} products'),
/// )
/// 
/// // Enhanced dialogs with reactive features
/// AutoFormDialog.showCreate(
///   context: context,
///   query: QueryBuilder().selectAll().from('users'),
///   fields: [
///     AutoFormField.text('name', validator: AutoFormValidation.minLength(3)),
///     AutoFormField.text('email', validator: AutoFormValidation.email()),
///   ],
/// )
/// ```
/// 
/// ### Building Reactive Lists with CRUD Operations
/// ```dart
/// // Create a list where each item has CRUD operations (no dataAccess needed with provider)
/// ReactiveRecordListBuilder(
///   tableName: 'users',
///   itemBuilder: (context, recordData) => ListTile(
///     title: Text(recordData['name'] ?? ''),
///     trailing: IconButton(
///       icon: Icon(Icons.edit),
///       onPressed: () => recordData.updateColumn('name', 'Updated'),
///     ),
///   ),
/// )
/// ```
/// 
/// ### Building Reactive Grids
/// ```dart
/// // Create a grid where each item has CRUD operations (no dataAccess needed with provider)
/// ReactiveRecordGridBuilder(
///   tableName: 'products',
///   crossAxisCount: 2,
///   itemBuilder: (context, recordData) => Card(
///     child: Column(
///       children: [
///         Text(recordData['name'] ?? ''),
///         ElevatedButton(
///           onPressed: () => recordData.delete(),
///           child: Text('Delete'),
///         ),
///       ],
///     ),
///   ),
/// )
/// ```
/// 
/// ### Faceted Search with Query Builder
/// ```dart
/// // Build complex queries with faceted search interface
/// QueryBuilderWidget(
///   tableName: 'orders',
///   freeTextSearchColumns: ['customer_name', 'product_name'],
///   fields: [
///     QueryField.multiselect('status', options: ['PENDING', 'SHIPPED', 'DELIVERED']),
///     QueryField.dateRange('order_date'),
///     QueryField.sliderRange('total_amount', min: 0, max: 1000),
///     QueryField.text('customer_name'),
///   ],
///   onQueryChanged: (query) {
///     // Query automatically supports hot swapping
///     setState(() {
///       currentQuery = query;
///     });
///   },
/// )
/// 
/// // Use the query with reactive widgets
/// ReactiveRecordListBuilder(
///   query: currentQuery, // Hot swapping supported!
///   itemBuilder: (context, recordData) => OrderCard(order: recordData),
/// )
/// ```
library declarative_sqlite_flutter;

// Core functionality
export 'src/reactive_list_view.dart';
export 'src/reactive_record_builder.dart';
export 'src/auto_form.dart';
export 'src/sync_status_widget.dart';

// Data access and providers
export 'src/data_access_provider.dart';
export 'src/database_stream_builder.dart';

// Query system
export 'src/database_query.dart';
export 'src/query_builder_widget.dart';

// Utilities and helpers
export 'src/flutter_database_service.dart';
export 'src/widget_helpers.dart';