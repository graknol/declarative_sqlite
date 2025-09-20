import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

/// An inherited widget that provides access to a [DeclarativeDatabase] instance
/// throughout the widget tree.
class _DatabaseInheritedWidget extends InheritedWidget {
  final DeclarativeDatabase database;

  const _DatabaseInheritedWidget({
    required this.database,
    required super.child,
  });

  @override
  bool updateShouldNotify(_DatabaseInheritedWidget oldWidget) {
    return database != oldWidget.database;
  }

  static DeclarativeDatabase? maybeOf(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<_DatabaseInheritedWidget>();
    return widget?.database;
  }

  static DeclarativeDatabase of(BuildContext context) {
    final database = maybeOf(context);
    if (database == null) {
      throw FlutterError(
        'DatabaseProvider.of() called with a context that does not contain a DatabaseProvider.\n'
        'No DatabaseProvider ancestor could be found starting from the context that was passed '
        'to DatabaseProvider.of(). This usually happens when the context provided is from a widget '
        'that is not a descendant of a DatabaseProvider widget.\n'
        'The context used was:\n'
        '  $context',
      );
    }
    return database;
  }
}

/// A widget that initializes and provides a [DeclarativeDatabase] to its descendants.
/// 
/// This widget manages the lifecycle of the database connection and provides it
/// through an [InheritedWidget] for efficient access throughout the widget tree.
/// 
/// Example:
/// ```dart
/// DatabaseProvider(
///   schema: (builder) {
///     builder.table('users', (table) {
///       table.guid('id').notNull();
///       table.text('name').notNull();
///     });
///   },
///   databaseName: 'my_app.db',
///   child: MyApp(),
/// )
/// ```
class DatabaseProvider extends StatefulWidget {
  final void Function(SchemaBuilder builder) schema;
  final String databaseName;
  final Widget child;
  final String? databasePath;

  const DatabaseProvider({
    super.key,
    required this.schema,
    required this.databaseName,
    required this.child,
    this.databasePath,
  });

  /// Access the database from anywhere in the widget tree.
  static DeclarativeDatabase of(BuildContext context) {
    return _DatabaseInheritedWidget.of(context);
  }

  /// Access the database from anywhere in the widget tree, returning null if not found.
  static DeclarativeDatabase? maybeOf(BuildContext context) {
    return _DatabaseInheritedWidget.maybeOf(context);
  }

  @override
  State<DatabaseProvider> createState() => _DatabaseProviderState();
}

class _DatabaseProviderState extends State<DatabaseProvider> {
  DeclarativeDatabase? _database;
  bool _isInitializing = true;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  @override
  void didUpdateWidget(DatabaseProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If schema or database name changed, reinitialize
    if (widget.databaseName != oldWidget.databaseName ||
        widget.databasePath != oldWidget.databasePath) {
      _disposeDatabase();
      _initializeDatabase();
    }
  }

  @override
  void dispose() {
    _disposeDatabase();
    super.dispose();
  }

  void _disposeDatabase() {
    _database?.close();
    _database = null;
  }

  Future<void> _initializeDatabase() async {
    _setInitializationState(isInitializing: true, error: null);

    try {
      final schema = _buildDatabaseSchema();
      final database = await _createDatabaseInstance(schema);
      _setInitializationState(isInitializing: false, database: database);
    } catch (error) {
      _setInitializationState(isInitializing: false, error: error);
    }
  }

  Schema _buildDatabaseSchema() {
    final schemaBuilder = SchemaBuilder();
    widget.schema(schemaBuilder);
    return schemaBuilder.build();
  }

  Future<DeclarativeDatabase> _createDatabaseInstance(Schema schema) async {
    return await DeclarativeDatabase.sqlite(
      path: widget.databasePath ?? widget.databaseName,
      schema: schema,
    );
  }

  void _setInitializationState({
    required bool isInitializing,
    Object? error,
    DeclarativeDatabase? database,
  }) {
    if (mounted) {
      setState(() {
        _isInitializing = isInitializing;
        _initializationError = error;
        if (database != null) {
          _database = database;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show error if database initialization failed
    if (_initializationError != null) {
      return ErrorWidget(_initializationError!);
    }

    // Show loading while initializing
    if (_isInitializing || _database == null) {
      return const SizedBox.shrink();
    }

    // Provide database to descendants
    return _DatabaseInheritedWidget(
      database: _database!,
      child: widget.child,
    );
  }
}
