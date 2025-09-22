/// A declarative SQLite library for Dart.
///
/// This library provides a fluent, declarative, and type-safe way to define
/// and interact with a SQLite database.
library declarative_sqlite;

export 'src/annotations/db_record.dart';
export 'src/annotations/register_factory.dart';
export 'src/builders/column_builder.dart';
export 'src/builders/date_column_builder.dart';
export 'src/builders/fileset_column_builder.dart';
export 'src/builders/guid_column_builder.dart';
export 'src/builders/integer_column_builder.dart';
export 'src/builders/key_builder.dart';
export 'src/builders/query_builder.dart';
export 'src/builders/real_column_builder.dart';
export 'src/builders/schema_builder.dart';
export 'src/builders/table_builder.dart';
export 'src/builders/text_column_builder.dart';
export 'src/builders/view_builder.dart';
export 'src/builders/where_clause.dart';
export 'src/data_mapping.dart';
export 'src/database.dart' show DeclarativeDatabase;
export 'src/files/file_repository.dart';
export 'src/files/fileset_field.dart';
export 'src/files/filesystem_file_repository.dart';
export 'src/record.dart' show DbRecord;
export 'src/record_factory.dart';
export 'src/record_map_factory_registry.dart';
export 'src/exceptions/db_exceptions.dart';
export 'src/scheduling/task_scheduler.dart';
export 'src/scheduling/database_maintenance_tasks.dart';
export 'src/schema/schema.dart';
export 'src/streaming/advanced_streaming_query.dart';
export 'src/streaming/query_dependency_analyzer.dart';
export 'src/streaming/streaming_query.dart';
export 'src/streaming/query_stream_manager.dart';
export 'src/sync/dirty_row.dart';
export 'src/sync/dirty_row_store.dart';
export 'src/sync/server_sync_manager.dart';
export 'src/sync/sqlite_dirty_row_store.dart';
