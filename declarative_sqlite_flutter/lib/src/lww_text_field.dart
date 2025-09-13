import 'package:flutter/material.dart';
import 'lww_form.dart';

/// A text field widget that automatically syncs with an LWW column in the database.
class LWWTextField extends LWWFormField<String> {
  /// Input decoration for the text field
  final InputDecoration? decoration;
  
  /// Text input type
  final TextInputType? keyboardType;
  
  /// Text capitalization behavior
  final TextCapitalization textCapitalization;
  
  /// Maximum number of lines
  final int? maxLines;
  
  /// Minimum number of lines
  final int? minLines;
  
  /// Maximum length of text
  final int? maxLength;
  
  /// Whether the field is obscured (for passwords)
  final bool obscureText;
  
  /// Text align
  final TextAlign textAlign;
  
  /// Whether the field is enabled
  final bool enabled;
  
  /// Whether the field is read-only
  final bool readOnly;
  
  /// Auto-focus behavior
  final bool autofocus;

  const LWWTextField({
    super.key,
    required super.columnName,
    super.initialValue,
    super.validator,
    super.onChanged,
    this.decoration,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.obscureText = false,
    this.textAlign = TextAlign.start,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
  });

  @override
  State<LWWTextField> createState() => _LWWTextFieldState();
}

class _LWWTextFieldState extends LWWFormFieldState<String, LWWTextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void didUpdateWidget(LWWTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: _controller,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      obscureText: widget.obscureText,
      textAlign: widget.textAlign,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      validator: widget.validator,
      onChanged: (value) {
        handleValueChange(value.isEmpty ? null : value);
      },
    );
  }
}

/// A text field that supports multiline input for LWW columns.
class LWWTextArea extends LWWTextField {
  const LWWTextArea({
    super.key,
    required super.columnName,
    super.initialValue,
    super.validator,
    super.onChanged,
    super.decoration,
    super.keyboardType = TextInputType.multiline,
    super.textCapitalization,
    super.maxLines = null,
    super.minLines = 3,
    super.maxLength,
    super.textAlign,
    super.enabled,
    super.readOnly,
    super.autofocus,
  });
}

/// A password field for LWW columns.
class LWWPasswordField extends LWWTextField {
  /// Whether to show a toggle button for password visibility
  final bool showVisibilityToggle;

  const LWWPasswordField({
    super.key,
    required super.columnName,
    super.initialValue,
    super.validator,
    super.onChanged,
    super.decoration,
    super.keyboardType = TextInputType.visiblePassword,
    super.textCapitalization,
    super.maxLength,
    super.textAlign,
    super.enabled,
    super.readOnly,
    super.autofocus,
    this.showVisibilityToggle = true,
  }) : super(
         obscureText: true,
         maxLines: 1,
       );

  @override
  State<LWWPasswordField> createState() => _LWWPasswordFieldState();
}

class _LWWPasswordFieldState extends LWWFormFieldState<String, LWWPasswordField> {
  late TextEditingController _controller;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void didUpdateWidget(LWWPasswordField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: _controller,
      decoration: widget.decoration?.copyWith(
        suffixIcon: widget.showVisibilityToggle
            ? IconButton(
                icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText;
                  });
                },
              )
            : widget.decoration?.suffixIcon,
      ),
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      maxLines: 1,
      maxLength: widget.maxLength,
      obscureText: _obscureText,
      textAlign: widget.textAlign,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      validator: widget.validator,
      onChanged: (value) {
        handleValueChange(value.isEmpty ? null : value);
      },
    );
  }
}