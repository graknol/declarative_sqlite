import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'database_query.dart';
import 'data_access_provider.dart';

/// Base class for query field descriptors that define how search fields should be rendered
abstract class QueryField {
  /// The column name this field searches
  final String columnName;
  
  /// Custom label for the field
  final String? label;
  
  /// Whether this field is enabled by default
  final bool enabledByDefault;

  const QueryField({
    required this.columnName,
    this.label,
    this.enabledByDefault = true,
  });

  /// Build the query field widget
  Widget buildField(
    BuildContext context,
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
  );

  /// Apply this field's current value to the query builder
  void applyToQuery(DatabaseQueryBuilder queryBuilder, dynamic value);

  /// Get the display label for this field
  String getLabel(ColumnBuilder? columnDefinition) {
    if (label != null) return label!;
    
    // Convert snake_case to Title Case
    return columnName
        .split('_')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Create a text search field descriptor
  static QueryTextField text(
    String columnName, {
    String? label,
    bool enabledByDefault = true,
    String? placeholder,
  }) {
    return QueryTextField(
      columnName: columnName,
      label: label,
      enabledByDefault: enabledByDefault,
      placeholder: placeholder,
    );
  }

  /// Create a multiselect field descriptor
  static QueryMultiselectField multiselect(
    String columnName, {
    String? label,
    bool enabledByDefault = true,
    required List<String> options,
  }) {
    return QueryMultiselectField(
      columnName: columnName,
      label: label,
      enabledByDefault: enabledByDefault,
      options: options,
    );
  }

  /// Create a date range field descriptor
  static QueryDateRangeField dateRange(
    String columnName, {
    String? label,
    bool enabledByDefault = true,
    DateTime? minDate,
    DateTime? maxDate,
  }) {
    return QueryDateRangeField(
      columnName: columnName,
      label: label,
      enabledByDefault: enabledByDefault,
      minDate: minDate,
      maxDate: maxDate,
    );
  }

  /// Create a slider range field descriptor
  static QuerySliderRangeField sliderRange(
    String columnName, {
    String? label,
    bool enabledByDefault = true,
    required double min,
    required double max,
    int? divisions,
  }) {
    return QuerySliderRangeField(
      columnName: columnName,
      label: label,
      enabledByDefault: enabledByDefault,
      min: min,
      max: max,
      divisions: divisions,
    );
  }
}

/// Text search field descriptor
class QueryTextField extends QueryField {
  final String? placeholder;

  const QueryTextField({
    required super.columnName,
    super.label,
    super.enabledByDefault = true,
    this.placeholder,
  });

  @override
  Widget buildField(
    BuildContext context,
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
  ) {
    return TextFormField(
      initialValue: currentValue?.toString() ?? '',
      decoration: InputDecoration(
        labelText: getLabel(columnDefinition),
        hintText: placeholder,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (value) => onChanged(columnName, value.isEmpty ? null : value),
    );
  }

  @override
  void applyToQuery(DatabaseQueryBuilder queryBuilder, dynamic value) {
    if (value != null && value.toString().isNotEmpty) {
      queryBuilder.whereLike(columnName, '%$value%');
    }
  }
}

/// Multiselect field descriptor
class QueryMultiselectField extends QueryField {
  final List<String> options;

  const QueryMultiselectField({
    required super.columnName,
    super.label,
    super.enabledByDefault = true,
    required this.options,
  });

  @override
  Widget buildField(
    BuildContext context,
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
  ) {
    final selectedValues = currentValue as List<String>? ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          getLabel(columnDefinition),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: options.map((option) {
            final isSelected = selectedValues.contains(option);
            return FilterChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (selected) {
                final newValues = List<String>.from(selectedValues);
                if (selected) {
                  newValues.add(option);
                } else {
                  newValues.remove(option);
                }
                onChanged(columnName, newValues.isEmpty ? null : newValues);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  void applyToQuery(DatabaseQueryBuilder queryBuilder, dynamic value) {
    if (value is List<String> && value.isNotEmpty) {
      queryBuilder.whereIn(columnName, value);
    }
  }
}

/// Date range field descriptor
class QueryDateRangeField extends QueryField {
  final DateTime? minDate;
  final DateTime? maxDate;

  const QueryDateRangeField({
    required super.columnName,
    super.label,
    super.enabledByDefault = true,
    this.minDate,
    this.maxDate,
  });

  @override
  Widget buildField(
    BuildContext context,
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
  ) {
    final dateRange = currentValue as DateTimeRange?;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          getLabel(columnDefinition),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: minDate ?? DateTime(1900),
              lastDate: maxDate ?? DateTime(2100),
              initialDateRange: dateRange,
            );
            
            if (picked != null) {
              onChanged(columnName, picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(Icons.date_range),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dateRange != null
                        ? '${_formatDate(dateRange.start)} - ${_formatDate(dateRange.end)}'
                        : 'Select date range',
                    style: dateRange == null
                        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).hintColor,
                          )
                        : null,
                  ),
                ),
                if (dateRange != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () => onChanged(columnName, null),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  void applyToQuery(DatabaseQueryBuilder queryBuilder, dynamic value) {
    if (value is DateTimeRange) {
      queryBuilder.whereDateRange(columnName, value.start, value.end);
    }
  }
}

/// Slider range field descriptor
class QuerySliderRangeField extends QueryField {
  final double min;
  final double max;
  final int? divisions;

  const QuerySliderRangeField({
    required super.columnName,
    super.label,
    super.enabledByDefault = true,
    required this.min,
    required this.max,
    this.divisions,
  });

  @override
  Widget buildField(
    BuildContext context,
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
  ) {
    final range = currentValue as RangeValues? ?? RangeValues(min, max);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              getLabel(columnDefinition),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${range.start.round()} - ${range.end.round()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        RangeSlider(
          values: range,
          min: min,
          max: max,
          divisions: divisions,
          labels: RangeLabels(
            range.start.round().toString(),
            range.end.round().toString(),
          ),
          onChanged: (values) => onChanged(columnName, values),
        ),
      ],
    );
  }

  @override
  void applyToQuery(DatabaseQueryBuilder queryBuilder, dynamic value) {
    if (value is RangeValues) {
      queryBuilder.whereRange(columnName, value.start, value.end);
    }
  }
}

/// A widget that provides faceted search capabilities with a free text search field
/// and customizable query fields.
/// 
/// This widget creates a dynamic query builder interface that supports hot swapping
/// of query parameters, making it ideal for faceted search scenarios.
/// 
/// ## Example Usage
/// 
/// ```dart
/// QueryBuilderWidget(
///   tableName: 'orders',
///   freeTextSearchColumns: ['customer_name', 'product_name'],
///   fields: [
///     QueryField.multiselect('status', options: ['PENDING', 'SHIPPED', 'DELIVERED']),
///     QueryField.dateRange('order_date'),
///     QueryField.sliderRange('total_amount', min: 0, max: 1000),
///     QueryField.text('customer_name'),
///   ],
///   onQueryChanged: (query) {
///     // Update your reactive widgets with the new query
///     setState(() {
///       currentQuery = query;
///     });
///   },
/// )
/// ```
class QueryBuilderWidget extends StatefulWidget {
  /// The data access instance for database operations
  /// If not provided, will be retrieved from DataAccessProvider
  final DataAccess? dataAccess;
  
  /// Table name to build queries for
  final String tableName;
  
  /// Columns to include in free text search
  final List<String> freeTextSearchColumns;
  
  /// Query field descriptors
  final List<QueryField> fields;
  
  /// Callback when the query changes
  final Function(DatabaseQuery query) onQueryChanged;
  
  /// Placeholder text for the free text search field
  final String? searchPlaceholder;
  
  /// Whether to show the free text search field
  final bool showFreeTextSearch;
  
  /// Initial query values
  final Map<String, dynamic>? initialValues;

  const QueryBuilderWidget({
    super.key,
    this.dataAccess,
    required this.tableName,
    this.freeTextSearchColumns = const [],
    required this.fields,
    required this.onQueryChanged,
    this.searchPlaceholder,
    this.showFreeTextSearch = true,
    this.initialValues,
  });

  @override
  State<QueryBuilderWidget> createState() => _QueryBuilderWidgetState();
}

class _QueryBuilderWidgetState extends State<QueryBuilderWidget> {
  final Map<String, dynamic> _queryValues = {};
  String _freeTextSearch = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialValues != null) {
      _queryValues.addAll(widget.initialValues!);
    }
    _buildAndNotifyQuery();
  }

  DataAccess _getDataAccess() {
    return getDataAccess(context, widget.dataAccess);
  }

  /// Get the table definition from the schema
  TableBuilder? _getTableDefinition() {
    final dataAccess = _getDataAccess();
    final schema = dataAccess.schema;
    
    for (final table in schema.tables) {
      if (table.name == widget.tableName) {
        return table;
      }
    }
    return null;
  }

  ColumnBuilder? _getColumnDefinition(String columnName) {
    final table = _getTableDefinition();
    if (table == null) return null;
    
    for (final column in table.columns) {
      if (column.name == columnName) {
        return column;
      }
    }
    return null;
  }

  void _updateQueryValue(String key, dynamic value) {
    setState(() {
      if (value == null) {
        _queryValues.remove(key);
      } else {
        _queryValues[key] = value;
      }
    });
    _buildAndNotifyQuery();
  }

  void _updateFreeTextSearch(String text) {
    setState(() {
      _freeTextSearch = text;
    });
    _buildAndNotifyQuery();
  }

  void _buildAndNotifyQuery() {
    final queryBuilder = DatabaseQueryBuilder.facetedSearch(widget.tableName);
    
    // Add free text search
    if (_freeTextSearch.isNotEmpty && widget.freeTextSearchColumns.isNotEmpty) {
      queryBuilder.freeTextSearch(_freeTextSearch, widget.freeTextSearchColumns);
    }
    
    // Apply field constraints
    for (final field in widget.fields) {
      final value = _queryValues[field.columnName];
      if (value != null) {
        field.applyToQuery(queryBuilder, value);
      }
    }
    
    final query = queryBuilder.build();
    widget.onQueryChanged(query);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Free text search
            if (widget.showFreeTextSearch) ...[
              TextFormField(
                initialValue: _freeTextSearch,
                decoration: InputDecoration(
                  labelText: 'Search',
                  hintText: widget.searchPlaceholder ?? 'Search across all fields...',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _freeTextSearch.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _updateFreeTextSearch(''),
                        )
                      : null,
                ),
                onChanged: _updateFreeTextSearch,
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
            ],
            
            // Query fields
            ...widget.fields.map((field) {
              final columnDefinition = _getColumnDefinition(field.columnName);
              final currentValue = _queryValues[field.columnName];
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: field.buildField(
                  context,
                  columnDefinition,
                  currentValue,
                  _updateQueryValue,
                ),
              );
            }),
            
            // Clear all button
            if (_queryValues.isNotEmpty || _freeTextSearch.isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _queryValues.clear();
                      _freeTextSearch = '';
                    });
                    _buildAndNotifyQuery();
                  },
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear All Filters'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}