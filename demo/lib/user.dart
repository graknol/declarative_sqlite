
import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'user.db.dart';

@GenerateDbRecord('users')
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database) 
      : super(data, 'users', database);
}