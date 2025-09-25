// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'simple_test.dart';

// **************************************************************************
// DeclarativeSqliteGenerator
// **************************************************************************

/// Generated typed properties for SimpleUser
extension SimpleUserGenerated on SimpleUser {
  // Generated getters and setters
  /// Gets the system_id column value.
  String get systemId => getTextNotNull('system_id');

  /// Sets the system_id column value.
  set systemId(String value) => setText('system_id', value);

  /// Gets the system_created_at column value.
  Object get systemCreatedAt => getValue('system_created_at');

  /// Sets the system_created_at column value.
  set systemCreatedAt(Object value) => setValue('system_created_at', value);

  /// Gets the system_version column value.
  Object get systemVersion => getValue('system_version');

  /// Sets the system_version column value.
  set systemVersion(Object value) => setValue('system_version', value);

  /// Gets the id column value.
  String get id => getTextNotNull('id');

  /// Gets the name column value.
  String get name => getTextNotNull('name');

  /// Sets the name column value.
  set name(String value) => setText('name', value);

  /// Gets the age column value.
  int get age => getIntegerNotNull('age');

  /// Sets the age column value.
  set age(int value) => setInteger('age', value);
}
