import 'dart:io';

import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

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
    final widget =
        context.dependOnInheritedWidgetOfExactType<_DatabaseInheritedWidget>();
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
  final void Function(SchemaBuilder builder)? schema;
  final String? databaseName;
  final DeclarativeDatabase? database;
  final Widget child;
  final String? databasePath;
  final bool recreateDatabase;

  const DatabaseProvider({
    super.key,
    required this.schema,
    required this.databaseName,
    required this.child,
    this.databasePath,
    this.recreateDatabase = false,
  }) : database = null;

  const DatabaseProvider.value({
    super.key,
    required this.database,
    required this.child,
  })  : schema = null,
        databaseName = null,
        databasePath = null,
        recreateDatabase = false;

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
    if (widget.database != null) {
      _database = widget.database;
      _isInitializing = false;
    } else {
      _initDatabase();
    }
  }

  @override
  void didUpdateWidget(DatabaseProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.database != oldWidget.database) {
      setState(() {
        _database = widget.database;
        _isInitializing = false;
        _initializationError = null;
      });
    } else if (widget.recreateDatabase &&
        widget.databaseName != oldWidget.databaseName) {
      _initDatabase();
    }
  }

  Future<void> _initDatabase() async {
    setState(() {
      _isInitializing = true;
      _initializationError = null;
    });

    try {
      final dbPath = widget.databasePath ??
          path.join(
            (await getApplicationDocumentsDirectory()).path,
            widget.databaseName!,
          );

      if (widget.recreateDatabase && await File(dbPath).exists()) {
        await File(dbPath).delete();
      }

      final schemaBuilder = SchemaBuilder();
      widget.schema!(schemaBuilder);
      final schema = schemaBuilder.build();

      final db = await DeclarativeDatabase.open(
        dbPath,
        schema: schema,
        databaseFactory: databaseFactory,
        fileRepository: FilesystemFileRepository(
          path.join(
            (await getApplicationDocumentsDirectory()).path,
            'files',
          ),
        ),
        recreateDatabase: widget.recreateDatabase,
      );
      setState(() {
        _database = db;
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _initializationError = e;
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
