/// Annotation to mark a class for automatic factory registration.
///
/// Classes annotated with @RegisterFactory will have their fromMap factory
/// methods automatically registered in the RecordMapFactoryRegistry during
/// code generation.
///
/// This annotation should be used together with @GenerateDbRecord to create
/// a complete generated record class with automatic registration.
///
/// Example:
/// ```dart
/// @GenerateDbRecord('users')
/// @RegisterFactory()
/// class User extends DbRecord {
///   User(Map<String, Object?> data, DeclarativeDatabase database)
///       : super(data, 'users', database);
/// }
/// ```
///
/// This will generate:
/// 1. Typed getters and setters for the User class
/// 2. A fromMap factory method
/// 3. Registration calls in a generated registration function
class RegisterFactory {
  /// Creates a RegisterFactory annotation.
  const RegisterFactory();
}