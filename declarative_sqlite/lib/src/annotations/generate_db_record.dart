/// Annotation to mark a class for DbRecord code generation.
///
/// Classes annotated with @GenerateDbRecord will have typed getters and setters
/// generated automatically based on the table schema.
///
/// Example:
/// ```dart
/// @GenerateDbRecord('users')
/// class User extends DbRecord {
///   User(Map<String, Object?> data, DeclarativeDatabase database)
///       : super(data, 'users', database);
///
///   // The generator creates a `fromMap` constructor on the class itself,
///   // and typed getters/setters in an extension.
///   // No need to write them manually.
/// }
/// ```
class GenerateDbRecord {
  /// The name of the database table this record represents.
  final String tableName;

  /// Creates a GenerateDbRecord annotation.
  ///
  /// [tableName] must match a table defined in your database schema.
  const GenerateDbRecord(this.tableName);
}