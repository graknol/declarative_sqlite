
import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'post.db.dart';

@GenerateDbRecord('posts')
class Post extends DbRecord {
  Post(Map<String, Object?> data, DeclarativeDatabase database) 
      : super(data, 'posts', database);

  static Post fromMap(Map<String, Object?> map, DeclarativeDatabase database) {
    return Post(map, database);
  }
}