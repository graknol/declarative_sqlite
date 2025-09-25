/// A declarative SQLite library for Dart.
///
/// This library provides a fluent, declarative, and type-safe way to define
/// and interact with a SQLite database.
library;

// Core annotations
export 'src/annotations/db_schema.dart';
export 'src/annotations/generate_db_record.dart';

// Query builders
export 'src/builders/analysis_context.dart';
export 'src/builders/column_builder.dart';
export 'src/builders/query_column.dart';
export 'src/builders/schema_builder.dart';
export 'src/builders/query_builder.dart';
export 'src/builders/query_dependencies.dart';
export 'src/builders/where_clause.dart';

// Utilities
export 'src/utils/value_serializer.dart';

// Core database classes
export 'src/declarative_database.dart';
export 'src/data_mapping.dart';
export 'src/db_record.dart';
export 'src/record_factory.dart';
export 'src/record_map_factory_registry.dart';
export 'src/files/filesystem_file_repository.dart';

// Schema classes
export 'src/schema/db_table.dart';
export 'src/schema/schema.dart';

// Streaming queries
export 'src/streaming/query_dependency_analyzer.dart';
export 'src/streaming/streaming_query.dart';
export 'src/streaming/query_stream_manager.dart';

// Synchronization
export 'src/sync/dirty_row.dart';
export 'src/sync/dirty_row_store.dart';
export 'src/scheduling/task_scheduler.dart';
export 'src/sync/hlc.dart';
