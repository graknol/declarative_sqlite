
import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'user.g.dart';

@GenerateDbRecord('users')
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database) 
      : super(data, 'users', database);

  static User fromMap(Map<String, Object?> map, DeclarativeDatabase database) {
    return User(map, database);
  }
}