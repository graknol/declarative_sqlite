import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'data_access_provider.dart';
import 'reactive_record_builder.dart';

/// Automatically generates a form widget from a table schema with validation.
/// 
/// This widget inspects the table schema and creates appropriate form fields
/// for each column, including validation based on schema constraints.
/// 
/// ## Example Usage
/// 
/// ```dart
/// AutoForm.fromTable(
///   tableName: 'users',
///   onSave: (data) {
///     print('User data: $data');
///     // Handle save logic
///   },
///   onCancel: () {
///     Navigator.pop(context);
///   },
/// )
/// ```
/// 
/// For editing existing records:
/// 
/// ```dart
/// AutoForm.fromRecord(
///   tableName: 'users',
///   primaryKey: userId,
///   onSave: (data) {
///     print('Updated user: $data');
///   },
/// )
/// ```
class AutoForm extends StatefulWidget {
  /// The data access instance for database operations
  /// If not provided, will be retrieved from DataAccessProvider
  final DataAccess? dataAccess;
  
  /// Name of the table to generate form for
  final String tableName;
  
  /// Primary key value for editing existing records (null for new records)
  final dynamic primaryKey;
  
  /// Name of the primary key column (defaults to 'id')
  final String primaryKeyColumn;
  
  /// Callback when form is saved with valid data
  final Function(Map<String, dynamic> data) onSave;
  
  /// Optional callback when form is cancelled
  final VoidCallback? onCancel;
  
  /// Initial data for new records
  final Map<String, dynamic>? initialData;
  
  /// Columns to exclude from the form
  final Set<String>? excludeColumns;
  
  /// Custom labels for columns (column_name -> label)
  final Map<String, String>? columnLabels;
  
  /// Custom validation for specific columns
  final Map<String, String? Function(dynamic value)>? customValidators;
  
  /// Form title
  final String? title;
  
  /// Whether to show save/cancel buttons
  final bool showActions;
  
  /// Custom save button text
  final String? saveButtonText;
  
  /// Custom cancel button text
  final String? cancelButtonText;

  const AutoForm._({
    super.key,
    this.dataAccess,
    required this.tableName,
    this.primaryKey,
    this.primaryKeyColumn = 'id',
    required this.onSave,
    this.onCancel,
    this.initialData,
    this.excludeColumns,
    this.columnLabels,
    this.customValidators,
    this.title,
    this.showActions = true,
    this.saveButtonText,
    this.cancelButtonText,
  });

  /// Create a form for adding new records to a table
  factory AutoForm.fromTable({
    Key? key,
    DataAccess? dataAccess,
    required String tableName,
    required Function(Map<String, dynamic> data) onSave,
    VoidCallback? onCancel,
    Map<String, dynamic>? initialData,
    Set<String>? excludeColumns,
    Map<String, String>? columnLabels,
    Map<String, String? Function(dynamic value)>? customValidators,
    String? title,
    bool showActions = true,
    String? saveButtonText,
    String? cancelButtonText,
  }) {
    return AutoForm._(
      key: key,
      dataAccess: dataAccess,
      tableName: tableName,
      onSave: onSave,
      onCancel: onCancel,
      initialData: initialData,
      excludeColumns: excludeColumns,
      columnLabels: columnLabels,
      customValidators: customValidators,
      title: title,
      showActions: showActions,
      saveButtonText: saveButtonText,
      cancelButtonText: cancelButtonText,
    );
  }

  /// Create a form for editing existing records
  factory AutoForm.fromRecord({
    Key? key,
    DataAccess? dataAccess,
    required String tableName,
    required dynamic primaryKey,
    String primaryKeyColumn = 'id',
    required Function(Map<String, dynamic> data) onSave,
    VoidCallback? onCancel,
    Set<String>? excludeColumns,
    Map<String, String>? columnLabels,
    Map<String, String? Function(dynamic value)>? customValidators,
    String? title,
    bool showActions = true,
    String? saveButtonText,
    String? cancelButtonText,
  }) {
    return AutoForm._(
      key: key,
      dataAccess: dataAccess,
      tableName: tableName,
      primaryKey: primaryKey,
      primaryKeyColumn: primaryKeyColumn,
      onSave: onSave,
      onCancel: onCancel,
      excludeColumns: excludeColumns,
      columnLabels: columnLabels,
      customValidators: customValidators,
      title: title,
      showActions: showActions,
      saveButtonText: saveButtonText,
      cancelButtonText: cancelButtonText,
    );
  }

  @override
  State<AutoForm> createState() => _AutoFormState();
}

class _AutoFormState extends State<AutoForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _formData = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeFormData();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initializeFormData() {
    if (widget.initialData != null) {
      _formData.addAll(widget.initialData!);
    }
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

  /// Get human-readable label for a column
  String _getColumnLabel(String columnName) {
    if (widget.columnLabels?.containsKey(columnName) == true) {
      return widget.columnLabels![columnName]!;
    }
    
    // Convert snake_case to Title Case
    return columnName
        .split('_')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Check if a column should be included in the form
  bool _shouldIncludeColumn(ColumnBuilder column) {
    // Exclude columns specified by user
    if (widget.excludeColumns?.contains(column.name) == true) {
      return false;
    }
    
    // For editing mode, exclude primary key
    if (widget.primaryKey != null && column.name == widget.primaryKeyColumn) {
      return false;
    }
    
    // Exclude auto-increment columns
    if (column.isAutoIncrement) {
      return false;
    }
    
    // Exclude LWW timestamp columns (they're managed automatically)
    if (column.name.endsWith('_lww_timestamp')) {
      return false;
    }
    
    return true;
  }

  /// Create appropriate form field for a column
  Widget _buildFormField(ColumnBuilder column, dynamic initialValue) {
    final label = _getColumnLabel(column.name);
    
    // Initialize controller with current value
    if (!_controllers.containsKey(column.name)) {
      _controllers[column.name] = TextEditingController(
        text: initialValue?.toString() ?? '',
      );
    }
    
    final controller = _controllers[column.name]!;
    
    // Build validator
    String? Function(String?) validator = (value) {
      // Custom validator takes precedence
      if (widget.customValidators?.containsKey(column.name) == true) {
        return widget.customValidators![column.name]!(value);
      }
      
      // Required validation
      if (column.isNotNull && (value == null || value.isEmpty)) {
        return '$label is required';
      }
      
      // Type-specific validation
      if (value != null && value.isNotEmpty) {
        switch (column.dataType) {
          case 'INTEGER':
            if (int.tryParse(value) == null) {
              return '$label must be a number';
            }
            break;
          case 'REAL':
            if (double.tryParse(value) == null) {
              return '$label must be a decimal number';
            }
            break;
        }
      }
      
      return null;
    };

    // Handle different data types
    switch (column.dataType) {
      case 'INTEGER':
        return TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: column.isNotNull ? const Icon(Icons.star, color: Colors.red, size: 12) : null,
          ),
          keyboardType: TextInputType.number,
          validator: validator,
          onSaved: (value) {
            if (value != null && value.isNotEmpty) {
              _formData[column.name] = int.tryParse(value);
            } else if (!column.isNotNull) {
              _formData[column.name] = null;
            }
          },
        );
        
      case 'REAL':
        return TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: column.isNotNull ? const Icon(Icons.star, color: Colors.red, size: 12) : null,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: validator,
          onSaved: (value) {
            if (value != null && value.isNotEmpty) {
              _formData[column.name] = double.tryParse(value);
            } else if (!column.isNotNull) {
              _formData[column.name] = null;
            }
          },
        );
        
      case 'TEXT':
      default:
        return TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: column.isNotNull ? const Icon(Icons.star, color: Colors.red, size: 12) : null,
          ),
          maxLines: column.name.toLowerCase().contains('description') || 
                    column.name.toLowerCase().contains('note') ? 3 : 1,
          validator: validator,
          onSaved: (value) {
            if (value != null && value.isNotEmpty) {
              _formData[column.name] = value;
            } else if (!column.isNotNull) {
              _formData[column.name] = null;
            }
          },
        );
    }
  }

  /// Handle form submission
  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      _formKey.currentState!.save();
      
      // For editing mode, merge with existing data
      if (widget.primaryKey != null) {
        final dataAccess = _getDataAccess();
        final existing = await dataAccess.getByPrimaryKey(widget.tableName, widget.primaryKey);
        if (existing != null) {
          final mergedData = {...existing, ..._formData};
          widget.onSave(mergedData);
        } else {
          widget.onSave(_formData);
        }
      } else {
        widget.onSave(_formData);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = _getTableDefinition();
    
    if (table == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Table "${widget.tableName}" not found in schema'),
        ),
      );
    }

    // For editing mode, use ReactiveRecordBuilder to get current data
    if (widget.primaryKey != null) {
      return ReactiveRecordBuilder(
        dataAccess: widget.dataAccess,
        tableName: widget.tableName,
        primaryKey: widget.primaryKey,
        primaryKeyColumn: widget.primaryKeyColumn,
        builder: (context, recordData) {
          return _buildForm(table, recordData?.data ?? {});
        },
      );
    }
    
    // For new records, build form directly
    return _buildForm(table, widget.initialData ?? {});
  }

  Widget _buildForm(TableBuilder table, Map<String, dynamic> currentData) {
    final formFields = <Widget>[];
    
    // Add title if provided
    if (widget.title != null) {
      formFields.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Text(
            widget.title!,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    
    // Create form fields for each column
    for (final column in table.columns) {
      if (_shouldIncludeColumn(column)) {
        final initialValue = currentData[column.name] ?? _formData[column.name];
        
        formFields.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: _buildFormField(column, initialValue),
          ),
        );
      }
    }
    
    // Add action buttons if enabled
    if (widget.showActions) {
      formFields.add(
        Padding(
          padding: const EdgeInsets.only(top: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (widget.onCancel != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : widget.onCancel,
                      child: Text(widget.cancelButtonText ?? 'Cancel'),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSave,
                    child: _isLoading 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.saveButtonText ?? 'Save'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: formFields,
          ),
        ),
      ),
    );
  }
}

/// A convenience widget for creating auto-forms as dialog overlays
class AutoFormDialog extends StatelessWidget {
  /// The AutoForm widget to display in the dialog
  final AutoForm form;
  
  /// Dialog title (overrides AutoForm title)
  final String? title;
  
  /// Whether the dialog can be dismissed by tapping outside
  final bool barrierDismissible;

  const AutoFormDialog({
    super.key,
    required this.form,
    this.title,
    this.barrierDismissible = true,
  });

  /// Show an auto-form dialog for creating new records
  static Future<T?> showCreate<T>({
    required BuildContext context,
    DataAccess? dataAccess,
    required String tableName,
    required Function(Map<String, dynamic> data) onSave,
    Map<String, dynamic>? initialData,
    Set<String>? excludeColumns,
    Map<String, String>? columnLabels,
    Map<String, String? Function(dynamic value)>? customValidators,
    String? title,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => AutoFormDialog(
        title: title,
        barrierDismissible: barrierDismissible,
        form: AutoForm.fromTable(
          dataAccess: dataAccess,
          tableName: tableName,
          onSave: (data) {
            Navigator.of(context).pop();
            onSave(data);
          },
          onCancel: () => Navigator.of(context).pop(),
          initialData: initialData,
          excludeColumns: excludeColumns,
          columnLabels: columnLabels,
          customValidators: customValidators,
          title: title,
        ),
      ),
    );
  }

  /// Show an auto-form dialog for editing existing records
  static Future<T?> showEdit<T>({
    required BuildContext context,
    DataAccess? dataAccess,
    required String tableName,
    required dynamic primaryKey,
    String primaryKeyColumn = 'id',
    required Function(Map<String, dynamic> data) onSave,
    Set<String>? excludeColumns,
    Map<String, String>? columnLabels,
    Map<String, String? Function(dynamic value)>? customValidators,
    String? title,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => AutoFormDialog(
        title: title,
        barrierDismissible: barrierDismissible,
        form: AutoForm.fromRecord(
          dataAccess: dataAccess,
          tableName: tableName,
          primaryKey: primaryKey,
          primaryKeyColumn: primaryKeyColumn,
          onSave: (data) {
            Navigator.of(context).pop();
            onSave(data);
          },
          onCancel: () => Navigator.of(context).pop(),
          excludeColumns: excludeColumns,
          columnLabels: columnLabels,
          customValidators: customValidators,
          title: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: title != null ? Text(title!) : null,
      content: SingleChildScrollView(
        child: form,
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: EdgeInsets.zero,
      actions: const [], // Actions are handled by the form itself
    );
  }
}