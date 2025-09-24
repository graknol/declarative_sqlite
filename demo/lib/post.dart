
import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'post.db.dart';

@GenerateDbRecord('posts')
class Post extends DbRecord {
  Post(Map<String, Object?> data, DeclarativeDatabase database) 
      : super(data, 'posts', database);
  
  // Factory constructor to create Post from Map - used by the framework
  static Post fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return Post(data, database);
  }
}
