import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:equatable/equatable.dart';
import 'data_access_provider.dart';
import 'reactive_record_builder.dart';
import 'database_stream_builder.dart';
import 'widget_helpers.dart';

/// Enhanced AutoForm family built with modern reactive patterns
/// This redesigned AutoForm leverages all the building blocks we now have:
/// - ReactiveRecordBuilder for live updates
/// - QueryBuilder for dynamic validation
/// - DataAccessProvider for dependency injection
/// - DatabaseStreamBuilder for related field lookups

/// Enhanced auto-form that leverages reactive building blocks
class ReactiveAutoForm extends StatefulWidget {
  /// The table name to build the form for
  final String tableName;
  
  /// Primary key for editing existing records (null for new records)
  final dynamic primaryKey;
  
  /// Primary key column name
  final String primaryKeyColumn;
  
  /// Field descriptors
  final List<AutoFormField> fields;
  
  /// Callback when form is saved
  final Function(Map<String, dynamic> data)? onSave;
  
  /// Callback when form is cancelled
  final VoidCallback? onCancel;
  
  /// Initial data for new records
  final Map<String, dynamic>? initialData;
  
  /// Form title
  final String? title;
  
  /// Whether to show save/cancel buttons
  final bool showActions;
  
  /// Whether to enable live preview (immediate database updates)
  final bool livePreview;
  
  /// Validation mode
  final AutovalidateMode autovalidateMode;

  const ReactiveAutoForm({
    super.key,
    required this.tableName,
    required this.fields,
    this.primaryKey,
    this.primaryKeyColumn = 'id',
    this.onSave,
    this.onCancel,
    this.initialData,
    this.title,
    this.showActions = true,
    this.livePreview = false,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  @override
  State<ReactiveAutoForm> createState() => _ReactiveAutoFormState();
}

class _ReactiveAutoFormState extends State<ReactiveAutoForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _formData = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _formData.addAll(widget.initialData!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.primaryKey != null) {
      // Editing existing record - use ReactiveRecordBuilder for live updates
      return ReactiveRecordBuilder(
        tableName: widget.tableName,
        primaryKey: widget.primaryKey!,
        primaryKeyColumn: widget.primaryKeyColumn,
        builder: (context, recordData) {
          return _buildForm(recordData);
        },
      );
    } else {
      // Creating new record
      return _buildForm(null);
    }
  }

  Widget _buildForm(RecordData? recordData) {
    final currentData = recordData?.data ?? widget.initialData ?? {};
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          autovalidateMode: widget.autovalidateMode,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              if (widget.title != null) ...[
                Text(
                  widget.title!,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ],
              
              // Form fields
              ...widget.fields.map((field) {
                final currentValue = currentData[field.columnName] ?? _formData[field.columnName];
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: field.buildField(
                    context,
                    null, // Column definition lookup could be added here
                    currentValue,
                    (columnName, value) {
                      setState(() {
                        _formData[columnName] = value;
                      });
                      
                      // Handle live preview
                      if (widget.livePreview && recordData != null) {
                        recordData.updateColumn(columnName, value);
                      }
                      
                      // Trigger validation for dependent fields
                      if (field.triggersValidation) {
                        _formKey.currentState?.validate();
                      }
                    },
                    {...currentData, ..._formData},
                    recordData: recordData,
                  ),
                );
              }).toList(),
              
              // Action buttons
              if (widget.showActions) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (widget.onCancel != null)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : widget.onCancel,
                            child: const Text('Cancel'),
                          ),
                        ),
                      ),
                    if (widget.onSave != null)
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
                              : const Text('Save'),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final finalData = {..._formData};
      
      // Perform async validation
      await _performAsyncValidation(finalData);
      
      widget.onSave?.call(finalData);
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _performAsyncValidation(Map<String, dynamic> data) async {
    // Perform async validations like uniqueness checks
    final dataAccess = getDataAccess(context, null);
    
    for (final field in widget.fields) {
      if (field.validator != null) {
        final error = field.validator!(data[field.columnName]);
        if (error != null) {
          throw Exception(error);
        }
      }
    }
  }
}

/// Batch form for editing multiple records at once
class AutoFormBatch extends StatefulWidget {
  /// The table name
  final String tableName;
  
  /// Query to select records for batch editing
  final QueryBuilder query;
  
  /// Fields to show for batch editing
  final List<AutoFormField> fields;
  
  /// Callback when batch save is completed
  final Function(List<Map<String, dynamic>> updatedRecords)? onBatchSave;
  
  /// Maximum number of records to show
  final int maxRecords;

  const AutoFormBatch({
    super.key,
    required this.tableName,
    required this.query,
    required this.fields,
    this.onBatchSave,
    this.maxRecords = 50,
  });

  @override
  State<AutoFormBatch> createState() => _AutoFormBatchState();
}

class _AutoFormBatchState extends State<AutoFormBatch> {
  final Map<dynamic, Map<String, dynamic>> _batchChanges = {};
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return DatabaseStreamBuilder<List<Map<String, dynamic>>>(
      query: widget.query.limit(widget.maxRecords),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final records = snapshot.data ?? [];
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Batch Edit (${records.length} records)',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                
                Expanded(
                  child: ListView.separated(
                    itemCount: records.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final primaryKey = record['id']; // Assuming 'id' primary key
                      
                      return _buildRecordForm(record, primaryKey);
                    },
                  ),
                ),
                
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton(
                      onPressed: _isLoading ? null : () {
                        setState(() {
                          _batchChanges.clear();
                        });
                      },
                      child: const Text('Reset'),
                    ),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleBatchSave,
                      child: _isLoading 
                        ? const CircularProgressIndicator()
                        : Text('Save ${_batchChanges.length} Changes'),
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

  Widget _buildRecordForm(Map<String, dynamic> record, dynamic primaryKey) {
    final changes = _batchChanges[primaryKey] ?? {};
    final currentData = {...record, ...changes};
    
    return ExpansionTile(
      title: Text('Record ${primaryKey}'),
      children: widget.fields.map((field) {
        final currentValue = currentData[field.columnName];
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: field.buildField(
            context,
            null,
            currentValue,
            (columnName, value) {
              setState(() {
                _batchChanges.putIfAbsent(primaryKey, () => {});
                _batchChanges[primaryKey]![columnName] = value;
              });
            },
            currentData,
          ),
        );
      }).toList(),
    );
  }

  Future<void> _handleBatchSave() async {
    setState(() => _isLoading = true);
    
    try {
      final dataAccess = getDataAccess(context, null);
      final updatedRecords = <Map<String, dynamic>>[];
      
      for (final entry in _batchChanges.entries) {
        final primaryKey = entry.key;
        final changes = entry.value;
        
        await dataAccess.update(
          widget.tableName,
          changes,
          where: 'id = ?',
          whereArgs: [primaryKey],
        );
        
        updatedRecords.add({...changes, 'id': primaryKey});
      }
      
      widget.onBatchSave?.call(updatedRecords);
      
      // Clear changes after successful save
      setState(() {
        _batchChanges.clear();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully updated ${updatedRecords.length} records'),
            backgroundColor: Colors.green,
          ),
        );
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
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

/// Enhanced form dialog with reactive features
class ReactiveAutoFormDialog {
  /// Show a dialog for creating a new record
  static Future<T?> showCreate<T>({
    required BuildContext context,
    required String tableName,
    required List<AutoFormField> fields,
    String? title,
    Map<String, dynamic>? initialData,
    bool livePreview = false,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => AlertDialog(
        title: title != null ? Text(title) : null,
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: ReactiveAutoForm(
            tableName: tableName,
            fields: fields,
            initialData: initialData,
            livePreview: livePreview,
            onSave: (data) async {
              final dataAccess = getDataAccess(context, null);
              await dataAccess.insert(tableName, data);
              Navigator.of(context).pop(data);
            },
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }

  /// Show a dialog for editing an existing record
  static Future<T?> showEdit<T>({
    required BuildContext context,
    required String tableName,
    required dynamic primaryKey,
    required List<AutoFormField> fields,
    String primaryKeyColumn = 'id',
    String? title,
    bool livePreview = false,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => AlertDialog(
        title: title != null ? Text(title) : null,
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: ReactiveAutoForm(
            tableName: tableName,
            primaryKey: primaryKey,
            primaryKeyColumn: primaryKeyColumn,
            fields: fields,
            livePreview: livePreview,
            onSave: (data) async {
              final dataAccess = getDataAccess(context, null);
              await dataAccess.update(
                tableName,
                data,
                where: '$primaryKeyColumn = ?',
                whereArgs: [primaryKey],
              );
              Navigator.of(context).pop(data);
            },
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }

  /// Show a batch editing dialog
  static Future<T?> showBatch<T>({
    required BuildContext context,
    required String tableName,
    required QueryBuilder query,
    required List<AutoFormField> fields,
    String? title,
    int maxRecords = 50,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => AlertDialog(
        title: title != null ? Text(title) : null,
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: AutoFormBatch(
            tableName: tableName,
            query: query,
            fields: fields,
            maxRecords: maxRecords,
            onBatchSave: (records) {
              Navigator.of(context).pop(records);
            },
          ),
        ),
      ),
    );
  }
}

/// Enhanced field descriptor base class
abstract class AutoFormField extends Equatable {
  final String columnName;
  final String? label;
  final bool readOnly;
  final String? Function(dynamic value)? validator;
  final bool? required;
  final bool livePreview;
  final bool triggersValidation;
  final bool Function(Map<String, dynamic> formData)? visibilityCondition;

  const AutoFormField({
    required this.columnName,
    this.label,
    this.readOnly = false,
    this.validator,
    this.required,
    this.livePreview = false,
    this.triggersValidation = false,
    this.visibilityCondition,
  });

  @override
  List<Object?> get props => [
    columnName, label, readOnly, validator, required,
    livePreview, triggersValidation, visibilityCondition,
  ];

  Widget buildField(
    BuildContext context,
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
    Map<String, dynamic> formData, {
    RecordData? recordData,
  }) {
    // Check visibility condition
    if (visibilityCondition != null && !visibilityCondition!(formData)) {
      return const SizedBox.shrink();
    }

    return buildDefaultField(
      context, 
      columnDefinition, 
      currentValue, 
      onChanged, 
      formData,
      recordData: recordData,
    );
  }

  Widget buildDefaultField(
    BuildContext context,
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
    Map<String, dynamic> formData, {
    RecordData? recordData,
  });

  String getLabel(ColumnBuilder? columnDefinition) {
    if (label != null) return label!;
    
    return columnName
        .split('_')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  bool isRequired(ColumnBuilder? columnDefinition) {
    if (required != null) return required!;
    return columnDefinition?.isNotNull ?? false;
  }

  // Factory methods for common field types
  static AutoFormTextField text(
    String columnName, {
    String? label,
    bool readOnly = false,
    String? Function(dynamic value)? validator,
    bool? required,
    String? hint,
    int? maxLines,
    bool livePreview = false,
    bool triggersValidation = false,
    bool Function(Map<String, dynamic> formData)? visibilityCondition,
  }) {
    return AutoFormTextField(
      columnName: columnName,
      label: label,
      readOnly: readOnly,
      validator: validator,
      required: required,
      hint: hint,
      maxLines: maxLines,
      livePreview: livePreview,
      triggersValidation: triggersValidation,
      visibilityCondition: visibilityCondition,
    );
  }

  static AutoFormRelatedField related(
    String columnName, {
    String? label,
    required String relatedTable,
    required String relatedValueColumn,
    String? relatedDisplayColumn,
    bool Function(Map<String, dynamic> formData)? visibilityCondition,
  }) {
    return AutoFormRelatedField(
      columnName: columnName,
      label: label,
      relatedTable: relatedTable,
      relatedValueColumn: relatedValueColumn,
      relatedDisplayColumn: relatedDisplayColumn,
      visibilityCondition: visibilityCondition,
    );
  }

  static AutoFormComputedField computed(
    String columnName, {
    String? label,
    required dynamic Function(Map<String, dynamic> formData) computation,
    Set<String>? dependsOn,
    bool Function(Map<String, dynamic> formData)? visibilityCondition,
  }) {
    return AutoFormComputedField(
      columnName: columnName,
      label: label,
      computation: computation,
      dependsOn: dependsOn,
      visibilityCondition: visibilityCondition,
    );
  }
}

/// Text field implementation
class AutoFormTextField extends AutoFormField {
  final String? hint;
  final int? maxLines;

  const AutoFormTextField({
    required super.columnName,
    super.label,
    super.readOnly = false,
    super.validator,
    super.required,
    super.livePreview = false,
    super.triggersValidation = false,
    super.visibilityCondition,
    this.hint,
    this.maxLines,
  });

  @override
  List<Object?> get props => [...super.props, hint, maxLines];

  @override
  Widget buildDefaultField(
    BuildContext context,
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
    Map<String, dynamic> formData, {
    RecordData? recordData,
  }) {
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
      maxLines: maxLines ?? 1,
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
      onChanged: (value) {
        final newValue = value.isEmpty ? null : value;
        onChanged(columnName, newValue);
        
        if (livePreview && recordData != null && newValue != currentValue) {
          recordData.updateColumn(columnName, newValue);
        }
      },
    );
  }
}

/// Related field that displays data from another table
class AutoFormRelatedField extends AutoFormField {
  final String relatedTable;
  final String relatedValueColumn;
  final String? relatedDisplayColumn;

  const AutoFormRelatedField({
    required super.columnName,
    super.label,
    super.visibilityCondition,
    required this.relatedTable,
    required this.relatedValueColumn,
    this.relatedDisplayColumn,
  }) : super(readOnly: true);

  @override
  List<Object?> get props => [...super.props, relatedTable, relatedValueColumn, relatedDisplayColumn];

  @override
  Widget buildDefaultField(
    BuildContext context,
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
    Map<String, dynamic> formData, {
    RecordData? recordData,
  }) {
    if (currentValue == null) {
      return TextFormField(
        initialValue: '',
        decoration: InputDecoration(
          labelText: getLabel(columnDefinition),
          border: const OutlineInputBorder(),
        ),
        readOnly: true,
        enabled: false,
      );
    }

    return DatabaseStreamBuilder<Map<String, dynamic>?>(
      query: QueryBuilder()
          .selectAll()
          .from(relatedTable)
          .where((cb) => cb.eq(relatedValueColumn, currentValue)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        
        final relatedData = snapshot.data;
        final displayValue = relatedData != null 
            ? (relatedDisplayColumn != null 
                ? relatedData[relatedDisplayColumn!]?.toString() 
                : relatedData[relatedValueColumn]?.toString())
            : currentValue?.toString();

        return TextFormField(
          initialValue: displayValue ?? '',
          decoration: InputDecoration(
            labelText: getLabel(columnDefinition),
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.link, color: Colors.blue),
          ),
          readOnly: true,
          enabled: false,
        );
      },
    );
  }
}

/// Computed field that calculates values from other form fields
class AutoFormComputedField extends AutoFormField {
  final dynamic Function(Map<String, dynamic> formData) computation;
  final Set<String>? dependsOn;

  const AutoFormComputedField({
    required super.columnName,
    super.label,
    super.visibilityCondition,
    required this.computation,
    this.dependsOn,
  }) : super(readOnly: true);

  @override
  List<Object?> get props => [...super.props, computation, dependsOn];

  @override
  Widget buildDefaultField(
    BuildContext context,
    ColumnBuilder? columnDefinition,
    dynamic currentValue,
    void Function(String columnName, dynamic value) onChanged,
    Map<String, dynamic> formData, {
    RecordData? recordData,
  }) {
    final computedValue = computation(formData);
    
    if (computedValue != currentValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged(columnName, computedValue);
      });
    }

    return TextFormField(
      initialValue: computedValue?.toString() ?? '',
      decoration: InputDecoration(
        labelText: getLabel(columnDefinition),
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calculate, color: Colors.blue),
      ),
      readOnly: true,
      enabled: false,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}