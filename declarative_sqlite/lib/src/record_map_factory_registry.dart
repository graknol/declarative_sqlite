import 'package:declarative_sqlite/src/record.dart';

/// Registry for typed record factory functions.
/// 
/// This allows registering fromMap factory functions for specific record types
/// and looking them up by Type, eliminating the need for mapper parameters
/// in query methods.
class RecordMapFactoryRegistry {
  static final Map<Type, Function> _factories = {};

  /// Registers a fromMap factory for the given record type.
  /// 
  /// Example:
  /// ```dart
  /// RecordMapFactoryRegistry.register<User>(User.fromMap);
  /// ```
  static void register<T extends DbRecord>(T Function(Map<String, Object?>) factory) {
    _factories[T] = factory;
  }

  /// Gets the factory for the given record type.
  /// 
  /// Throws [ArgumentError] if no factory is registered for the type.
  static T Function(Map<String, Object?>) getFactory<T extends DbRecord>() {
    final factory = _factories[T];
    if (factory == null) {
      throw ArgumentError('No factory registered for type $T. '
          'Call RecordMapFactoryRegistry.register<$T>(factory) first.');
    }
    return factory as T Function(Map<String, Object?>);
  }

  /// Checks if a factory is registered for the given type.
  static bool hasFactory<T extends DbRecord>() {
    return _factories.containsKey(T);
  }

  /// Checks if a factory is registered for the given type by Type object.
  static bool hasFactoryForType(Type type) {
    return _factories.containsKey(type);
  }

  /// Gets all registered types.
  static Set<Type> get registeredTypes => Set.unmodifiable(_factories.keys);

  /// Clears all registered factories. Useful for testing.
  static void clear() {
    _factories.clear();
  }

  /// Creates an instance using the registered factory for the given type.
  /// 
  /// This is a convenience method that combines getFactory and calling it.
  static T create<T extends DbRecord>(Map<String, Object?> data) {
    final factory = getFactory<T>();
    return factory(data);
  }
}