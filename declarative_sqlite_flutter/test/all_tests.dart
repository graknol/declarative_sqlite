import 'package:flutter_test/flutter_test.dart';

// Import all test files
import 'database_provider_test.dart' as database_provider_tests;
import 'query_list_view_test.dart' as query_list_view_tests;
import 'server_sync_manager_test.dart' as server_sync_manager_tests;
import 'integration_test.dart' as integration_tests;
import 'package_test.dart' as package_tests;

void main() {
  group('Declarative SQLite Flutter Test Suite', () {
    group('DatabaseProvider Tests', database_provider_tests.main);
    group('QueryListView Tests', query_list_view_tests.main);
    group('ServerSyncManagerWidget Tests', server_sync_manager_tests.main);
    group('Integration Tests', integration_tests.main);
    group('Package Tests', package_tests.main);
  });
}