// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'post.dart';

// **************************************************************************
// DeclarativeSqliteGenerator
// **************************************************************************

/// Generated typed properties for Post
extension PostGenerated on Post {
  // Generated getters and setters
  /// Gets the id column value.
  String get id => getTextNotNull('id');

  /// Gets the user_id column value.
  String get userId => getTextNotNull('user_id');

  /// Sets the user_id column value.
  set userId(String value) => setText('user_id', value);

  /// Gets the title column value.
  String get title => getTextNotNull('title');

  /// Sets the title column value.
  set title(String value) => setText('title', value);

  /// Gets the content column value.
  String get content => getTextNotNull('content');

  /// Sets the content column value.
  set content(String value) => setText('content', value);

  /// Gets the created_at column value.
  DateTime get createdAt => getDateTimeNotNull('created_at');

  /// Sets the created_at column value.
  set createdAt(DateTime value) => setDateTime('created_at', value);

  /// Gets the user_name column value.
  String get userName => getTextNotNull('user_name');

  /// Sets the user_name column value.
  set userName(String value) => setText('user_name', value);
}
