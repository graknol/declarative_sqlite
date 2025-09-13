import 'package:flutter/material.dart';
import 'lww_form.dart';

/// A dropdown widget that automatically syncs with an LWW column in the database.
class LWWDropdown<T> extends LWWFormField<T> {
  /// List of dropdown items
  final List<DropdownMenuItem<T>> items;
  
  /// Input decoration for the dropdown
  final InputDecoration? decoration;
  
  /// Hint text when no value is selected
  final Widget? hint;
  
  /// Widget to display when dropdown is disabled
  final Widget? disabledHint;
  
  /// Icon for the dropdown
  final Widget? icon;
  
  /// Size of the dropdown icon
  final double iconSize;
  
  /// Whether the dropdown is expanded to fill width
  final bool isExpanded;
  
  /// Style for the dropdown text
  final TextStyle? style;
  
  /// Dropdown button height
  final double? itemHeight;
  
  /// Focus node for the dropdown
  final FocusNode? focusNode;
  
  /// Whether dropdown auto-focuses
  final bool autofocus;
  
  /// Color for the dropdown
  final Color? dropdownColor;

  const LWWDropdown({
    super.key,
    required super.columnName,
    required this.items,
    super.initialValue,
    super.validator,
    super.onChanged,
    this.decoration,
    this.hint,
    this.disabledHint,
    this.icon,
    this.iconSize = 24.0,
    this.isExpanded = true,
    this.style,
    this.itemHeight,
    this.focusNode,
    this.autofocus = false,
    this.dropdownColor,
  });

  @override
  State<LWWDropdown<T>> createState() => _LWWDropdownState<T>();
}

class _LWWDropdownState<T> extends LWWFormFieldState<T, LWWDropdown<T>> {
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: fieldKey,
      value: currentValue,
      items: widget.items,
      decoration: widget.decoration,
      hint: widget.hint,
      disabledHint: widget.disabledHint,
      icon: widget.icon,
      iconSize: widget.iconSize,
      isExpanded: widget.isExpanded,
      style: widget.style,
      itemHeight: widget.itemHeight,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      dropdownColor: widget.dropdownColor,
      validator: widget.validator,
      onChanged: (value) {
        handleValueChange(value);
      },
    );
  }
}

/// A dropdown widget for selecting from a database table.
class LWWDatabaseDropdown extends LWWFormField<dynamic> {
  /// Data access instance for loading dropdown options
  final DataAccess dataAccess;
  
  /// Table name to load options from
  final String optionsTable;
  
  /// Column name for the option value
  final String valueColumn;
  
  /// Column name for the option display text
  final String displayColumn;
  
  /// Optional WHERE clause to filter options
  final String? where;
  
  /// Optional WHERE clause arguments
  final List<dynamic>? whereArgs;
  
  /// Optional ORDER BY clause for options
  final String? orderBy;
  
  /// Input decoration for the dropdown
  final InputDecoration? decoration;
  
  /// Hint text when no value is selected
  final Widget? hint;
  
  /// Widget to display when loading options
  final Widget? loadingWidget;
  
  /// Widget to display when loading fails
  final Widget Function(Object error)? errorBuilder;
  
  /// Whether the dropdown is expanded to fill width
  final bool isExpanded;

  const LWWDatabaseDropdown({
    super.key,
    required super.columnName,
    required this.dataAccess,
    required this.optionsTable,
    required this.valueColumn,
    required this.displayColumn,
    super.initialValue,
    super.validator,
    super.onChanged,
    this.where,
    this.whereArgs,
    this.orderBy,
    this.decoration,
    this.hint,
    this.loadingWidget,
    this.errorBuilder,
    this.isExpanded = true,
  });

  @override
  State<LWWDatabaseDropdown> createState() => _LWWDatabaseDropdownState();
}

class _LWWDatabaseDropdownState extends LWWFormFieldState<dynamic, LWWDatabaseDropdown> {
  List<Map<String, dynamic>>? _options;
  Object? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void didUpdateWidget(LWWDatabaseDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Reload options if query parameters changed
    if (oldWidget.optionsTable != widget.optionsTable ||
        oldWidget.valueColumn != widget.valueColumn ||
        oldWidget.displayColumn != widget.displayColumn ||
        oldWidget.where != widget.where ||
        oldWidget.whereArgs != widget.whereArgs ||
        oldWidget.orderBy != widget.orderBy) {
      _loadOptions();
    }
  }

  Future<void> _loadOptions() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final options = await widget.dataAccess.getAllWhere(
        widget.optionsTable,
        where: widget.where,
        whereArgs: widget.whereArgs,
        orderBy: widget.orderBy,
      );

      if (mounted) {
        setState(() {
          _options = options;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.loadingWidget ?? 
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ),
        );
    }

    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(_error!);
      }
      return Text(
        'Error loading options: $_error',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    final options = _options ?? [];
    
    return DropdownButtonFormField<dynamic>(
      key: fieldKey,
      value: currentValue,
      items: options.map((option) {
        final value = option[widget.valueColumn];
        final display = option[widget.displayColumn]?.toString() ?? value?.toString() ?? '';
        
        return DropdownMenuItem<dynamic>(
          value: value,
          child: Text(display),
        );
      }).toList(),
      decoration: widget.decoration,
      hint: widget.hint,
      isExpanded: widget.isExpanded,
      validator: widget.validator,
      onChanged: (value) {
        handleValueChange(value);
      },
    );
  }
}

/// A checkbox list tile widget that syncs with an LWW boolean column.
class LWWCheckboxListTile extends LWWFormField<bool> {
  /// Title for the checkbox
  final Widget? title;
  
  /// Subtitle for the checkbox
  final Widget? subtitle;
  
  /// Secondary widget (usually an icon)
  final Widget? secondary;
  
  /// Whether the checkbox is tristate
  final bool tristate;
  
  /// Active color for the checkbox
  final Color? activeColor;
  
  /// Checkmark color
  final Color? checkColor;
  
  /// Control affinity (leading, trailing, or platform default)
  final ListTileControlAffinity controlAffinity;
  
  /// Whether the list tile is dense
  final bool dense;

  const LWWCheckboxListTile({
    super.key,
    required super.columnName,
    super.initialValue,
    super.validator,
    super.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.tristate = false,
    this.activeColor,
    this.checkColor,
    this.controlAffinity = ListTileControlAffinity.platform,
    this.dense = false,
  });

  @override
  State<LWWCheckboxListTile> createState() => _LWWCheckboxListTileState();
}

class _LWWCheckboxListTileState extends LWWFormFieldState<bool, LWWCheckboxListTile> {
  @override
  Widget build(BuildContext context) {
    return FormField<bool>(
      key: fieldKey,
      initialValue: currentValue,
      validator: widget.validator,
      builder: (FormFieldState<bool> field) {
        return CheckboxListTile(
          value: currentValue,
          title: widget.title,
          subtitle: widget.subtitle,
          secondary: widget.secondary,
          tristate: widget.tristate,
          activeColor: widget.activeColor,
          checkColor: widget.checkColor,
          controlAffinity: widget.controlAffinity,
          dense: widget.dense,
          onChanged: (value) {
            field.didChange(value);
            handleValueChange(value);
          },
        );
      },
    );
  }
}