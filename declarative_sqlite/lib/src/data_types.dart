/// SQLite data type affinities supported by the declarative schema builder.
/// 
/// SQLite has type affinity rather than strict typing, meaning that columns
/// have a preferred type but can store values of other types.
enum SqliteDataType {
  /// INTEGER affinity for whole numbers
  integer('INTEGER'),
  
  /// REAL affinity for floating point numbers
  real('REAL'),
  
  /// TEXT affinity for strings
  text('TEXT'),
  
  /// BLOB affinity for binary data
  blob('BLOB'),
  
  /// Date type stored as TEXT in ISO8601 format (like Oracle's DATE)
  /// Automatically handles encoding/decoding between DateTime and ISO8601 string
  date('TEXT'),
  
  /// Fileset type for managing collections of files (pictures, PDFs, etc.)
  /// Stored as TEXT containing fileset ID that references the _filesets table
  /// Files are stored on filesystem with GUID filenames for security
  fileset('TEXT');

  const SqliteDataType(this.sqlName);
  
  /// The SQL type name as it appears in CREATE TABLE statements
  final String sqlName;
  
  /// Whether this type requires special encoding/decoding
  bool get requiresEncoding => this == date || this == fileset;
  
  @override
  String toString() => sqlName;
}

/// Constraint types supported by the schema builder
enum ConstraintType {
  /// Primary key constraint
  primaryKey('PRIMARY KEY'),
  
  /// Unique constraint
  unique('UNIQUE'),
  
  /// Not null constraint
  notNull('NOT NULL'),
  
  /// Last-Writer-Wins conflict resolution marker (not a SQL constraint)
  /// Columns marked with this will use HLC timestamp-based conflict resolution
  lww('');

  const ConstraintType(this.sqlName);
  
  /// The SQL constraint name as it appears in CREATE TABLE statements
  final String sqlName;
  
  /// Whether this constraint appears in SQL CREATE TABLE statements
  bool get isSqlConstraint => sqlName.isNotEmpty;
  
  @override
  String toString() => sqlName;
}

/// System metacolumn names that are automatically added to all tables
class SystemColumns {
  static const String systemId = 'systemId';
  static const String systemVersion = 'systemVersion';
  
  /// List of all system column names
  static const List<String> all = [systemId, systemVersion];
  
  /// Checks if a column name is a reserved system column
  static bool isSystemColumn(String columnName) {
    return all.contains(columnName);
  }
}