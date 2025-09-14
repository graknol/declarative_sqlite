/// A Flutter package that provides seamless integration of declarative_sqlite 
/// with Flutter widgets, forms, and UI patterns.
/// 
/// This library builds upon the declarative_sqlite package to provide:
/// - Reactive ListView widgets that automatically update when database changes
/// - Reactive list and grid builders with per-item CRUD operations
/// - Auto-generated forms based on table schemas with validation
/// - Pre-built dashboard widgets for analytics and monitoring
/// - Visual schema browser and data editor
/// - Form widgets with automatic LWW (Last-Write-Wins) column binding  
/// - Input field widgets that sync with database columns
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
/// ### Option 2: Explicit DataAccess Parameter
/// 
/// Pass dataAccess explicitly to each widget:
/// 
/// ```dart
/// // Create a reactive ListView that updates when the database changes
/// ReactiveListView.builder(
///   dataAccess: dataAccess,
///   tableName: 'users',
///   itemBuilder: (context, user) => ListTile(
///     title: Text(user['name']),
///     subtitle: Text(user['email']),
///   ),
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
/// ### Dashboard Components
/// ```dart
/// // Pre-built dashboard widgets for analytics
/// DashboardGrid([
///   DashboardWidgets.countCard(
///     tableName: 'orders',
///     title: 'Total Orders',
///     icon: Icons.shopping_cart,
///   ),
///   DashboardWidgets.statusDistribution(
///     tableName: 'tasks',
///     statusColumn: 'status',
///     title: 'Task Status',
///   ),
///   DashboardWidgets.trendIndicator(
///     tableName: 'sales',
///     title: 'Sales Trend',
///     dateColumn: 'created_at',
///   ),
/// ])
/// ```
/// 
/// ### Schema Inspector
/// ```dart
/// // Visual browser for database schema and data
/// SchemaInspector(
///   title: 'Database Browser',
///   expandDataByDefault: true,
/// )
/// ```
/// 
/// ### Auto-Generated Forms
/// ```dart
/// // Automatically generate a form from table schema with validation
/// AutoForm.fromTable(
///   tableName: 'users',
///   onSave: (data) => print('User saved: $data'),
///   onCancel: () => Navigator.pop(context),
/// )
/// 
/// // Edit existing records
/// AutoForm.fromRecord(
///   tableName: 'users',
///   primaryKey: userId,
///   onSave: (data) => print('User updated: $data'),
/// )
/// 
/// // Show form in a dialog
/// AutoFormDialog.showCreate(
///   context: context,
///   tableName: 'users',
///   onSave: (data) => print('User created: $data'),
/// )
/// ```
/// 
/// ### Form Integration with LWW
/// ```dart
/// // Create a form that automatically syncs with LWW columns (no dataAccess needed with provider)
/// LWWForm(
///   tableName: 'users',
///   primaryKey: userId,
///   child: Column(
///     children: [
///       LWWTextField(
///         columnName: 'name',
///         decoration: InputDecoration(labelText: 'Name'),
///       ),
///       LWWTextField(
///         columnName: 'email',
///         decoration: InputDecoration(labelText: 'Email'),
///       ),
///       LWWSlider(
///         columnName: 'age',
///         min: 0,
///         max: 120,
///       ),
///     ],
///   ),
/// )
/// ```
library declarative_sqlite_flutter;

// Core functionality
export 'src/reactive_list_view.dart';
export 'src/reactive_record_builder.dart';
export 'src/auto_form.dart';
export 'src/schema_inspector.dart';
export 'src/dashboard_widgets.dart';
export 'src/lww_form.dart';
export 'src/lww_text_field.dart';
export 'src/lww_slider.dart';
export 'src/lww_dropdown.dart';

export 'src/data_access_provider.dart';
export 'src/database_stream_builder.dart';
export 'src/reactive_widgets.dart';

// Utilities and helpers
export 'src/flutter_database_service.dart';
export 'src/widget_helpers.dart';