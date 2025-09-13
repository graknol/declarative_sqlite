import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:path/path.dart';

/// A Flutter-specific database service that provides easy integration with declarative_sqlite.
/// 
/// This class handles database initialization, schema migration, and provides
/// Flutter-specific utilities like change notifications.
class FlutterDatabaseService extends ChangeNotifier {
  Database? _database;
  SchemaBuilder? _schema;
  DataAccess? _dataAccess;
  bool _isInitialized = false;
  String? _databasePath;

  /// Whether the database service is initialized
  bool get isInitialized => _isInitialized;

  /// The current database instance
  Database? get database => _database;

  /// The current schema
  SchemaBuilder? get schema => _schema;

  /// The data access instance
  DataAccess? get dataAccess => _dataAccess;

  /// Initialize the database service with a schema
  Future<void> initialize({
    required SchemaBuilder schema,
    String? databaseName,
    String? databasePath,
    int version = 1,
    void Function(Database db, int oldVersion, int newVersion)? onUpgrade,
  }) async {
    if (_isInitialized) {
      debugPrint('FlutterDatabaseService already initialized');
      return;
    }

    try {
      _schema = schema;
      
      // Determine database path
      if (databasePath != null) {
        _databasePath = databasePath;
      } else {
        final dbDir = await getDatabasesPath();
        _databasePath = join(dbDir, databaseName ?? 'app_database.db');
      }

      // Open database
      _database = await openDatabase(
        _databasePath!,
        version: version,
        onCreate: (db, version) async {
          debugPrint('Creating database tables...');
          await _applySchema(db);
        },
        onUpgrade: onUpgrade ?? (db, oldVersion, newVersion) async {
          debugPrint('Upgrading database from $oldVersion to $newVersion');
          await _applySchema(db);
        },
      );

      // Create data access instance
      _dataAccess = await DataAccess.create(
        database: _database!,
        schema: _schema!,
      );

      _isInitialized = true;
      notifyListeners();
      
      debugPrint('FlutterDatabaseService initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize FlutterDatabaseService: $e');
      rethrow;
    }
  }

  /// Apply the schema to the database
  Future<void> _applySchema(Database database) async {
    if (_schema == null) return;
    
    final migrator = SchemaMigrator();
    await migrator.migrate(database, _schema!);
  }

  /// Close the database and clean up resources
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    
    _dataAccess = null;
    _schema = null;
    _isInitialized = false;
    
    notifyListeners();
    debugPrint('FlutterDatabaseService closed');
  }

  /// Reset the database (delete and recreate)
  Future<void> reset({bool reinitialize = true}) async {
    if (_databasePath == null) return;
    
    await close();
    
    try {
      await deleteDatabase(_databasePath!);
      debugPrint('Database deleted: $_databasePath');
      
      if (reinitialize && _schema != null) {
        await initialize(schema: _schema!);
      }
    } catch (e) {
      debugPrint('Failed to reset database: $e');
      rethrow;
    }
  }

  /// Get database size in bytes
  Future<int?> getDatabaseSize() async {
    if (_databasePath == null) return null;
    
    try {
      final file = await File(_databasePath!).stat();
      return file.size;
    } catch (e) {
      debugPrint('Failed to get database size: $e');
      return null;
    }
  }

  /// Get database information
  Future<Map<String, dynamic>> getDatabaseInfo() async {
    if (_database == null) return {};
    
    try {
      final version = await _database!.getVersion();
      final size = await getDatabaseSize();
      
      // Get table information
      final tables = await _database!.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      
      final tableInfo = <String, Map<String, dynamic>>{};
      for (final table in tables) {
        final tableName = table['name'] as String;
        final count = await _database!.rawQuery('SELECT COUNT(*) as count FROM $tableName');
        final rowCount = count.first['count'] as int;
        
        tableInfo[tableName] = {
          'rowCount': rowCount,
        };
      }
      
      return {
        'path': _databasePath,
        'version': version,
        'size': size,
        'tables': tableInfo,
        'isInitialized': _isInitialized,
      };
    } catch (e) {
      debugPrint('Failed to get database info: $e');
      return {};
    }
  }

  /// Execute a database transaction
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    if (_database == null) {
      throw StateError('Database not initialized');
    }
    
    return await _database!.transaction(action);
  }

  /// Backup the database to a file
  Future<void> backup(String backupPath) async {
    if (_database == null || _databasePath == null) {
      throw StateError('Database not initialized');
    }
    
    try {
      final sourceFile = File(_databasePath!);
      await sourceFile.copy(backupPath);
      debugPrint('Database backed up to: $backupPath');
    } catch (e) {
      debugPrint('Failed to backup database: $e');
      rethrow;
    }
  }

  /// Restore the database from a backup file
  Future<void> restore(String backupPath, {bool reinitialize = true}) async {
    if (_databasePath == null) {
      throw StateError('Database path not set');
    }
    
    await close();
    
    try {
      final backupFile = File(backupPath);
      await backupFile.copy(_databasePath!);
      debugPrint('Database restored from: $backupPath');
      
      if (reinitialize && _schema != null) {
        await initialize(schema: _schema!);
      }
    } catch (e) {
      debugPrint('Failed to restore database: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}

/// A widget that provides FlutterDatabaseService to its descendants
class DatabaseProvider extends InheritedNotifier<FlutterDatabaseService> {
  const DatabaseProvider({
    super.key,
    required FlutterDatabaseService service,
    required super.child,
  }) : super(notifier: service);

  static FlutterDatabaseService? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DatabaseProvider>()?.notifier;
  }
}

/// A widget that initializes the database service and provides it to children
class DatabaseServiceProvider extends StatefulWidget {
  /// The schema to use for the database
  final SchemaBuilder schema;
  
  /// Name of the database file
  final String? databaseName;
  
  /// Custom database path
  final String? databasePath;
  
  /// Database version
  final int version;
  
  /// Custom upgrade function
  final void Function(Database db, int oldVersion, int newVersion)? onUpgrade;
  
  /// Widget to show while initializing
  final Widget? loadingWidget;
  
  /// Widget to show on initialization error
  final Widget Function(Object error)? errorBuilder;
  
  /// Child widget tree
  final Widget child;

  const DatabaseServiceProvider({
    super.key,
    required this.schema,
    required this.child,
    this.databaseName,
    this.databasePath,
    this.version = 1,
    this.onUpgrade,
    this.loadingWidget,
    this.errorBuilder,
  });

  @override
  State<DatabaseServiceProvider> createState() => _DatabaseServiceProviderState();
}

class _DatabaseServiceProviderState extends State<DatabaseServiceProvider> {
  late FlutterDatabaseService _service;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _service = FlutterDatabaseService();
    _initializeService();
  }

  Future<void> _initializeService() async {
    try {
      await _service.initialize(
        schema: widget.schema,
        databaseName: widget.databaseName,
        databasePath: widget.databasePath,
        version: widget.version,
        onUpgrade: widget.onUpgrade,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(_error!);
      }
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text('Database initialization failed: $_error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                  });
                  _initializeService();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_service.isInitialized) {
      return widget.loadingWidget ??
          const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing database...'),
                ],
              ),
            ),
          );
    }

    return DatabaseProvider(
      service: _service,
      child: widget.child,
    );
  }
}