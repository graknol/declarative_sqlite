/// A build generator that generates data classes for interacting with table rows
/// and view rows from declarative_sqlite schemas.
/// 
/// This library analyzes SchemaBuilder metadata and generates type-safe Dart 
/// data classes that provide convenient access to database rows, making it 
/// easier to work with the declarative_sqlite library.
/// 
/// ## Usage
/// 
/// 1. Add this package as a dev_dependency in your pubspec.yaml
/// 2. Create a schema definition file with your database schema
/// 3. Run `dart run build_runner build` to generate data classes
/// 4. Use the generated classes in your application code
/// 
/// ## Example
/// 
/// ```dart
/// // schema.dart
/// import 'package:declarative_sqlite/declarative_sqlite.dart';
/// 
/// final schema = SchemaBuilder()
///   .table('users', (table) => table
///     .autoIncrementPrimaryKey('id')
///     .text('username', (col) => col.notNull())
///     .text('email', (col) => col.unique())
///     .integer('age'));
/// 
/// // Generated: users_data.g.dart
/// class UsersData {
///   const UsersData({
///     required this.id,
///     required this.systemId,
///     required this.systemVersion,
///     required this.username,
///     this.email,
///     this.age,
///   });
/// 
///   final int id;
///   final String systemId;
///   final String systemVersion;
///   final String username;
///   final String? email;
///   final int? age;
/// 
///   Map<String, dynamic> toMap() => {
///     'id': id,
///     'systemId': systemId,
///     'systemVersion': systemVersion,
///     'username': username,
///     'email': email,
///     'age': age,
///   };
/// 
///   static UsersData fromMap(Map<String, dynamic> map) => UsersData(
///     id: map['id'] as int,
///     systemId: map['systemId'] as String,
///     systemVersion: map['systemVersion'] as String,
///     username: map['username'] as String,
///     email: map['email'] as String?,
///     age: map['age'] as int?,
///   );
/// }
/// ```
library declarative_sqlite_generator;

export 'src/schema_code_generator.dart';
export 'src/table_data_class_generator.dart';
export 'src/view_data_class_generator.dart';
export 'src/fileset_field.dart';
export 'src/builder.dart';