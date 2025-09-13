/// A Flutter package that provides seamless integration of declarative_sqlite 
/// with Flutter widgets, forms, and UI patterns.
/// 
/// This library builds upon the declarative_sqlite package to provide:
/// - Reactive ListView widgets that automatically update when database changes
/// - Reactive list and grid builders with per-item CRUD operations
/// - Form widgets with automatic LWW (Last-Write-Wins) column binding  
/// - Input field widgets that sync with database columns
/// - Stream-based UI updates using reactive database functionality
/// - Low-level record builder widgets for custom reactive components
/// 
/// ## Quick Start
/// 
/// ### Setting up Database-Backed Lists
/// ```dart
/// import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
/// 
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
/// // Create a list where each item has CRUD operations
/// ReactiveRecordListBuilder(
///   dataAccess: dataAccess,
///   tableName: 'users',
///   itemBuilder: (context, recordData) => ListTile(
///     title: Text(recordData.getValue<String>('name') ?? ''),
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
/// // Create a grid where each item has CRUD operations
/// ReactiveRecordGridBuilder(
///   dataAccess: dataAccess,
///   tableName: 'products',
///   crossAxisCount: 2,
///   itemBuilder: (context, recordData) => Card(
///     child: Column(
///       children: [
///         Text(recordData.getValue<String>('name') ?? ''),
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
/// ### Form Integration with LWW
/// ```dart
/// // Create a form that automatically syncs with LWW columns
/// LWWForm(
///   dataAccess: dataAccess,
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
export 'src/lww_form.dart';
export 'src/lww_text_field.dart';
export 'src/lww_slider.dart';
export 'src/lww_dropdown.dart';

export 'src/database_stream_builder.dart';
export 'src/reactive_widgets.dart';

// Utilities and helpers
export 'src/flutter_database_service.dart';
export 'src/widget_helpers.dart';