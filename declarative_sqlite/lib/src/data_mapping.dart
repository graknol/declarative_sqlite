/// Base class for mapping database rows to typed objects.
///
/// Generated code will create subclasses of this for each table/view.
abstract class DataMapper<T> {
  String get tableName;

  /// Creates an instance of [T] from a database row map.
  T fromMap(Map<String, dynamic> map);
}
