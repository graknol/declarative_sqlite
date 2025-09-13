import 'package:flutter/material.dart';
import 'lww_form.dart';

/// A slider widget that automatically syncs with an LWW numeric column in the database.
class LWWSlider extends LWWFormField<double> {
  /// Minimum value for the slider
  final double min;
  
  /// Maximum value for the slider
  final double max;
  
  /// Number of discrete divisions on the slider
  final int? divisions;
  
  /// Label to display for the slider
  final String? label;
  
  /// Format function for the value label
  final String Function(double value)? labelFormatter;
  
  /// Whether to show the value label
  final bool showValueLabel;
  
  /// Active color for the slider
  final Color? activeColor;
  
  /// Inactive color for the slider
  final Color? inactiveColor;
  
  /// Thumb color for the slider
  final Color? thumbColor;

  const LWWSlider({
    super.key,
    required super.columnName,
    required this.min,
    required this.max,
    super.initialValue,
    super.validator,
    super.onChanged,
    this.divisions,
    this.label,
    this.labelFormatter,
    this.showValueLabel = true,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
  });

  @override
  State<LWWSlider> createState() => _LWWSliderState();
}

class _LWWSliderState extends LWWFormFieldState<double, LWWSlider> {
  late double _currentSliderValue;

  @override
  void initState() {
    super.initState();
    _currentSliderValue = widget.initialValue ?? widget.min;
  }

  @override
  void didUpdateWidget(LWWSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _currentSliderValue = widget.initialValue ?? widget.min;
    }
  }

  String _formatValue(double value) {
    if (widget.labelFormatter != null) {
      return widget.labelFormatter!(value);
    }
    
    if (widget.divisions != null) {
      return value.toInt().toString();
    }
    
    return value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return FormField<double>(
      key: fieldKey,
      initialValue: _currentSliderValue,
      validator: widget.validator,
      builder: (FormFieldState<double> field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null)
              Text(
                widget.label!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            Row(
              children: [
                Text(
                  _formatValue(widget.min),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Expanded(
                  child: Slider(
                    value: _currentSliderValue,
                    min: widget.min,
                    max: widget.max,
                    divisions: widget.divisions,
                    activeColor: widget.activeColor,
                    inactiveColor: widget.inactiveColor,
                    thumbColor: widget.thumbColor,
                    label: widget.showValueLabel ? _formatValue(_currentSliderValue) : null,
                    onChanged: (value) {
                      setState(() {
                        _currentSliderValue = value;
                      });
                      field.didChange(value);
                      handleValueChange(value);
                    },
                  ),
                ),
                Text(
                  _formatValue(widget.max),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (widget.showValueLabel)
              Center(
                child: Text(
                  'Value: ${_formatValue(_currentSliderValue)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  field.errorText!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// An integer slider widget that syncs with an LWW integer column.
class LWWIntSlider extends LWWFormField<int> {
  /// Minimum value for the slider
  final int min;
  
  /// Maximum value for the slider
  final int max;
  
  /// Label to display for the slider
  final String? label;
  
  /// Format function for the value label
  final String Function(int value)? labelFormatter;
  
  /// Whether to show the value label
  final bool showValueLabel;
  
  /// Active color for the slider
  final Color? activeColor;
  
  /// Inactive color for the slider
  final Color? inactiveColor;
  
  /// Thumb color for the slider
  final Color? thumbColor;

  const LWWIntSlider({
    super.key,
    required super.columnName,
    required this.min,
    required this.max,
    super.initialValue,
    super.validator,
    super.onChanged,
    this.label,
    this.labelFormatter,
    this.showValueLabel = true,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
  });

  @override
  State<LWWIntSlider> createState() => _LWWIntSliderState();
}

class _LWWIntSliderState extends LWWFormFieldState<int, LWWIntSlider> {
  late int _currentSliderValue;

  @override
  void initState() {
    super.initState();
    _currentSliderValue = widget.initialValue ?? widget.min;
  }

  @override
  void didUpdateWidget(LWWIntSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _currentSliderValue = widget.initialValue ?? widget.min;
    }
  }

  String _formatValue(int value) {
    if (widget.labelFormatter != null) {
      return widget.labelFormatter!(value);
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return FormField<int>(
      key: fieldKey,
      initialValue: _currentSliderValue,
      validator: widget.validator,
      builder: (FormFieldState<int> field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null)
              Text(
                widget.label!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            Row(
              children: [
                Text(
                  _formatValue(widget.min),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Expanded(
                  child: Slider(
                    value: _currentSliderValue.toDouble(),
                    min: widget.min.toDouble(),
                    max: widget.max.toDouble(),
                    divisions: widget.max - widget.min,
                    activeColor: widget.activeColor,
                    inactiveColor: widget.inactiveColor,
                    thumbColor: widget.thumbColor,
                    label: widget.showValueLabel ? _formatValue(_currentSliderValue) : null,
                    onChanged: (value) {
                      final intValue = value.round();
                      setState(() {
                        _currentSliderValue = intValue;
                      });
                      field.didChange(intValue);
                      handleValueChange(intValue);
                    },
                  ),
                ),
                Text(
                  _formatValue(widget.max),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (widget.showValueLabel)
              Center(
                child: Text(
                  'Value: ${_formatValue(_currentSliderValue)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  field.errorText!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}