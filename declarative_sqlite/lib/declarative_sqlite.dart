/// A declarative SQLite library for Dart.
///
/// This library provides a fluent, declarative, and type-safe way to define
/// and interact with a SQLite database.
library declarative_sqlite;

// Core annotations
export 'src/annotations/db_record.dart';

// Query builders
export 'src/builders/analysis_context.dart';
export 'src/builders/column.dart';
export 'src/builders/schema_builder.dart';
export 'src/builders/query_builder.dart';
export 'src/builders/query_dependencies.dart';
export 'src/builders/where_clause.dart';

// Core database classes
export 'src/database.dart';
export 'src/data_mapping.dart';
export 'src/record.dart';
export 'src/record_factory.dart';
export 'src/record_map_factory_registry.dart';
export 'src/files/filesystem_file_repository.dart';

// Schema classes
export 'src/schema/table.dart';
export 'src/schema/schema.dart';

// Streaming queries
export 'src/streaming/query_dependency_analyzer.dart';
export 'src/streaming/streaming_query.dart';
export 'src/streaming/advanced_streaming_query.dart';

// Synchronization
export 'src/sync/server_sync_manager.dart';
export 'src/scheduling/task_scheduler.dart';