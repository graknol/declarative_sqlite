/// Represents the analysis context for dependency resolution
/// 
/// Acts as a stack of available table/view names and aliases that columns
/// can be qualified with. When collisions occur, the closest (most recently added)
/// one wins according to SQL scoping rules.
class AnalysisContext {
  final List<_ContextLevel> _levels = [];

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
    _levels.last.tables[alias ?? name] = name;
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

  /// Creates a copy of this context for use in subqueries
  AnalysisContext copy() {
    final newContext = AnalysisContext();
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