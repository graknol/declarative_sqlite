import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'data_access_provider.dart';
import 'reactive_record_builder.dart';
import 'auto_form.dart';

/// A widget that provides visual browsing and editing of database schemas and data.
/// 
/// This widget displays the database schema in a hierarchical view, allowing users to:
/// - Browse tables and their column definitions
/// - View and edit table data
/// - Add, edit, and delete records
/// - See relationships between tables
/// 
/// ## Example Usage
/// 
/// ```dart
/// SchemaInspector(
///   schema: schema,  // Optional if DataAccessProvider is available
///   title: 'Database Browser',
/// )
/// ```
class SchemaInspector extends StatefulWidget {
  /// The database schema to inspect
  /// If not provided, will be retrieved from DataAccessProvider
  final Schema? schema;
  
  /// The data access instance for database operations
  /// If not provided, will be retrieved from DataAccessProvider
  final DataAccess? dataAccess;
  
  /// Inspector title
  final String? title;
  
  /// Whether to show table data by default
  final bool expandDataByDefault;
  
  /// Maximum number of records to show per table
  final int maxRecordsPerTable;

  const SchemaInspector({
    super.key,
    this.schema,
    this.dataAccess,
    this.title,
    this.expandDataByDefault = false,
    this.maxRecordsPerTable = 50,
  });

  @override
  State<SchemaInspector> createState() => _SchemaInspectorState();
}

class _SchemaInspectorState extends State<SchemaInspector> {
  String? _selectedTableName;
  bool _showTableData = false;

  DataAccess _getDataAccess() {
    return getDataAccess(context, widget.dataAccess);
  }

  Schema _getSchema() {
    return widget.schema ?? _getDataAccess().schema;
  }

  @override
  Widget build(BuildContext context) {
    final schema = _getSchema();
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Schema Inspector'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Row(
        children: [
          // Left panel: Schema tree
          Expanded(
            flex: 1,
            child: _buildSchemaTree(schema),
          ),
          
          // Right panel: Table details/data
          if (_selectedTableName != null)
            Expanded(
              flex: 2,
              child: _buildTableDetails(schema, _selectedTableName!),
            ),
        ],
      ),
    );
  }

  Widget _buildSchemaTree(Schema schema) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tables (${schema.tables.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: schema.tables.length,
                itemBuilder: (context, index) {
                  final table = schema.tables[index];
                  final isSelected = _selectedTableName == table.name;
                  
                  return Card(
                    color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
                    child: ListTile(
                      leading: const Icon(Icons.table_chart),
                      title: Text(
                        table.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text('${table.columns.length} columns'),
                      onTap: () {
                        setState(() {
                          _selectedTableName = table.name;
                          _showTableData = widget.expandDataByDefault;
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableDetails(Schema schema, String tableName) {
    final table = schema.tables.firstWhere((t) => t.name == tableName);
    
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // Table header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.table_chart, color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  tableName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Schema'), icon: Icon(Icons.account_tree)),
                    ButtonSegment(value: true, label: Text('Data'), icon: Icon(Icons.storage)),
                  ],
                  selected: {_showTableData},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _showTableData = selection.first;
                    });
                  },
                ),
              ],
            ),
          ),
          
          // Content area
          Expanded(
            child: _showTableData
                ? _buildTableDataView(table)
                : _buildTableSchemaView(table),
          ),
        ],
      ),
    );
  }

  Widget _buildTableSchemaView(TableBuilder table) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Columns (${table.columns.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: table.columns.length,
              itemBuilder: (context, index) {
                final column = table.columns[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      _getColumnIcon(column.dataType),
                      color: column.isNotNull ? Colors.red : Colors.grey,
                    ),
                    title: Text(
                      column.name,
                      style: TextStyle(
                        fontWeight: column.isPrimaryKey ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(_getColumnDescription(column)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (column.isPrimaryKey) 
                          const Chip(
                            label: Text('PK', style: TextStyle(fontSize: 10)),
                            backgroundColor: Colors.orange,
                          ),
                        if (column.isUnique) 
                          const Chip(
                            label: Text('UQ', style: TextStyle(fontSize: 10)),
                            backgroundColor: Colors.blue,
                          ),
                        if (column.isNotNull) 
                          const Chip(
                            label: Text('NN', style: TextStyle(fontSize: 10)),
                            backgroundColor: Colors.red,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Indices section
          if (table.indices.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Indices (${table.indices.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...table.indices.map((index) => Card(
              child: ListTile(
                leading: const Icon(Icons.speed),
                title: Text(index.name),
                subtitle: Text('Columns: ${index.columns.join(', ')}'),
                trailing: index.isUnique 
                  ? const Chip(
                      label: Text('UNIQUE', style: TextStyle(fontSize: 10)),
                      backgroundColor: Colors.green,
                    )
                  : null,
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildTableDataView(TableBuilder table) {
    return Column(
      children: [
        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _showAddRecordDialog(table),
                icon: const Icon(Icons.add),
                label: const Text('Add Record'),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: () => _refreshData(),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        
        // Data grid
        Expanded(
          child: ReactiveRecordListBuilder(
            dataAccess: widget.dataAccess,
            tableName: table.name,
            limit: widget.maxRecordsPerTable,
            itemBuilder: (context, recordData) => _buildDataRow(table, recordData),
            emptyWidget: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No data found', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataRow(TableBuilder table, RecordData recordData) {
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            '${recordData[table.primaryKeyColumn] ?? '?'}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(_getPrimaryDisplayValue(table, recordData)),
        subtitle: Text('Record ID: ${recordData[table.primaryKeyColumn]}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditRecordDialog(table, recordData),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _showDeleteConfirmation(recordData),
              tooltip: 'Delete',
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: table.columns.map((column) {
                final value = recordData[column.name];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          column.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value?.toString() ?? '<null>',
                          style: TextStyle(
                            color: value == null ? Colors.grey : null,
                            fontStyle: value == null ? FontStyle.italic : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getColumnIcon(String dataType) {
    switch (dataType.toUpperCase()) {
      case 'INTEGER':
        return Icons.numbers;
      case 'REAL':
        return Icons.decimal_increase;
      case 'TEXT':
        return Icons.text_fields;
      case 'BLOB':
        return Icons.data_object;
      default:
        return Icons.help_outline;
    }
  }

  String _getColumnDescription(ColumnBuilder column) {
    final parts = <String>[];
    parts.add(column.dataType);
    
    if (column.isAutoIncrement) parts.add('AUTO_INCREMENT');
    if (column.hasDefaultValue && column.defaultValue != null) {
      parts.add('DEFAULT ${column.defaultValue}');
    }
    
    return parts.join(' | ');
  }

  String _getPrimaryDisplayValue(TableBuilder table, RecordData recordData) {
    // Try to find a displayable column (name, title, etc.)
    final displayColumns = ['name', 'title', 'label', 'description', 'email'];
    
    for (final columnName in displayColumns) {
      final value = recordData[columnName];
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }
    
    // Fall back to first text column
    for (final column in table.columns) {
      if (column.dataType == 'TEXT' && column.name != table.primaryKeyColumn) {
        final value = recordData[column.name];
        if (value != null && value.toString().isNotEmpty) {
          return value.toString();
        }
      }
    }
    
    return 'Record';
  }

  void _showAddRecordDialog(TableBuilder table) {
    AutoFormDialog.showCreate(
      context: context,
      dataAccess: widget.dataAccess,
      tableName: table.name,
      title: 'Add ${table.name}',
      onSave: (data) async {
        try {
          final dataAccess = _getDataAccess();
          await dataAccess.insert(table.name, data);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Record added successfully')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error adding record: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  void _showEditRecordDialog(TableBuilder table, RecordData recordData) {
    AutoFormDialog.showEdit(
      context: context,
      dataAccess: widget.dataAccess,
      tableName: table.name,
      primaryKey: recordData.primaryKey,
      primaryKeyColumn: recordData.primaryKeyColumn,
      title: 'Edit ${table.name}',
      onSave: (data) async {
        try {
          await recordData.updateColumns(data);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Record updated successfully')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error updating record: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  void _showDeleteConfirmation(RecordData recordData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Record'),
        content: Text('Are you sure you want to delete this record? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await recordData.delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Record deleted successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting record: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _refreshData() {
    // Force refresh by rebuilding the widget
    setState(() {});
  }
}