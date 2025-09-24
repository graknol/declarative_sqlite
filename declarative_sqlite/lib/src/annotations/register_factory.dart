/// DEPRECATED: The @RegisterFactory annotation is no longer needed.
/// 
/// The registration builder now automatically detects all classes that:
/// - Extend DbRecord
/// - Have the @GenerateDbRecord annotation
/// 
/// Simply use @GenerateDbRecord alone:
/// ```dart
/// @GenerateDbRecord('users')
/// class User extends DbRecord {
///   User(Map<String, Object?> data, DeclarativeDatabase database)
///       : super(data, 'users', database);
/// }
/// ```
/// 
/// This will automatically generate:
/// 1. Typed getters and setters for the User class
/// 2. A fromMap factory method  
/// 3. Registration calls in the generated registration function
@Deprecated('Use @GenerateDbRecord alone - @RegisterFactory is no longer needed')
class RegisterFactory {
  /// Creates a RegisterFactory annotation.
  const RegisterFactory();
}