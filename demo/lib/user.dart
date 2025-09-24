
import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'user.db.dart';

@GenerateDbRecord('users')
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database) 
      : super(data, 'users', database);
  
  // Factory constructor to create User from Map - used by the framework
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return User(data, database);
  }
}