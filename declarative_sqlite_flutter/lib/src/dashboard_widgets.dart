import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'data_access_provider.dart';
import 'database_stream_builder.dart';
import 'reactive_record_builder.dart';

/// Pre-built dashboard components for common database analytics and monitoring.
/// 
/// Provides easy-to-use widgets for displaying counts, trends, distributions,
/// and other common dashboard patterns from database tables.
class DashboardWidgets {
  /// Create a count card showing total records in a table
  static Widget countCard({
    DataAccess? dataAccess,
    required String tableName,
    required String title,
    String? subtitle,
    String? where,
    List<dynamic>? whereArgs,
    IconData? icon,
    Color? color,
    VoidCallback? onTap,
  }) {
    return _CountCard(
      dataAccess: dataAccess,
      tableName: tableName,
      title: title,
      subtitle: subtitle,
      where: where,
      whereArgs: whereArgs,
      icon: icon,
      color: color,
      onTap: onTap,
    );
  }

  /// Create a status distribution chart showing value frequencies
  static Widget statusDistribution({
    DataAccess? dataAccess,
    required String tableName,
    required String statusColumn,
    required String title,
    String? where,
    List<dynamic>? whereArgs,
    Color? color,
  }) {
    return _StatusDistribution(
      dataAccess: dataAccess,
      tableName: tableName,
      statusColumn: statusColumn,
      title: title,
      where: where,
      whereArgs: whereArgs,
      color: color,
    );
  }

  /// Create a simple trend indicator (comparing current period to previous)
  static Widget trendIndicator({
    DataAccess? dataAccess,
    required String tableName,
    required String title,
    required String dateColumn,
    String? where,
    List<dynamic>? whereArgs,
    Duration period = const Duration(days: 7),
    IconData? icon,
    Color? color,
  }) {
    return _TrendIndicator(
      dataAccess: dataAccess,
      tableName: tableName,
      title: title,
      dateColumn: dateColumn,
      where: where,
      whereArgs: whereArgs,
      period: period,
      icon: icon,
      color: color,
    );
  }

  /// Create a summary table of aggregated data
  static Widget summaryTable({
    DataAccess? dataAccess,
    required String tableName,
    required Map<String, String> aggregations, // column -> function (COUNT, SUM, AVG, etc.)
    required String title,
    String? groupBy,
    String? where,
    List<dynamic>? whereArgs,
    int? limit,
  }) {
    return _SummaryTable(
      dataAccess: dataAccess,
      tableName: tableName,
      aggregations: aggregations,
      title: title,
      groupBy: groupBy,
      where: where,
      whereArgs: whereArgs,
      limit: limit,
    );
  }
}

class _CountCard extends StatelessWidget {
  final DataAccess? dataAccess;
  final String tableName;
  final String title;
  final String? subtitle;
  final String? where;
  final List<dynamic>? whereArgs;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  const _CountCard({
    this.dataAccess,
    required this.tableName,
    required this.title,
    this.subtitle,
    this.where,
    this.whereArgs,
    this.icon,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveDataAccess = getDataAccess(context, dataAccess);
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    
    return DatabaseStreamBuilder<int>(
      dataAccess: effectiveDataAccess,
      query: () => effectiveDataAccess.count(
        tableName,
        where: where,
        whereArgs: whereArgs,
      ),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        
        return Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: effectiveColor, size: 32),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      count.toString(),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: effectiveColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusDistribution extends StatelessWidget {
  final DataAccess? dataAccess;
  final String tableName;
  final String statusColumn;
  final String title;
  final String? where;
  final List<dynamic>? whereArgs;
  final Color? color;

  const _StatusDistribution({
    this.dataAccess,
    required this.tableName,
    required this.statusColumn,
    required this.title,
    this.where,
    this.whereArgs,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveDataAccess = getDataAccess(context, dataAccess);
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    
    return DatabaseStreamBuilder<List<Map<String, dynamic>>>(
      dataAccess: effectiveDataAccess,
      query: () => effectiveDataAccess.rawQuery(
        '''
        SELECT $statusColumn, COUNT(*) as count 
        FROM $tableName 
        ${where != null ? 'WHERE $where' : ''}
        GROUP BY $statusColumn 
        ORDER BY count DESC
        ''',
        whereArgs ?? [],
      ),
      builder: (context, snapshot) {
        final distributions = snapshot.data ?? [];
        final total = distributions.fold<int>(0, (sum, item) => sum + (item['count'] as int? ?? 0));
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (distributions.isEmpty)
                  const Center(
                    child: Text(
                      'No data available',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...distributions.map((item) {
                    final status = item[statusColumn]?.toString() ?? 'Unknown';
                    final count = item['count'] as int? ?? 0;
                    final percentage = total > 0 ? (count / total * 100) : 0.0;
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  status,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              Text(
                                '$count (${percentage.toStringAsFixed(1)}%)',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: percentage / 100,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrendIndicator extends StatelessWidget {
  final DataAccess? dataAccess;
  final String tableName;
  final String title;
  final String dateColumn;
  final String? where;
  final List<dynamic>? whereArgs;
  final Duration period;
  final IconData? icon;
  final Color? color;

  const _TrendIndicator({
    this.dataAccess,
    required this.tableName,
    required this.title,
    required this.dateColumn,
    this.where,
    this.whereArgs,
    this.period = const Duration(days: 7),
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveDataAccess = getDataAccess(context, dataAccess);
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    
    return DatabaseStreamBuilder<Map<String, int>>(
      dataAccess: effectiveDataAccess,
      query: () async {
        final now = DateTime.now();
        final currentPeriodStart = now.subtract(period);
        final previousPeriodStart = currentPeriodStart.subtract(period);
        
        final whereClause = where != null ? '$where AND' : '';
        
        final currentResult = await effectiveDataAccess.rawQuery(
          '''
          SELECT COUNT(*) as count 
          FROM $tableName 
          WHERE $whereClause $dateColumn >= ? AND $dateColumn < ?
          ''',
          [...?whereArgs, currentPeriodStart.toIso8601String(), now.toIso8601String()],
        );
        
        final previousResult = await effectiveDataAccess.rawQuery(
          '''
          SELECT COUNT(*) as count 
          FROM $tableName 
          WHERE $whereClause $dateColumn >= ? AND $dateColumn < ?
          ''',
          [...?whereArgs, previousPeriodStart.toIso8601String(), currentPeriodStart.toIso8601String()],
        );
        
        return {
          'current': currentResult.first['count'] as int? ?? 0,
          'previous': previousResult.first['count'] as int? ?? 0,
        };
      },
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          );
        }
        
        final data = snapshot.data ?? {'current': 0, 'previous': 0};
        final current = data['current']!;
        final previous = data['previous']!;
        
        final change = current - previous;
        final percentChange = previous > 0 ? (change / previous * 100) : 0.0;
        
        final isPositive = change >= 0;
        final trendColor = isPositive ? Colors.green : Colors.red;
        final trendIcon = isPositive ? Icons.trending_up : Icons.trending_down;
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: effectiveColor, size: 24),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  current.toString(),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: effectiveColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(trendIcon, color: trendColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${isPositive ? '+' : ''}$change (${percentChange.toStringAsFixed(1)}%)',
                      style: TextStyle(
                        color: trendColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'vs last ${period.inDays} days',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SummaryTable extends StatelessWidget {
  final DataAccess? dataAccess;
  final String tableName;
  final Map<String, String> aggregations;
  final String title;
  final String? groupBy;
  final String? where;
  final List<dynamic>? whereArgs;
  final int? limit;

  const _SummaryTable({
    this.dataAccess,
    required this.tableName,
    required this.aggregations,
    required this.title,
    this.groupBy,
    this.where,
    this.whereArgs,
    this.limit,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveDataAccess = getDataAccess(context, dataAccess);
    
    return DatabaseStreamBuilder<List<Map<String, dynamic>>>(
      dataAccess: effectiveDataAccess,
      query: () {
        final selectClauses = <String>[];
        
        if (groupBy != null) {
          selectClauses.add(groupBy!);
        }
        
        for (final entry in aggregations.entries) {
          selectClauses.add('${entry.value}(${entry.key}) as ${entry.key}_${entry.value.toLowerCase()}');
        }
        
        final selectClause = selectClauses.join(', ');
        final groupClause = groupBy != null ? 'GROUP BY $groupBy' : '';
        final whereClause = where != null ? 'WHERE $where' : '';
        final limitClause = limit != null ? 'LIMIT $limit' : '';
        
        final query = '''
          SELECT $selectClause
          FROM $tableName
          $whereClause
          $groupClause
          $limitClause
        ''';
        
        return effectiveDataAccess.rawQuery(query, whereArgs ?? []);
      },
      builder: (context, snapshot) {
        final data = snapshot.data ?? [];
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (data.isEmpty)
                  const Center(
                    child: Text(
                      'No data available',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: data.first.keys.map((key) {
                        return DataColumn(
                          label: Text(
                            key.toString().replaceAll('_', ' ').toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                      rows: data.map((row) {
                        return DataRow(
                          cells: row.values.map((value) {
                            return DataCell(
                              Text(value?.toString() ?? ''),
                            );
                          }).toList(),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A pre-built dashboard grid layout that arranges dashboard widgets in a responsive grid.
class DashboardGrid extends StatelessWidget {
  /// List of dashboard widgets to display
  final List<Widget> widgets;
  
  /// Number of columns in the grid (defaults to responsive based on screen width)
  final int? crossAxisCount;
  
  /// Spacing between grid items
  final double spacing;
  
  /// Child aspect ratio for grid items
  final double childAspectRatio;
  
  /// Scroll controller for the grid
  final ScrollController? controller;
  
  /// Whether the grid should shrink wrap
  final bool shrinkWrap;
  
  /// Grid padding
  final EdgeInsetsGeometry? padding;

  const DashboardGrid({
    super.key,
    required this.widgets,
    this.crossAxisCount,
    this.spacing = 16.0,
    this.childAspectRatio = 1.2,
    this.controller,
    this.shrinkWrap = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final effectiveCrossAxisCount = crossAxisCount ?? _getResponsiveCrossAxisCount(screenWidth);
    
    return GridView.count(
      controller: controller,
      shrinkWrap: shrinkWrap,
      padding: padding ?? const EdgeInsets.all(16.0),
      crossAxisCount: effectiveCrossAxisCount,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      childAspectRatio: childAspectRatio,
      children: widgets,
    );
  }

  int _getResponsiveCrossAxisCount(double screenWidth) {
    if (screenWidth < 600) return 1; // Mobile
    if (screenWidth < 900) return 2; // Tablet
    if (screenWidth < 1200) return 3; // Small desktop
    return 4; // Large desktop
  }
}