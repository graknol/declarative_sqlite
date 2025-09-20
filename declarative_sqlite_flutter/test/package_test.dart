import 'package:flutter_test/flutter_test.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  group('Package Exports', () {
    test('exports all required widgets', () {
      // Test that all main widgets are accessible
      expect(DatabaseProvider, isA<Type>());
      expect(QueryListView, isA<Type>());
      expect(ServerSyncManagerWidget, isA<Type>());
    });

    test('exports core library types', () {
      // Test that core library types are accessible through the flutter package
      expect(DeclarativeDatabase, isA<Type>());
      expect(SchemaBuilder, isA<Type>());
      expect(QueryBuilder, isA<Type>());
      expect(OnFetch, isA<Type>());
      expect(OnSend, isA<Type>());
      expect(DirtyRow, isA<Type>());
    });

    test('DatabaseProvider static methods are accessible', () {
      // Test that static methods exist and have correct signatures
      expect(DatabaseProvider.of, isA<Function>());
      expect(DatabaseProvider.maybeOf, isA<Function>());
    });

    test('QueryListView constructor parameters', () {
      // Test that QueryListView has all expected constructor parameters
      // This is validated by the type system, but we can verify the constructor exists
      expect(() {
        QueryListView<Map<String, Object?>>(
          query: (q) => q.from('test'),
          mapper: (map) => map,
          loadingBuilder: (context) => throw UnimplementedError(),
          errorBuilder: (context, error) => throw UnimplementedError(),
          itemBuilder: (context, item) => throw UnimplementedError(),
        );
      }, returnsNormally);
    });

    test('ServerSyncManagerWidget constructor parameters', () {
      // Test that ServerSyncManagerWidget has all expected constructor parameters
      expect(() {
        ServerSyncManagerWidget(
          retryStrategy: null,
          fetchInterval: const Duration(minutes: 5),
          onFetch: (db, table, lastSynced) async {},
          onSend: (operations) async => true,
          child: throw UnimplementedError(),
        );
      }, returnsNormally);
    });
  });

  group('Type Safety', () {
    test('QueryListView generic type parameter', () {
      // Test that QueryListView properly handles generic types
      expect(
        QueryListView<String>,
        isA<Type>(),
      );
      expect(
        QueryListView<Map<String, Object?>>,
        isA<Type>(),
      );
      expect(
        QueryListView<TestModel>,
        isA<Type>(),
      );
    });

    test('mapper function type safety', () {
      // Test that mapper functions have correct signatures
      String stringMapper(Map<String, Object?> map) => map['value'] as String;
      TestModel testModelMapper(Map<String, Object?> map) => TestModel.fromMap(map);

      expect(stringMapper, isA<String Function(Map<String, Object?>)>());
      expect(testModelMapper, isA<TestModel Function(Map<String, Object?>)>());
    });

    test('callback function type safety', () {
      // Test that callback functions have correct signatures
      Future<void> onFetchCallback(DeclarativeDatabase db, String table, DateTime? lastSynced) async {}
      Future<bool> onSendCallback(List<DirtyRow> operations) async => true;

      expect(onFetchCallback, isA<Future<void> Function(DeclarativeDatabase, String, DateTime?)>());
      expect(onSendCallback, isA<Future<bool> Function(List<DirtyRow>)>());
    });
  });

  group('Constants and Defaults', () {
    test('QueryListView default values', () {
      final widget = QueryListView<String>(
        query: (q) => q.from('test'),
        mapper: (map) => '',
        loadingBuilder: (context) => throw UnimplementedError(),
        errorBuilder: (context, error) => throw UnimplementedError(),
        itemBuilder: (context, item) => throw UnimplementedError(),
      );

      // Test default values from Flutter SDK
      expect(widget.scrollDirection, equals(Axis.vertical));
      expect(widget.reverse, equals(false));
      expect(widget.shrinkWrap, equals(false));
      expect(widget.addAutomaticKeepAlives, equals(true));
      expect(widget.addRepaintBoundaries, equals(true));
      expect(widget.addSemanticIndexes, equals(true));
    });
  });
}

/// Test model for type safety testing
class TestModel {
  final String id;
  final String name;

  TestModel({required this.id, required this.name});

  static TestModel fromMap(Map<String, Object?> map) {
    return TestModel(
      id: map['id'] as String,
      name: map['name'] as String,
    );
  }
}