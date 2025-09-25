import '../utils/string_utils.dart';

/// Interface for schema information to resolve column-to-table mappings
abstract class SchemaProvider {
  /// Returns true if the specified table contains the specified column
  bool tableHasColumn(String tableName, String columnName);
  
  /// Gets all tables that contain the specified column
  List<String> getTablesWithColumn(String columnName);
}

/// Represents the analysis context for dependency resolution
///
/// Acts as a stack of available table/view names and aliases that columns
/// can be qualified with. When collisions occur, the closest (most recently added)
/// one wins according to SQL scoping rules.
class AnalysisContext {
  final List<_ContextLevel> _levels = [];
  final SchemaProvider? _schema;

  /// Creates a new analysis context
  AnalysisContext([this._schema]);

  /// Adds a new context level (e.g., for subqueries)
  void pushLevel() {
    _levels.add(_ContextLevel());
  }

  /// Removes the current context level
  void popLevel() {
    if (_levels.isNotEmpty) {
      _levels.removeLast();
    }
  }

  /// Adds a table or view to the current context level
  void addTable(String name, {String? alias}) {
    if (_levels.isEmpty) {
      pushLevel();
    }
    _addTable(alias, name);
    _addTable(name, name);
  }

  void _addTable(String? key, String value) {
    if (isNullOrWhitespace(key) || isNullOrWhitespace(value)) {
      return;
    }
    _levels.last.tables[key!] = value;
  }

  /// Resolves a table/alias name to its full table name
  /// Returns null if not found in any context level
  String? resolveTable(String nameOrAlias) {
    // Search from most recent level to oldest (SQL scoping rules)
    for (int i = _levels.length - 1; i >= 0; i--) {
      final table = _levels[i].tables[nameOrAlias];
      if (table != null) {
        return table;
      }
    }
    return null;
  }

  /// Gets all available table names and aliases in the current context
  Map<String, String> getAllTables() {
    final result = <String, String>{};

    // Start from oldest level to newest so newer ones override older ones
    for (final level in _levels) {
      result.addAll(level.tables);
    }

    return result;
  }

  /// Gets the primary table from the outermost context (FROM clause)
  String? get primaryTable {
    if (_levels.isEmpty) return null;

    final outermost = _levels.first;
    if (outermost.tables.isEmpty) return null;

    // Return the first table added (which should be the FROM table)
    return outermost.tables.values.first;
  }

  /// Resolves an unqualified column to the most appropriate table
  /// This is used when a column doesn't have a table prefix and we need to
  /// determine which table it belongs to based on context.
  /// 
  /// Uses schema information when available to find tables that actually
  /// contain the column, otherwise falls back to context-based heuristics.
  String? resolveUnqualifiedColumn(String columnName) {
    if (_schema != null) {
      // Check tables from current level first (closest scope), then work backwards
      for (int i = _levels.length - 1; i >= 0; i--) {
        final level = _levels[i];
        
        // Within each level, check tables in reverse order of addition
        // (most recently added tables have precedence)
        final tableNames = level.tables.values.toList().reversed;
        
        for (final tableName in tableNames) {
          if (_schema.tableHasColumn(tableName, columnName)) {
            return tableName;
          }
        }
      }
      
      // No table in context contains this column
      return null;
    }
    
    // Fallback to heuristics when no schema is available
    // In the current context level, prefer the primary table (FROM clause)
    if (_levels.isNotEmpty) {
      final currentLevel = _levels.last;
      
      // If there's only one table in the current level, use it
      if (currentLevel.tables.length == 1) {
        return currentLevel.tables.values.first;
      }
      
      // If there are multiple tables, prefer the first one added (FROM table)
      if (currentLevel.tables.isNotEmpty) {
        return currentLevel.tables.values.first;
      }
    }
    
    // Fall back to the primary table from outer context
    return primaryTable;
  }

  /// Creates a copy of this context for use in subqueries
  AnalysisContext copy() {
    final newContext = AnalysisContext(_schema);
    for (final level in _levels) {
      newContext.pushLevel();
      newContext._levels.last.tables.addAll(level.tables);
    }
    return newContext;
  }

  @override
  String toString() {
    final buffer = StringBuffer('AnalysisContext{\n');
    for (int i = 0; i < _levels.length; i++) {
      buffer.writeln('  Level $i: ${_levels[i].tables}');
    }
    buffer.writeln('}');
    return buffer.toString();
  }
}

/// Represents a single context level with available tables/aliases
class _ContextLevel {
  /// Maps alias/table names to their full table names
  final Map<String, String> tables = <String, String>{};
}
