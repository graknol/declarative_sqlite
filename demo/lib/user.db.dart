// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'user.dart';

// **************************************************************************
// DeclarativeSqliteGenerator
// **************************************************************************

/// Generated typed properties for User
extension UserGenerated on User {
  // Generated getters and setters
  /// Gets the id column value.
  String get id => getTextNotNull('id');

  /// Gets the name column value.
  String get name => getTextNotNull('name');

  /// Sets the name column value.
  set name(String value) => setText('name', value);

  /// Gets the email column value.
  String get email => getTextNotNull('email');

  /// Sets the email column value.
  set email(String value) => setText('email', value);

  /// Gets the age column value.
  int get age => getIntegerNotNull('age');

  /// Sets the age column value.
  set age(int value) => setInteger('age', value);

  /// Gets the gender column value.
  String get gender => getTextNotNull('gender');

  /// Sets the gender column value.
  set gender(String value) => setText('gender', value);

  /// Gets the kids column value.
  int get kids => getIntegerNotNull('kids');

  /// Sets the kids column value.
  set kids(int value) => setInteger('kids', value);

  /// Gets the created_at column value.
  DateTime get createdAt => getDateTimeNotNull('created_at');

  /// Sets the created_at column value.
  set createdAt(DateTime value) => setDateTime('created_at', value);
}
