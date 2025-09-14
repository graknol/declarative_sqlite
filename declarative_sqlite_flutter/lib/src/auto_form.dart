import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'data_access_provider.dart';
import 'reactive_record_builder.dart';

/// Base class for form field descriptors that define how columns should be rendered
abstract class AutoFormField {
  /// The column name this field represents
  final String columnName;
  
  /// Custom label for the field (overrides auto-generated label)
  final String? label;
  
  /// Whether this field is read-only
  final bool readOnly;
  
  /// Custom validator for this field
  final String? Function(dynamic value)? validator;
  
  /// Whether this field is required (overrides schema constraint)
  final bool? required;

  const AutoFormField({
    required this.columnName,
    this.label,
    this.readOnly = false,
    this.validator,
    this.required,
  });

  /// Build the form field widget
  Widget buildField(
    BuildContext context, 
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
  );

  /// Get the display label for this field
  String getLabel(ColumnBuilder? columnDefinition) {
    if (label != null) return label!;
    
    // Convert snake_case to Title Case
    return columnName
        .split('_')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Check if this field is required
  bool isRequired(ColumnBuilder? columnDefinition) {
    if (required != null) return required!;
    return columnDefinition?.isNotNull ?? false;
  }

  /// Create a text field descriptor
  static AutoFormTextField text(
    String columnName, {
    String? label,
    bool readOnly = false,
    String? Function(dynamic value)? validator,
    bool? required,
    int? maxLines,
    TextInputType? keyboardType,
    String? hint,
  }) {
    return AutoFormTextField(
      columnName: columnName,
      label: label,
      readOnly: readOnly,
      validator: validator,
      required: required,
      maxLines: maxLines,
      keyboardType: keyboardType,
      hint: hint,
    );
  }

  /// Create a number field descriptor
  static AutoFormNumberField number(
    String columnName, {
    String? label,
    bool readOnly = false,
    String? Function(dynamic value)? validator,
    bool? required,
    bool allowDecimals = false,
    double? min,
    double? max,
  }) {
    return AutoFormNumberField(
      columnName: columnName,
      label: label,
      readOnly: readOnly,
      validator: validator,
      required: required,
      allowDecimals: allowDecimals,
      min: min,
      max: max,
    );
  }

  /// Create a counter field descriptor (number with increment/decrement buttons)
  static AutoFormCounterField counter(
    String columnName, {
    String? label,
    bool readOnly = false,
    String? Function(dynamic value)? validator,
    bool? required,
    int? min,
    int? max,
    int step = 1,
  }) {
    return AutoFormCounterField(
      columnName: columnName,
      label: label,
      readOnly: readOnly,
      validator: validator,
      required: required,
      min: min,
      max: max,
      step: step,
    );
  }

  /// Create a date field descriptor
  static AutoFormDateField date(
    String columnName, {
    String? label,
    bool readOnly = false,
    String? Function(dynamic value)? validator,
    bool? required,
    DateTime? firstDate,
    DateTime? lastDate,
  }) {
    return AutoFormDateField(
      columnName: columnName,
      label: label,
      readOnly: readOnly,
      validator: validator,
      required: required,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  /// Create a dropdown field descriptor
  static AutoFormDropdownField dropdown(
    String columnName, {
    String? label,
    bool readOnly = false,
    String? Function(dynamic value)? validator,
    bool? required,
    required List<DropdownMenuItem> items,
  }) {
    return AutoFormDropdownField(
      columnName: columnName,
      label: label,
      readOnly: readOnly,
      validator: validator,
      required: required,
      items: items,
    );
  }

  /// Create a switch field descriptor
  static AutoFormSwitchField switch_(
    String columnName, {
    String? label,
    bool readOnly = false,
    String? Function(dynamic value)? validator,
  }) {
    return AutoFormSwitchField(
      columnName: columnName,
      label: label,
      readOnly: readOnly,
      validator: validator,
    );
  }
}

/// Text field descriptor
class AutoFormTextField extends AutoFormField {
  final int? maxLines;
  final TextInputType? keyboardType;
  final String? hint;

  const AutoFormTextField({
    required super.columnName,
    super.label,
    super.readOnly = false,
    super.validator,
    super.required,
    this.maxLines,
    this.keyboardType,
    this.hint,
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
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: isRequired(columnDefinition) 
          ? const Icon(Icons.star, color: Colors.red, size: 12) 
          : null,
      ),
      maxLines: maxLines ?? (columnDefinition?.name.toLowerCase().contains('description') == true || 
                             columnDefinition?.name.toLowerCase().contains('note') == true ? 3 : 1),
      keyboardType: keyboardType,
      readOnly: readOnly,
      validator: (value) {
        if (validator != null) {
          return validator!(value);
        }
        
        if (isRequired(columnDefinition) && (value == null || value.isEmpty)) {
          return '${getLabel(columnDefinition)} is required';
        }
        
        return null;
      },
      onChanged: (value) => onChanged(columnName, value.isEmpty ? null : value),
    );
  }
}

/// Number field descriptor
class AutoFormNumberField extends AutoFormField {
  final bool allowDecimals;
  final double? min;
  final double? max;

  const AutoFormNumberField({
    required super.columnName,
    super.label,
    super.readOnly = false,
    super.validator,
    super.required,
    this.allowDecimals = false,
    this.min,
    this.max,
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
        border: const OutlineInputBorder(),
        suffixIcon: isRequired(columnDefinition) 
          ? const Icon(Icons.star, color: Colors.red, size: 12) 
          : null,
      ),
      keyboardType: allowDecimals 
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.number,
      readOnly: readOnly,
      validator: (value) {
        if (validator != null) {
          return validator!(value);
        }
        
        if (isRequired(columnDefinition) && (value == null || value.isEmpty)) {
          return '${getLabel(columnDefinition)} is required';
        }
        
        if (value != null && value.isNotEmpty) {
          final numValue = allowDecimals ? double.tryParse(value) : int.tryParse(value);
          if (numValue == null) {
            return '${getLabel(columnDefinition)} must be a ${allowDecimals ? 'number' : 'whole number'}';
          }
          
          if (min != null && numValue < min!) {
            return '${getLabel(columnDefinition)} must be at least $min';
          }
          
          if (max != null && numValue > max!) {
            return '${getLabel(columnDefinition)} must be at most $max';
          }
        }
        
        return null;
      },
      onChanged: (value) {
        if (value.isEmpty) {
          onChanged(columnName, null);
        } else {
          final numValue = allowDecimals ? double.tryParse(value) : int.tryParse(value);
          onChanged(columnName, numValue);
        }
      },
    );
  }
}

/// Counter field descriptor with increment/decrement buttons
class AutoFormCounterField extends AutoFormField {
  final int? min;
  final int? max;
  final int step;

  const AutoFormCounterField({
    required super.columnName,
    super.label,
    super.readOnly = false,
    super.validator,
    super.required,
    this.min,
    this.max,
    this.step = 1,
  });

  @override
  Widget buildField(
    BuildContext context, 
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
  ) {
    int value = currentValue is int ? currentValue : (int.tryParse(currentValue?.toString() ?? '') ?? 0);
    
    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              getLabel(columnDefinition),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: readOnly || (min != null && value <= min!) 
                      ? null 
                      : () {
                          setState(() {
                            value = (value - step).clamp(min ?? double.negativeInfinity.toInt(), max ?? double.infinity.toInt());
                          });
                          onChanged(columnName, value);
                        },
                    icon: const Icon(Icons.remove),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 60),
                    child: Text(
                      value.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: readOnly || (max != null && value >= max!) 
                      ? null 
                      : () {
                          setState(() {
                            value = (value + step).clamp(min ?? double.negativeInfinity.toInt(), max ?? double.infinity.toInt());
                          });
                          onChanged(columnName, value);
                        },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Date field descriptor
class AutoFormDateField extends AutoFormField {
  final DateTime? firstDate;
  final DateTime? lastDate;

  const AutoFormDateField({
    required super.columnName,
    super.label,
    super.readOnly = false,
    super.validator,
    super.required,
    this.firstDate,
    this.lastDate,
  });

  @override
  Widget buildField(
    BuildContext context, 
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
  ) {
    DateTime? selectedDate;
    
    if (currentValue != null) {
      if (currentValue is DateTime) {
        selectedDate = currentValue;
      } else if (currentValue is String) {
        selectedDate = DateTime.tryParse(currentValue);
      }
    }
    
    return StatefulBuilder(
      builder: (context, setState) {
        return InkWell(
          onTap: readOnly ? null : () async {
            final date = await showDatePicker(
              context: context,
              initialDate: selectedDate ?? DateTime.now(),
              firstDate: firstDate ?? DateTime(1900),
              lastDate: lastDate ?? DateTime(2100),
            );
            
            if (date != null) {
              setState(() {
                selectedDate = date;
              });
              onChanged(columnName, date.toIso8601String());
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: getLabel(columnDefinition),
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isRequired(columnDefinition))
                    const Icon(Icons.star, color: Colors.red, size: 12),
                  const Icon(Icons.calendar_today),
                ],
              ),
            ),
            child: Text(
              selectedDate != null 
                ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                : 'Select date',
              style: selectedDate == null 
                ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).hintColor,
                  )
                : null,
            ),
          ),
        );
      },
    );
  }
}

/// Dropdown field descriptor
class AutoFormDropdownField extends AutoFormField {
  final List<DropdownMenuItem> items;

  const AutoFormDropdownField({
    required super.columnName,
    super.label,
    super.readOnly = false,
    super.validator,
    super.required,
    required this.items,
  });

  @override
  Widget buildField(
    BuildContext context, 
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
  ) {
    return DropdownButtonFormField(
      value: currentValue,
      decoration: InputDecoration(
        labelText: getLabel(columnDefinition),
        border: const OutlineInputBorder(),
        suffixIcon: isRequired(columnDefinition) 
          ? const Icon(Icons.star, color: Colors.red, size: 12) 
          : null,
      ),
      items: items,
      onChanged: readOnly ? null : (value) => onChanged(columnName, value),
      validator: (value) {
        if (validator != null) {
          return validator!(value);
        }
        
        if (isRequired(columnDefinition) && value == null) {
          return '${getLabel(columnDefinition)} is required';
        }
        
        return null;
      },
    );
  }
}

/// Switch field descriptor
class AutoFormSwitchField extends AutoFormField {
  const AutoFormSwitchField({
    required super.columnName,
    super.label,
    super.readOnly = false,
    super.validator,
  });

  @override
  Widget buildField(
    BuildContext context, 
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
  ) {
    bool value = currentValue == true || currentValue == 1 || currentValue == '1';
    
    return StatefulBuilder(
      builder: (context, setState) {
        return SwitchListTile(
          title: Text(getLabel(columnDefinition)),
          value: value,
          onChanged: readOnly ? null : (newValue) {
            setState(() {
              value = newValue;
            });
            onChanged(columnName, newValue ? 1 : 0);
          },
        );
      },
    );
  }
}

/// Automatically generates a form widget from a table schema or field descriptors.
/// 
/// This widget supports two modes:
/// 1. Auto-generation from table schema (legacy mode)
/// 2. Custom field descriptors for precise control (new preferred mode)
/// 
/// ## Example Usage with Field Descriptors (Recommended)
/// 
/// ```dart
/// AutoForm.withFields(
///   tableName: 'users',
///   fields: [
///     AutoFormField.text('name'),
///     AutoFormField.text('created_by', readOnly: true),
///     AutoFormField.date('delivery_date'),
///     AutoFormField.counter('qty'),
///     AutoFormField.dropdown('status', items: statusItems),
///   ],
///   onSave: (data) {
///     print('User data: $data');
///   },
/// )
/// ```
/// 
/// ## Legacy Auto-Generation Mode
/// 
/// ```dart
/// AutoForm.fromTable(
///   tableName: 'users',
///   onSave: (data) {
///     print('User data: $data');
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
  
  /// Field descriptors (new preferred mode)
  final List<AutoFormField>? fields;
  
  /// Columns to exclude from the form (legacy mode only)
  final Set<String>? excludeColumns;
  
  /// Custom labels for columns (legacy mode only)
  final Map<String, String>? columnLabels;
  
  /// Custom validation for specific columns (legacy mode only)
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
    this.fields,
    this.excludeColumns,
    this.columnLabels,
    this.customValidators,
    this.title,
    this.showActions = true,
    this.saveButtonText,
    this.cancelButtonText,
  });

  /// Create a form using field descriptors (recommended approach)
  factory AutoForm.withFields({
    Key? key,
    DataAccess? dataAccess,
    required String tableName,
    required List<AutoFormField> fields,
    required Function(Map<String, dynamic> data) onSave,
    VoidCallback? onCancel,
    dynamic primaryKey,
    String primaryKeyColumn = 'id',
    Map<String, dynamic>? initialData,
    String? title,
    bool showActions = true,
    String? saveButtonText,
    String? cancelButtonText,
  }) {
    return AutoForm._(
      key: key,
      dataAccess: dataAccess,
      tableName: tableName,
      fields: fields,
      primaryKey: primaryKey,
      primaryKeyColumn: primaryKeyColumn,
      onSave: onSave,
      onCancel: onCancel,
      initialData: initialData,
      title: title,
      showActions: showActions,
      saveButtonText: saveButtonText,
      cancelButtonText: cancelButtonText,
    );
  }

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
    
    // Use field descriptors if provided (new preferred mode)
    if (widget.fields != null) {
      for (final field in widget.fields!) {
        final columnDefinition = table.columns.firstWhere(
          (col) => col.name == field.columnName,
          orElse: () => ColumnBuilder('', 'TEXT'), // Fallback for missing columns
        );
        
        final initialValue = currentData[field.columnName] ?? _formData[field.columnName];
        
        formFields.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: field.buildField(
              context,
              columnDefinition,
              initialValue,
              (columnName, value) {
                setState(() {
                  _formData[columnName] = value;
                });
              },
            ),
          ),
        );
      }
    } else {
      // Legacy mode: auto-generate from schema
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