/// Minimal test to verify the dirty row data field works correctly
/// This test focuses only on the changes we made, avoiding other parts of the codebase

import 'package:test/test.dart';
import 'package:declarative_sqlite/src/sync/dirty_row.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';

void main() {
  group('DirtyRow Data Field', () {
    test('can create DirtyRow with data', () {
      final hlc = Hlc(milliseconds: 1000, counter: 0, nodeId: 'test-node');
      
      final dirtyRow = DirtyRow(
        tableName: 'c_work_order',
        rowId: 'test-id-123',
        hlc: hlc,
        isFullRow: true,
        data: {
          'rowstate': 'WorkStarted',
          'priority': 5,
        },
      );
      
      expect(dirtyRow.tableName, equals('c_work_order'));
      expect(dirtyRow.rowId, equals('test-id-123'));
      expect(dirtyRow.isFullRow, isTrue);
      expect(dirtyRow.data, isNotNull);
      expect(dirtyRow.data!['rowstate'], equals('WorkStarted'));
      expect(dirtyRow.data!['priority'], equals(5));
    });
    
    test('can create DirtyRow without data (null)', () {
      final hlc = Hlc(milliseconds: 1000, counter: 0, nodeId: 'test-node');
      
      final dirtyRow = DirtyRow(
        tableName: 'c_work_order',
        rowId: 'test-id-456',
        hlc: hlc,
        isFullRow: true,
        data: null,
      );
      
      expect(dirtyRow.tableName, equals('c_work_order'));
      expect(dirtyRow.rowId, equals('test-id-456'));
      expect(dirtyRow.data, isNull);
    });
    
    test('can create DirtyRow without specifying data (defaults to null)', () {
      final hlc = Hlc(milliseconds: 1000, counter: 0, nodeId: 'test-node');
      
      final dirtyRow = DirtyRow(
        tableName: 'c_work_order',
        rowId: 'test-id-789',
        hlc: hlc,
        isFullRow: true,
      );
      
      expect(dirtyRow.tableName, equals('c_work_order'));
      expect(dirtyRow.rowId, equals('test-id-789'));
      expect(dirtyRow.data, isNull);
    });
    
    test('data field supports various types', () {
      final hlc = Hlc(milliseconds: 1000, counter: 0, nodeId: 'test-node');
      
      final dirtyRow = DirtyRow(
        tableName: 'test_table',
        rowId: 'test-id',
        hlc: hlc,
        isFullRow: true,
        data: {
          'text_field': 'Hello World',
          'int_field': 42,
          'double_field': 3.14,
          'bool_field': true,
          'null_field': null,
        },
      );
      
      expect(dirtyRow.data!['text_field'], isA<String>());
      expect(dirtyRow.data!['int_field'], isA<int>());
      expect(dirtyRow.data!['double_field'], isA<double>());
      expect(dirtyRow.data!['bool_field'], isA<bool>());
      expect(dirtyRow.data!['null_field'], isNull);
    });
    
    test('equality comparison includes data field', () {
      final hlc = Hlc(milliseconds: 1000, counter: 0, nodeId: 'test-node');
      
      final dirtyRow1 = DirtyRow(
        tableName: 'test',
        rowId: 'id1',
        hlc: hlc,
        isFullRow: true,
        data: {'field': 'value'},
      );
      
      final dirtyRow2 = DirtyRow(
        tableName: 'test',
        rowId: 'id1',
        hlc: hlc,
        isFullRow: true,
        data: {'field': 'value'},
      );
      
      final dirtyRow3 = DirtyRow(
        tableName: 'test',
        rowId: 'id1',
        hlc: hlc,
        isFullRow: true,
        data: {'field': 'different'},
      );
      
      expect(dirtyRow1, equals(dirtyRow2));
      expect(dirtyRow1, isNot(equals(dirtyRow3)));
    });
  });
}
