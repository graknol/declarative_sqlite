import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  // Initialize sqflite for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  group('LWW BulkLoad Integration Tests', () {
    late Database database;
    late SchemaBuilder schema;
    late LWWDataAccess dataAccess;

    setUpAll(() async {
      database = await databaseFactory.openDatabase(':memory:');
      
      schema = SchemaBuilder()
        .table('tasks', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .integer('hours', (col) => col.lww()) // LWW column
          .real('rate', (col) => col.lww()) // LWW column
          .text('notes', (col) => col.lww()) // LWW column
          .text('status', (col) => col.notNull().withDefaultValue('pending')))
        .table('users', (table) => table
          .text('username', (col) => col.notNull())
          .text('email', (col) => col.notNull())
          .compositeKey(['username', 'email'])
          .integer('score', (col) => col.lww()) // LWW column
          .text('bio', (col) => col.lww())); // LWW column

      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);
      
      dataAccess = await LWWDataAccess.create(database: database, schema: schema);
    });

    tearDownAll(() async {
      await database.close();
    });

    setUp(() {
      dataAccess.clearAllPendingOperations();
    });

    test('rejects LWW column updates without HLC timestamps', () async {
      final dataset = [
        {
          'title': 'Task 1',
          'hours': 10, // LWW column without timestamp
          'status': 'active',
        }
      ];

      expect(
        () => dataAccess.bulkLoad('tasks', dataset),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('no timestamps provided'),
        )),
      );
    });

    test('allows non-LWW columns without timestamps', () async {
      final dataset = [
        {
          'title': 'Task 1',
          'status': 'active', // Non-LWW columns are fine
        }
      ];

      final result = await dataAccess.bulkLoad('tasks', dataset);
      expect(result.rowsInserted, equals(1));
      expect(result.errors, isEmpty);
    });

    test('validates timestamp requirements for specific LWW columns', () async {
      final dataset = [
        {
          'title': 'Task 1',
          'hours': 10, // LWW column present
          'rate': 25.0, // LWW column present
          'status': 'active',
        }
      ];

      // Missing timestamp for 'rate' column
      final options = BulkLoadOptions(
        lwwTimestamps: [{'hours': '1000'}], // Missing 'rate' timestamp for row
        isFromServer: true,
      );

      expect(
        () => dataAccess.bulkLoad('tasks', dataset, options: options),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('no HLC timestamp provided for it'),
        )),
      );
    });

    test('successfully loads data with LWW timestamps', () async {
      final currentTime = DateTime.now().microsecondsSinceEpoch;
      final dataset = [
        {
          'title': 'Server Task 1',
          'hours': 8,
          'rate': 30.0,
          'notes': 'Server notes',
          'status': 'active',
        },
        {
          'title': 'Server Task 2',
          'hours': 12,
          'rate': 45.0,
          'notes': 'Another server note',
          'status': 'completed',
        }
      ];

      final options = BulkLoadOptions(
        lwwTimestamps: [
          // Row 1 timestamps
          {
            'hours': currentTime.toString(),
            'rate': (currentTime + 1000).toString(),
            'notes': (currentTime + 2000).toString(),
          },
          // Row 2 timestamps 
          {
            'hours': currentTime.toString(),
            'rate': (currentTime + 1000).toString(),
            'notes': (currentTime + 2000).toString(),
          },
        ],
        isFromServer: true,
      );

      final result = await dataAccess.bulkLoad('tasks', dataset, options: options);

      expect(result.rowsInserted, equals(2));
      expect(result.rowsUpdated, equals(0));
      expect(result.errors, isEmpty);

      // Verify data was inserted correctly
      final task1 = await dataAccess.getByPrimaryKey('tasks', 1);
      expect(task1!['title'], equals('Server Task 1'));
      expect(task1['hours'], equals(8));
      expect(task1['rate'], equals(30.0));
      expect(task1['notes'], equals('Server notes'));
    });

    test('performs LWW conflict resolution during upsert mode', () async {
      // Insert initial data locally
      await dataAccess.insert('tasks', {
        'title': 'Local Task',
        'hours': 5,
        'rate': 20.0,
        'notes': 'Local notes',
        'status': 'active',
      });

      // Update LWW columns locally (will have newer timestamps)
      await dataAccess.updateLWWColumn('tasks', 1, 'hours', 8);
      await dataAccess.updateLWWColumn('tasks', 1, 'notes', 'Updated locally');

      // Give some buffer to ensure local timestamps are in past
      await Future.delayed(Duration(milliseconds: 50));

      // Simulate server data with mixed older/newer timestamps
      final currentTime = DateTime.now().microsecondsSinceEpoch;
      final serverDataset = [
        {
          'id': 1, // Existing task
          'title': 'Local Task', // Non-LWW, will be updated
          'hours': 10, // Server value with newer timestamp (should win)
          'rate': 15.0, // Server value with older timestamp (should lose)
          'notes': 'Server notes', // Server value with newer timestamp (should win)
          'status': 'completed', // Non-LWW, will be updated
        }
      ];

      final options = BulkLoadOptions(
        upsertMode: true,
        lwwTimestamps: [
          {
            'hours': (currentTime + 10000).toString(), // Newer (server wins)
            'rate': (currentTime - 100000).toString(), // Older (local wins)
            'notes': (currentTime + 5000).toString(), // Newer (server wins)
          }
        ],
        isFromServer: true,
      );

      final result = await dataAccess.bulkLoad('tasks', serverDataset, options: options);

      expect(result.rowsInserted, equals(0));
      expect(result.rowsUpdated, equals(1));
      expect(result.errors, isEmpty);

      // Verify conflict resolution results
      final task = await dataAccess.getByPrimaryKey('tasks', 1);
      expect(task!['title'], equals('Local Task')); // Non-LWW updated
      expect(task['hours'], equals(10)); // Server won (newer timestamp)
      expect(task['rate'], equals(20.0)); // Local won (newer timestamp)
      expect(task['notes'], equals('Server notes')); // Server won (newer timestamp)
      expect(task['status'], equals('completed')); // Non-LWW updated
    });

    test('handles composite primary keys with LWW columns', () async {
      final currentTime = DateTime.now().microsecondsSinceEpoch;
      final dataset = [
        {
          'username': 'alice',
          'email': 'alice@example.com',
          'score': 100,
          'bio': 'Software engineer',
        },
        {
          'username': 'bob',
          'email': 'bob@example.com', 
          'score': 85,
          'bio': 'Data scientist',
        }
      ];

      final options = BulkLoadOptions(
        lwwTimestamps: [
          {
            'score': currentTime.toString(),
            'bio': (currentTime + 1000).toString(),
          },
          {
            'score': currentTime.toString(),
            'bio': (currentTime + 1000).toString(),
          },
        ],
        isFromServer: true,
      );

      final result = await dataAccess.bulkLoad('users', dataset, options: options);

      expect(result.rowsInserted, equals(2));
      expect(result.errors, isEmpty);

      // Verify retrieval works with composite keys
      final alice = await dataAccess.getByPrimaryKey('users', {
        'username': 'alice',
        'email': 'alice@example.com',
      });
      expect(alice!['score'], equals(100));
      expect(alice['bio'], equals('Software engineer'));
    });

    test('handles upsert mode with composite primary keys and LWW', () async {
      // Insert initial data
      final initialTime = DateTime.now().microsecondsSinceEpoch;
      final initialDataset = [
        {
          'username': 'charlie',
          'email': 'charlie@example.com',
          'score': 75,
          'bio': 'Initial bio',
        }
      ];

      await dataAccess.bulkLoad('users', initialDataset, options: BulkLoadOptions(
        lwwTimestamps: [
          {
            'score': initialTime.toString(),
            'bio': initialTime.toString(),
          }
        ],
      ));

      // Update via upsert with newer timestamps
      await Future.delayed(Duration(milliseconds: 50));
      final updateTime = DateTime.now().microsecondsSinceEpoch;
      final updateDataset = [
        {
          'username': 'charlie',
          'email': 'charlie@example.com',
          'score': 90, // Should win (newer)
          'bio': 'Updated bio', // Should win (newer)
        }
      ];

      final result = await dataAccess.bulkLoad('users', updateDataset, options: BulkLoadOptions(
        upsertMode: true,
        lwwTimestamps: [
          {
            'score': updateTime.toString(),
            'bio': updateTime.toString(),
          }
        ],
        isFromServer: true,
      ));

      expect(result.rowsInserted, equals(0));
      expect(result.rowsUpdated, equals(1));

      // Verify update
      final charlie = await dataAccess.getByPrimaryKey('users', {
        'username': 'charlie',
        'email': 'charlie@example.com',
      });
      expect(charlie!['score'], equals(90));
      expect(charlie['bio'], equals('Updated bio'));
    });

    test('processes large datasets efficiently with batching', () async {
      // Create a large dataset
      final currentTime = DateTime.now().microsecondsSinceEpoch;
      final largeDataset = <Map<String, dynamic>>[];
      
      for (int i = 0; i < 150; i++) {
        largeDataset.add({
          'title': 'Bulk Task $i',
          'hours': 5 + (i % 10),
          'rate': 20.0 + (i % 5),
          'notes': 'Bulk notes $i',
          'status': i % 2 == 0 ? 'active' : 'completed',
        });
      }

      final options = BulkLoadOptions(
        batchSize: 50, // Process in smaller batches
        lwwTimestamps: List.generate(150, (index) => {
          'hours': currentTime.toString(),
          'rate': (currentTime + 1000).toString(),
          'notes': (currentTime + 2000).toString(),
        }),
        isFromServer: true,
      );

      final result = await dataAccess.bulkLoad('tasks', largeDataset, options: options);

      expect(result.rowsInserted, equals(150));
      expect(result.rowsUpdated, equals(0));
      expect(result.rowsSkipped, equals(0));
      expect(result.errors, isEmpty);

      // Verify a few random entries
      final task1 = await dataAccess.getByPrimaryKey('tasks', 1);
      expect(task1!['title'], equals('Bulk Task 0'));
      
      final task50 = await dataAccess.getByPrimaryKey('tasks', 50);
      expect(task50!['title'], equals('Bulk Task 49'));
    });

    test('handles mixed LWW and non-LWW updates correctly', () async {
      // Insert initial data
      await dataAccess.insert('tasks', {
        'title': 'Mixed Test',
        'hours': 10,
        'rate': 25.0,
        'notes': 'Initial',
        'status': 'active',
      });

      // Update some LWW columns locally
      await dataAccess.updateLWWColumn('tasks', 1, 'hours', 15);

      await Future.delayed(Duration(milliseconds: 50));

      // Server update: mix of LWW and non-LWW columns
      final currentTime = DateTime.now().microsecondsSinceEpoch;
      final serverDataset = [
        {
          'id': 1,
          'title': 'Updated Title', // Non-LWW
          'hours': 12, // LWW with older timestamp (should lose)
          'rate': 30.0, // LWW with newer timestamp (should win)
          'status': 'completed', // Non-LWW
          // notes not included (should remain unchanged)
        }
      ];

      final result = await dataAccess.bulkLoad('tasks', serverDataset, options: BulkLoadOptions(
        upsertMode: true,
        lwwTimestamps: [
          {
            'hours': (currentTime - 100000).toString(), // Older
            'rate': (currentTime + 10000).toString(), // Newer
          }
        ],
        isFromServer: true,
      ));

      expect(result.rowsUpdated, equals(1));

      // Verify results
      final task = await dataAccess.getByPrimaryKey('tasks', 1);
      expect(task!['title'], equals('Updated Title')); // Non-LWW updated
      expect(task['hours'], equals(15)); // Local LWW value won
      expect(task['rate'], equals(30.0)); // Server LWW value won
      expect(task['notes'], equals('Initial')); // Unchanged
      expect(task['status'], equals('completed')); // Non-LWW updated
    });

    test('validates error handling with malformed data', () async {
      final dataset = [
        {
          'title': 'Valid Task',
          'hours': 8,
          'status': 'active',
        },
        {
          // Missing required 'title' column
          'hours': 10,
          'status': 'pending',
        }
      ];

      final options = BulkLoadOptions(
        allowPartialData: true,
        collectErrors: true,
        lwwTimestamps: [
          {'hours': '1000'}, // Row 1 timestamps
          {'hours': '1000'}, // Row 2 timestamps
        ],
      );

      final result = await dataAccess.bulkLoad('tasks', dataset, options: options);

      expect(result.rowsInserted, equals(1)); // Only valid row inserted
      expect(result.rowsSkipped, equals(1)); // Invalid row skipped
      expect(result.errors.length, equals(1));
      expect(result.errors.first, contains('Missing required columns'));
    });
  });
}