/**
 * Result from a SQL statement execution that modifies data
 */
export interface RunResult {
  /** Number of rows modified */
  changes: number;
  /** Last inserted row ID (if applicable) */
  lastInsertRowid: number | bigint;
}

/**
 * Prepared statement interface for parameterized queries
 */
export interface PreparedStatement {
  /**
   * Execute statement and return results as array of objects
   * @param params - Positional parameters for the query
   */
  all<T = any>(...params: any[]): Promise<T[]>;
  
  /**
   * Execute statement and return first result
   * @param params - Positional parameters for the query
   */
  get<T = any>(...params: any[]): Promise<T | undefined>;
  
  /**
   * Execute statement without returning results
   * @param params - Positional parameters for the query
   */
  run(...params: any[]): Promise<RunResult>;
  
  /**
   * Finalize/close the prepared statement
   */
  finalize(): Promise<void>;
}

/**
 * Main SQLite adapter interface
 * Abstraction layer to support multiple SQLite implementations
 */
export interface SQLiteAdapter {
  /**
   * Open/initialize the database
   * @param path - Database file path (or ':memory:' for in-memory)
   */
  open(path: string): Promise<void>;
  
  /**
   * Close the database connection
   */
  close(): Promise<void>;
  
  /**
   * Execute SQL without returning results (for DDL, etc.)
   * @param sql - SQL statement to execute
   */
  exec(sql: string): Promise<void>;
  
  /**
   * Prepare a SQL statement for execution
   * @param sql - SQL statement with ? placeholders
   */
  prepare(sql: string): PreparedStatement;
  
  /**
   * Execute multiple statements in a transaction
   * Automatically commits on success, rolls back on error
   * @param callback - Function containing transaction logic
   */
  transaction<T>(callback: () => Promise<T>): Promise<T>;
  
  /**
   * Check if database is currently open
   */
  isOpen(): boolean;
}
