import '../files/fileset_field.dart';

/// Utility class for serializing Dart values to SQLite-compatible format
class DatabaseValueSerializer {
  /// Serializes a Dart value for SQLite storage
  /// 
  /// This uses the same logic as DbRecord.setValue for consistency
  static Object? serialize(Object? value) {
    if (value == null) return null;
    
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is FilesetField) {
      return value.toDatabaseValue();
    }
    
    return value;
  }
}