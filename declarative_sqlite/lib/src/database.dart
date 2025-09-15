import 'dart:async';
import 'package:sqflite_common/sqflite.dart' as sqflite;
import 'package:path/path.dart' as p;
import 'package:declarative_sqlite/src/migration/generate_migration_scripts.dart';
import 'package:declarative_sqlite/src/migration/diff_schemas.dart';
import 'package:declarative_sqlite/src/migration/introspect_schema.dart';
import 'package:declarative_sqlite/src/schema/schema.dart';

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

// These are query condition functions from DREAM.md
dynamic and(List<dynamic> conditions) => {};
dynamic or(List<dynamic> conditions) => {};
dynamic isA(String field) => IsClause(field);

class IsClause {
  final String field;
  IsClause(this.field);

  dynamic eq(dynamic value) => {};
  dynamic gt(dynamic value) => {};
  dynamic like(String value) => {};
  dynamic get nil => {};
  dynamic get not => NotClause(this);
}

class NotClause {
  final IsClause clause;
  NotClause(this.clause);

  dynamic get nil => {};
}

class Database {
  final String _databaseName;
  final Schema _schema;
  sqflite.Database? _db;

  Database(this._databaseName, this._schema);

  Future<void> open() async {
    final databasesPath = await sqflite.getDatabasesPath();
    final path = p.join(databasesPath, _databaseName);

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
}
