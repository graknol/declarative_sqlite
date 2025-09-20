import 'package:declarative_sqlite/src/database.dart';
import 'package:declarative_sqlite/src/files/fileset_field.dart';

/// Base class for mapping database rows to typed objects.
///
/// Generated code will create subclasses of this for each table/view.
abstract class DataMapper<T> {
  String get tableName;

  /// Creates an instance of [T] from a database row map.
  T fromMap(Map<String, dynamic> map);
}

/// Utility class for converting database values to appropriate types.
class DataMappingUtils {
  /// Creates a FilesetField from a database value.
  /// 
  /// [value] should be the fileset identifier (string) from the database.
  /// [database] is the DeclarativeDatabase instance.
  static FilesetField? filesetFieldFromValue(
    dynamic value,
    DeclarativeDatabase database,
  ) {
    if (value == null) return null;
    return FilesetField.fromDatabaseValue(value, database);
  }

  /// Converts a FilesetField back to a database value.
  /// 
  /// Returns the fileset identifier string or null.
  static String? filesetFieldToValue(FilesetField? field) {
    return field?.toDatabaseValue();
  }
}
