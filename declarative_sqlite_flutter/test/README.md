# Declarative SQLite Flutter - Test Suite

This directory contains a comprehensive test suite for the `declarative_sqlite_flutter` package.

## Test Structure

### Core Widget Tests

#### `database_provider_test.dart`
Tests for the `DatabaseProvider` widget including:
- ✅ Database initialization and lifecycle management
- ✅ InheritedWidget functionality (`of()` and `maybeOf()`)
- ✅ Error handling during database initialization
- ✅ Proper disposal and cleanup
- ✅ Configuration changes and rebuilding
- ✅ Custom database path support

#### `query_list_view_test.dart`
Tests for the `QueryListView` widget including:
- ✅ Loading, error, and data states
- ✅ Reactive updates when data changes
- ✅ Query parameter changes
- ✅ Database switching
- ✅ ListView property pass-through
- ✅ Integration with DatabaseProvider
- ✅ Error handling and graceful degradation

#### `server_sync_manager_test.dart`
Tests for the `ServerSyncManagerWidget` including:
- ✅ Sync manager initialization and lifecycle
- ✅ Database provider integration
- ✅ Configuration change handling
- ✅ Callback function changes
- ✅ Error handling and graceful degradation
- ✅ Proper disposal and cleanup

### Integration Tests

#### `integration_test.dart`
End-to-end tests covering:
- ✅ DatabaseProvider + QueryListView integration
- ✅ Full stack integration (DatabaseProvider + ServerSyncManagerWidget + QueryListView)
- ✅ Error handling across all widgets
- ✅ Dynamic configuration changes
- ✅ Performance with large datasets
- ✅ Complex widget tree scenarios

### Package Tests

#### `package_test.dart`
Tests for package structure and exports:
- ✅ All required widgets are exported
- ✅ Core library types are accessible
- ✅ Type safety and generic parameters
- ✅ Constructor parameter validation
- ✅ Default values and constants

### Test Utilities

#### `test_helper.dart`
Shared utilities for testing:
- ✅ SQLite FFI initialization
- ✅ Test database creation and cleanup
- ✅ Test data models (TestUser, TestPost)
- ✅ Helper functions for async operations

## Running Tests

### Run All Tests
```bash
cd declarative_sqlite_flutter
flutter test
```

### Run Specific Test Files
```bash
flutter test test/database_provider_test.dart
flutter test test/query_list_view_test.dart
flutter test test/server_sync_manager_test.dart
flutter test test/integration_test.dart
flutter test test/package_test.dart
```

### Run All Tests with Coverage
```bash
flutter test --coverage
```

### Run Tests in Watch Mode
```bash
flutter test --watch
```

## Test Coverage

The test suite provides comprehensive coverage of:

### Widget Functionality
- ✅ **DatabaseProvider**: 100% of public API methods and edge cases
- ✅ **QueryListView**: All rendering states, data flow, and ListView integration
- ✅ **ServerSyncManagerWidget**: Lifecycle management and sync configuration

### Integration Scenarios
- ✅ **Provider Pattern**: InheritedWidget integration and dependency injection
- ✅ **Reactive Updates**: Streaming query updates and UI synchronization
- ✅ **Error Handling**: Graceful degradation and error state management
- ✅ **Performance**: Large dataset handling and widget rebuilding

### Edge Cases
- ✅ **Null Safety**: Handling of null databases and optional parameters
- ✅ **Configuration Changes**: Dynamic updates to widget properties
- ✅ **Disposal**: Proper cleanup and resource management
- ✅ **Error Conditions**: Database errors, query failures, and sync issues

## Test Patterns

### Widget Testing
```dart
testWidgets('description', (WidgetTester tester) async {
  await tester.pumpWidget(/* widget tree */);
  await tester.pumpAndSettle();
  
  // Assertions
  expect(find.text('Expected Text'), findsOneWidget);
});
```

### Database Testing
```dart
test('database operation', () async {
  final database = await createTestDatabase(schema: createTestSchema());
  
  // Test database operations
  await database.insert('table', data);
  
  // Cleanup
  await database.close();
});
```

### Integration Testing
```dart
testWidgets('integration scenario', (WidgetTester tester) async {
  await tester.pumpWidget(
    DatabaseProvider(
      schema: (builder) => /* schema */,
      child: QueryListView(/* parameters */),
    ),
  );
  
  // Test interactions
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  
  // Verify results
  expect(find.text('New Item'), findsOneWidget);
});
```

## Dependencies

The test suite uses:
- `flutter_test`: Flutter testing framework
- `test`: Dart testing framework
- `sqflite_common_ffi`: SQLite FFI for testing
- `mockito` (for future mocking needs)

## Best Practices

### Test Organization
- Group related tests using `group()`
- Use descriptive test names
- Follow AAA pattern (Arrange, Act, Assert)

### Database Testing
- Always use in-memory databases for tests
- Clean up databases after each test
- Use helper functions for common operations

### Widget Testing
- Use `pumpAndSettle()` for async operations
- Test all widget states (loading, error, success)
- Verify both UI and behavior

### Async Testing
- Use `waitForAsync()` helper for stream operations
- Handle timing issues with appropriate delays
- Test both sync and async code paths

## Future Enhancements

- [ ] Performance benchmarking tests
- [ ] Accessibility testing
- [ ] Visual regression testing
- [ ] Stress testing with very large datasets
- [ ] Mock network conditions for sync testing
- [ ] Golden file testing for UI consistency