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
  blob('BLOB');

  const SqliteDataType(this.sqlName);
  
  /// The SQL type name as it appears in CREATE TABLE statements
  final String sqlName;
  
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
  notNull('NOT NULL');

  const ConstraintType(this.sqlName);
  
  /// The SQL constraint name as it appears in CREATE TABLE statements
  final String sqlName;
  
  @override
  String toString() => sqlName;
}