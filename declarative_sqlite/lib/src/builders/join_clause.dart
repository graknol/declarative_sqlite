import 'aliased.dart';
import 'analysis_context.dart';
import 'query_dependencies.dart';
import 'where_clause.dart';

class JoinClause {
  final String type; // 'INNER', 'LEFT', 'RIGHT', 'FULL OUTER', etc.
  final Aliased<String> table;
  final WhereClause onCondition;

  JoinClause(this.type, this.table, this.onCondition);

  /// Factory constructors for common join types
  factory JoinClause.inner(String table, WhereClause onCondition, [String? alias]) {
    return JoinClause('INNER', Aliased(table, alias), onCondition);
  }

  factory JoinClause.left(String table, WhereClause onCondition, [String? alias]) {
    return JoinClause('LEFT', Aliased(table, alias), onCondition);
  }

  factory JoinClause.right(String table, WhereClause onCondition, [String? alias]) {
    return JoinClause('RIGHT', Aliased(table, alias), onCondition);
  }

  factory JoinClause.fullOuter(String table, WhereClause onCondition, [String? alias]) {
    return JoinClause('FULL OUTER', Aliased(table, alias), onCondition);
  }

  BuiltJoinClause build() {
    final builtCondition = onCondition.build();
    final sql = '$type JOIN ${table.toString()} ON ${builtCondition.sql}';
    return BuiltJoinClause(sql, builtCondition.parameters);
  }

  /// Analyzes this JOIN clause to extract table and column dependencies
  QueryDependencies analyzeDependencies(AnalysisContext context) {
    var dependencies = QueryDependencies.empty();
    
    // Add the joined table to context for proper resolution
    context.addTable(table.expression, alias: table.alias);
    
    // Add the joined table to dependencies
    dependencies = dependencies.merge(QueryDependencies(
      tables: {table.toString()}, // Use toString() to include alias if present
      columns: <QueryDependencyColumn>{},
      usesWildcard: false,
    ));
    
    // Analyze the ON condition dependencies
    dependencies = dependencies.merge(onCondition.analyzeDependencies(context));
    
    return dependencies;
  }
}

/// Represents a built JOIN clause with SQL and parameters
class BuiltJoinClause {
  final String sql;
  final List<Object?> parameters;

  BuiltJoinClause(this.sql, this.parameters);
}