import 'dart:async';
import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'data_access_provider.dart';

/// A form widget that provides automatic synchronization with LWW (Last-Write-Wins) columns.
/// 
/// This widget manages the form state and automatically handles updates to the database
/// with conflict resolution using LWW timestamps.
class LWWForm extends StatefulWidget {
  /// The data access instance for database operations
  /// If not provided, will be retrieved from DataAccessProvider
  final DataAccess? dataAccess;
  
  /// Name of the table containing the form data
  final String tableName;
  
  /// Primary key value for the record being edited
  final dynamic primaryKey;
  
  /// Child widget containing the form fields
  final Widget child;
  
  /// Callback when form data is successfully saved
  final VoidCallback? onSaved;
  
  /// Callback when form save fails
  final void Function(Object error)? onError;
  
  /// Whether to auto-save changes immediately
  final bool autoSave;
  
  /// Debounce duration for auto-save (if enabled)
  final Duration autoSaveDebounce;

  const LWWForm({
    super.key,
    this.dataAccess,
    required this.tableName,
    required this.primaryKey,
    required this.child,
    this.onSaved,
    this.onError,
    this.autoSave = false,
    this.autoSaveDebounce = const Duration(milliseconds: 500),
  });

  @override
  State<LWWForm> createState() => _LWWFormState();
  
  /// Access the LWWForm state from child widgets
  static _LWWFormState? of(BuildContext context) {
    return context.findAncestorStateOfType<_LWWFormState>();
  }
}

class _LWWFormState extends State<LWWForm> {
  final Map<String, dynamic> _pendingChanges = {};
  final Map<String, GlobalKey<FormFieldState>> _fieldKeys = {};
  Timer? _autoSaveTimer;
  bool _isSaving = false;

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  /// Register a form field with the form
  void registerField(String columnName, GlobalKey<FormFieldState> key) {
    _fieldKeys[columnName] = key;
  }

  /// Unregister a form field
  void unregisterField(String columnName) {
    _fieldKeys.remove(columnName);
    _pendingChanges.remove(columnName);
  }

  /// Update a column value with LWW semantics
  Future<void> updateColumn(String columnName, dynamic value) async {
    if (_isSaving) return;

    _pendingChanges[columnName] = value;

    if (widget.autoSave) {
      _scheduleAutoSave();
    }
  }

  /// Manually save all pending changes
  Future<void> save() async {
    if (_isSaving || _pendingChanges.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final effectiveDataAccess = getDataAccess(context, widget.dataAccess);
      
      // Update each changed column with LWW semantics
      for (final entry in _pendingChanges.entries) {
        await effectiveDataAccess.updateLWWColumn(
          widget.tableName,
          widget.primaryKey,
          entry.key,
          entry.value,
        );
      }

      _pendingChanges.clear();
      widget.onSaved?.call();
    } catch (error) {
      widget.onError?.call(error);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Validate all form fields
  bool validate() {
    bool isValid = true;
    for (final key in _fieldKeys.values) {
      if (key.currentState?.validate() == false) {
        isValid = false;
      }
    }
    return isValid;
  }

  /// Get current form data including pending changes
  Future<Map<String, dynamic>?> getCurrentData() async {
    try {
      final effectiveDataAccess = getDataAccess(context, widget.dataAccess);
      final currentData = await effectiveDataAccess.getByPrimaryKey(
        widget.tableName,
        widget.primaryKey,
      );
      
      if (currentData != null) {
        return {...currentData, ..._pendingChanges};
      }
      return _pendingChanges.isNotEmpty ? _pendingChanges : null;
    } catch (e) {
      return _pendingChanges.isNotEmpty ? _pendingChanges : null;
    }
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(widget.autoSaveDebounce, () {
      if (mounted && _pendingChanges.isNotEmpty) {
        save();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      child: Stack(
        children: [
          widget.child,
          if (_isSaving)
            Positioned.fill(
              child: Container(
                color: Colors.black12,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Inherited widget to provide LWW form context to child widgets
class LWWFormData extends InheritedWidget {
  final _LWWFormState formState;

  const LWWFormData({
    super.key,
    required this.formState,
    required super.child,
  });

  static LWWFormData? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LWWFormData>();
  }

  @override
  bool updateShouldNotify(LWWFormData oldWidget) {
    return formState != oldWidget.formState;
  }
}

/// Base class for LWW-enabled form fields
abstract class LWWFormField<T> extends StatefulWidget {
  /// Column name in the database
  final String columnName;
  
  /// Initial value for the field
  final T? initialValue;
  
  /// Validator function
  final String? Function(T? value)? validator;
  
  /// Called when the value changes
  final void Function(T? value)? onChanged;

  const LWWFormField({
    super.key,
    required this.columnName,
    this.initialValue,
    this.validator,
    this.onChanged,
  });
}

/// Base state class for LWW form fields
abstract class LWWFormFieldState<T, W extends LWWFormField<T>>
    extends State<W> {
  final GlobalKey<FormFieldState<T>> _key = GlobalKey<FormFieldState<T>>();
  _LWWFormState? _formState;
  T? _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final newFormState = LWWForm.of(context);
    if (_formState != newFormState) {
      _formState?.unregisterField(widget.columnName);
      _formState = newFormState;
      _formState?.registerField(widget.columnName, _key);
    }
  }

  @override
  void dispose() {
    _formState?.unregisterField(widget.columnName);
    super.dispose();
  }

  /// Handle value changes and notify the form
  void handleValueChange(T? value) {
    setState(() => _currentValue = value);
    _formState?.updateColumn(widget.columnName, value);
    widget.onChanged?.call(value);
  }

  /// Get the current value
  T? get currentValue => _currentValue;

  /// Get the form field key
  GlobalKey<FormFieldState<T>> get fieldKey => _key;
}