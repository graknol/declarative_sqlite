import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('DbRecord Annotation Tests', () {
    test('GenerateDbRecord annotation can be created', () {
      const annotation = GenerateDbRecord('users');
      expect(annotation.tableName, equals('users'));
    });

    test('GenerateDbRecord annotation can be used on classes', () {
      // This test verifies that the annotation can be applied to classes
      // We can't easily test the annotation processing without running the generator,
      // but we can at least verify the annotation exists and has the right properties
      
      const annotation = GenerateDbRecord('products');
      expect(annotation.tableName, equals('products'));
      expect(annotation, isA<GenerateDbRecord>());
    });
  });
}

// Example class that would use the annotation
// (For testing purposes only - the generator would process this)
@GenerateDbRecord('users')
class TestUser extends DbRecord {
  TestUser(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);

  static TestUser fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return TestUser(data, database);
  }
}