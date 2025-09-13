import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'database_stream_builder.dart';

/// Collection of reactive widgets that automatically update when database data changes.
class ReactiveWidgets {
  ReactiveWidgets._();

  /// Creates a Text widget that updates when a specific database value changes.
  static Widget text({
    required DataAccess dataAccess,
    required String tableName,
    required dynamic primaryKey,
    required String columnName,
    TextStyle? style,
    String? prefix,
    String? suffix,
    String Function(dynamic value)? formatter,
    Widget? loadingWidget,
    Widget? errorWidget,
  }) {
    return DatabaseRecordBuilder(
      dataAccess: dataAccess,
      tableName: tableName,
      primaryKey: primaryKey,
      loadingWidget: loadingWidget,
      errorBuilder: errorWidget != null ? (context, error) => errorWidget : null,
      builder: (context, record) {
        if (record == null) return const Text('--');
        
        final value = record[columnName];
        String displayText;
        
        if (formatter != null) {
          displayText = formatter(value);
        } else {
          displayText = value?.toString() ?? '--';
        }
        
        if (prefix != null) displayText = prefix + displayText;
        if (suffix != null) displayText = displayText + suffix;
        
        return Text(displayText, style: style);
      },
    );
  }

  /// Creates a Badge widget that shows a count from a database query.
  static Widget countBadge({
    required DataAccess dataAccess,
    required String tableName,
    required Widget child,
    String? where,
    List<dynamic>? whereArgs,
    Color? backgroundColor,
    Color? textColor,
    bool showZero = false,
  }) {
    return DatabaseQueryBuilder(
      dataAccess: dataAccess,
      tableName: tableName,
      where: where,
      whereArgs: whereArgs,
      builder: (context, results) {
        final count = results.length;
        
        if (count == 0 && !showZero) {
          return child;
        }
        
        return Badge(
          label: Text(
            count.toString(),
            style: TextStyle(color: textColor),
          ),
          backgroundColor: backgroundColor,
          child: child,
        );
      },
    );
  }

  /// Creates a progress indicator that shows completion percentage.
  static Widget progressIndicator({
    required DataAccess dataAccess,
    required String tableName,
    required String statusColumn,
    required String completedValue,
    String? where,
    List<dynamic>? whereArgs,
    Color? backgroundColor,
    Color? valueColor,
    double height = 8.0,
    bool showPercentage = true,
  }) {
    return DatabaseQueryBuilder(
      dataAccess: dataAccess,
      tableName: tableName,
      where: where,
      whereArgs: whereArgs,
      builder: (context, results) {
        if (results.isEmpty) {
          return const LinearProgressIndicator(value: 0);
        }
        
        final total = results.length;
        final completed = results.where((row) => row[statusColumn] == completedValue).length;
        final progress = completed / total;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress,
              backgroundColor: backgroundColor,
              valueColor: valueColor != null 
                  ? AlwaysStoppedAnimation<Color>(valueColor) 
                  : null,
              minHeight: height,
            ),
            if (showPercentage)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  '${(progress * 100).toInt()}% ($completed/$total)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Creates a Chart widget showing data distribution.
  static Widget distributionChart({
    required DataAccess dataAccess,
    required String tableName,
    required String groupColumn,
    String? where,
    List<dynamic>? whereArgs,
    Color? color,
    double height = 200,
  }) {
    return DatabaseQueryBuilder(
      dataAccess: dataAccess,
      tableName: tableName,
      where: where,
      whereArgs: whereArgs,
      builder: (context, results) {
        if (results.isEmpty) {
          return SizedBox(
            height: height,
            child: const Center(
              child: Text('No data to display'),
            ),
          );
        }
        
        // Group and count by the specified column
        final groups = <String, int>{};
        for (final row in results) {
          final groupValue = row[groupColumn]?.toString() ?? 'Unknown';
          groups[groupValue] = (groups[groupValue] ?? 0) + 1;
        }
        
        return SizedBox(
          height: height,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Distribution by $groupColumn',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final entry = groups.entries.elementAt(index);
                        final percentage = (entry.value / results.length * 100).toInt();
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(entry.key),
                              ),
                              Expanded(
                                flex: 5,
                                child: LinearProgressIndicator(
                                  value: entry.value / results.length,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    color ?? Theme.of(context).primaryColor,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${entry.value} ($percentage%)',
                                  textAlign: TextAlign.end,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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

  /// Creates a status card with live data.
  static Widget statusCard({
    required DataAccess dataAccess,
    required String tableName,
    required String title,
    required String valueColumn,
    dynamic primaryKey,
    String? where,
    List<dynamic>? whereArgs,
    String Function(dynamic value)? formatter,
    IconData? icon,
    Color? color,
    VoidCallback? onTap,
  }) {
    Widget buildCard(BuildContext context, String value) {
      return Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: color),
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
                const SizedBox(height: 8),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (primaryKey != null) {
      // Single record
      return DatabaseRecordBuilder(
        dataAccess: dataAccess,
        tableName: tableName,
        primaryKey: primaryKey,
        builder: (context, record) {
          if (record == null) return buildCard(context, '--');
          
          final value = record[valueColumn];
          final displayValue = formatter != null ? formatter(value) : value?.toString() ?? '--';
          
          return buildCard(context, displayValue);
        },
      );
    } else {
      // Aggregate value
      return DatabaseQueryBuilder(
        dataAccess: dataAccess,
        tableName: tableName,
        where: where,
        whereArgs: whereArgs,
        builder: (context, results) {
          String displayValue;
          
          if (results.isEmpty) {
            displayValue = '0';
          } else if (valueColumn == 'COUNT') {
            displayValue = results.length.toString();
          } else {
            // Sum numeric values
            final sum = results.fold<double>(0, (sum, row) {
              final value = row[valueColumn];
              if (value is num) return sum + value.toDouble();
              return sum;
            });
            displayValue = formatter != null ? formatter(sum) : sum.toString();
          }
          
          return buildCard(context, displayValue);
        },
      );
    }
  }

  /// Creates a live data table with automatic updates.
  static Widget dataTable({
    required DataAccess dataAccess,
    required String tableName,
    required List<String> columns,
    required Map<String, String> columnLabels,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    bool sortAscending = true,
    String? sortColumn,
    void Function(String column)? onSort,
    Map<String, String Function(dynamic value)>? formatters,
  }) {
    return DatabaseQueryBuilder(
      dataAccess: dataAccess,
      tableName: tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      builder: (context, results) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            sortColumnIndex: sortColumn != null ? columns.indexOf(sortColumn) : null,
            sortAscending: sortAscending,
            columns: columns.map((column) {
              return DataColumn(
                label: Text(columnLabels[column] ?? column),
                onSort: onSort != null ? (columnIndex, ascending) => onSort(column) : null,
              );
            }).toList(),
            rows: results.map((row) {
              return DataRow(
                cells: columns.map((column) {
                  final value = row[column];
                  final formatter = formatters?[column];
                  final displayValue = formatter != null 
                      ? formatter(value) 
                      : value?.toString() ?? '';
                  
                  return DataCell(Text(displayValue));
                }).toList(),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}