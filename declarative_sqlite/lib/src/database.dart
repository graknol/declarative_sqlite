import 'dart:async';
import 'package:sqflite_common/sqflite.dart' as sqflite;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:declarative_sqlite/src/migration/generate_migration_scripts.dart';
import 'package:declarative_sqlite/src/migration/diff_schemas.dart';
import 'package:declarative_sqlite/src/migration/introspect_schema.dart';
import 'package:declarative_sqlite/src/schema/schema.dart';
import 'package:declarative_sqlite/src/builders/query_builder.dart';
import 'package:declarative_sqlite/src/data_mapping.dart';

typedef OnFetch = Future<void> Function(
    DataAccess dataAccess, String tableName, String? clock);
typedef OnSend = Future<bool> Function(dynamic operations);

class DataAccess {
  Future<void> bulkLoad(dynamic json) async {
    // Implementation will be added later
  }
}

class RetryStrategies {
  static dynamic exponentialBackoff({required Duration maxDelay}) {
    // Implementation will be added later
  }
}

class ServerSyncException implements Exception {
  final dynamic content;

  ServerSyncException(this.content);
}

class DeclarativeDatabase {
  final String _databaseName;
  final Schema _schema;
  sqflite.Database? _db;

  DeclarativeDatabase(this._databaseName, this._schema);

  Future<void> open() async {
    String path;
    if (_databaseName == sqflite.inMemoryDatabasePath) {
      path = _databaseName;
    } else {
      // if (Platform.isAndroid) {
      //   path = sqflite.
      // } else if (Platform.isIos)
      // {
final documentsDirectory = await path_provider.getLibraryDirectory();
      path = p.join(documentsDirectory.path, _databaseName);
      }
    }

    _db = await sqflite.openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await _migrate(db, 0, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _migrate(db, oldVersion, newVersion);
      },
    );
  }

  Future<void> _migrate(
      sqflite.Database db, int oldVersion, int newVersion) async {
    final liveSchema = await introspectSchema(db);
    final changes = diffSchemas(_schema, liveSchema);
    final scripts = generateMigrationScripts(changes);

    if (scripts.isEmpty) {
      return;
    }

    await db.transaction((txn) async {
      for (final script in scripts) {
        await txn.execute(script);
      }
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<List<Map<String, dynamic>>> query(QueryBuilder builder) async {
    if (_db == null) {
      throw StateError('Database is not open. Call open() before querying.');
    }
    final (sql, params) = builder.build();
    return _db!.rawQuery(sql, params);
  }

  Future<int> insert(String table, Map<String, Object?> values) {
    if (_db == null) {
      throw StateError('Database is not open. Call open() before inserting.');
    }
    return _db!.insert(table, values);
  }

  Future<List<Object?>> batch(void Function(sqflite.Batch batch) operations) {
    if (_db == null) {
      throw StateError('Database is not open. Call open() before batching.');
    }
    final batch = _db!.batch();
    operations(batch);
    return batch.commit();
  }

  Future<List<T>> queryMapped<T>(
      QueryBuilder builder, DataMapper<T> mapper) async {
    final results = await query(builder);
    return results.map((row) => mapper.fromMap(row)).toList();
  }
}
