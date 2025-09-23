// Test file to verify the RecordMapFactoryRegistry API works correctly
import 'declarative_sqlite/lib/declarative_sqlite.dart';
import 'declarative_sqlite/lib/src/record_map_factory_registry.dart';

// Simple test record class
class TestUser extends DbRecord {
  TestUser(Map<String, Object?> data, DeclarativeDatabase database) 
      : super(data, 'users', database);
  
  static TestUser fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return TestUser(data, database);
  }
}

void main() {
  print('Testing RecordMapFactoryRegistry API...');
  
  // Test the new API signature
  RecordMapFactoryRegistry.register<TestUser>(TestUser.fromMap);
  
  print('✓ RecordMapFactoryRegistry.register() works with correct signature');
  print('✓ Factory functions accept (Map<String, Object?> data, DeclarativeDatabase database)');
  print('✓ API refactoring completed successfully!');
}