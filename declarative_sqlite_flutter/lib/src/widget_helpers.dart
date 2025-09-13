import 'dart:async';
import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Utility functions and helpers for Flutter integration with declarative_sqlite.
class WidgetHelpers {
  WidgetHelpers._();

  /// Creates a validator for required fields
  static String? Function(T? value) required<T>([String? message]) {
    return (T? value) {
      if (value == null || (value is String && value.isEmpty)) {
        return message ?? 'This field is required';
      }
      return null;
    };
  }

  /// Creates a validator for email fields
  static String? Function(String? value) email([String? message]) {
    return (String? value) {
      if (value == null || value.isEmpty) return null;
      
      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
      if (!emailRegex.hasMatch(value)) {
        return message ?? 'Please enter a valid email address';
      }
      return null;
    };
  }

  /// Creates a validator for minimum length
  static String? Function(String? value) minLength(int length, [String? message]) {
    return (String? value) {
      if (value == null || value.isEmpty) return null;
      
      if (value.length < length) {
        return message ?? 'Must be at least $length characters';
      }
      return null;
    };
  }

  /// Creates a validator for maximum length
  static String? Function(String? value) maxLength(int length, [String? message]) {
    return (String? value) {
      if (value == null || value.isEmpty) return null;
      
      if (value.length > length) {
        return message ?? 'Must be no more than $length characters';
      }
      return null;
    };
  }

  /// Creates a validator for numeric range
  static String? Function(num? value) range(num min, num max, [String? message]) {
    return (num? value) {
      if (value == null) return null;
      
      if (value < min || value > max) {
        return message ?? 'Value must be between $min and $max';
      }
      return null;
    };
  }

  /// Combines multiple validators
  static String? Function(T? value) combine<T>(List<String? Function(T? value)> validators) {
    return (T? value) {
      for (final validator in validators) {
        final result = validator(value);
        if (result != null) return result;
      }
      return null;
    };
  }

  /// Creates a debounced callback
  static VoidCallback debounce(VoidCallback callback, Duration delay) {
    Timer? timer;
    return () {
      timer?.cancel();
      timer = Timer(delay, callback);
    };
  }

  /// Formats a database value for display
  static String formatValue(dynamic value, {String? format}) {
    if (value == null) return '';
    
    if (format != null) {
      switch (format.toLowerCase()) {
        case 'currency':
          return '\$${(value as num).toStringAsFixed(2)}';
        case 'percentage':
          return '${(value as num).toStringAsFixed(1)}%';
        case 'date':
          if (value is String) {
            final date = DateTime.tryParse(value);
            if (date != null) {
              return '${date.day}/${date.month}/${date.year}';
            }
          }
          break;
        case 'datetime':
          if (value is String) {
            final date = DateTime.tryParse(value);
            if (date != null) {
              return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
            }
          }
          break;
        case 'time':
          if (value is String) {
            final date = DateTime.tryParse(value);
            if (date != null) {
              return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
            }
          }
          break;
      }
    }
    
    return value.toString();
  }

  /// Creates a confirmation dialog
  static Future<bool> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: confirmColor != null
                ? TextButton.styleFrom(foregroundColor: confirmColor)
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  /// Shows a loading overlay
  static void showLoadingOverlay(BuildContext context, {String? message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message),
            ],
          ],
        ),
      ),
    );
  }

  /// Hides the loading overlay
  static void hideLoadingOverlay(BuildContext context) {
    Navigator.of(context).pop();
  }

  /// Shows an error snackbar
  static void showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Shows a success snackbar
  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Creates a responsive layout based on screen size
  static Widget responsive({
    required BuildContext context,
    Widget? mobile,
    Widget? tablet,
    Widget? desktop,
    double tabletBreakpoint = 600,
    double desktopBreakpoint = 1200,
  }) {
    final width = MediaQuery.of(context).size.width;
    
    if (width >= desktopBreakpoint && desktop != null) {
      return desktop;
    } else if (width >= tabletBreakpoint && tablet != null) {
      return tablet;
    } else {
      return mobile ?? const SizedBox.shrink();
    }
  }

  /// Creates a grid layout that adapts to screen size
  static Widget adaptiveGrid({
    required List<Widget> children,
    int minColumns = 1,
    int maxColumns = 4,
    double minItemWidth = 200,
    double spacing = 8,
    double runSpacing = 8,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final effectiveColumns = ((availableWidth + spacing) / (minItemWidth + spacing))
            .floor()
            .clamp(minColumns, maxColumns);
        
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children.map((child) {
            final itemWidth = (availableWidth - spacing * (effectiveColumns - 1)) / effectiveColumns;
            return SizedBox(
              width: itemWidth,
              child: child,
            );
          }).toList(),
        );
      },
    );
  }

  /// Creates a loading state widget
  static Widget loadingState({
    String? message,
    Widget? icon,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon ?? const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message),
          ],
        ],
      ),
    );
  }

  /// Creates an empty state widget
  static Widget emptyState({
    required String message,
    Widget? icon,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon ?? const Icon(Icons.inbox, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }

  /// Creates an error state widget
  static Widget errorState({
    required String message,
    VoidCallback? onRetry,
    Widget? icon,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon ?? const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Extension methods for common Flutter operations with declarative_sqlite
extension DataAccessExtensions on DataAccess {
  /// Creates a stream that emits when any table changes
  Stream<void> get globalChangeStream {
    // This would need to be implemented in the core library
    // For now, return an empty stream
    return const Stream.empty();
  }

  /// Creates a stream for a specific record
  Stream<Map<String, dynamic>?> streamRecord(String tableName, dynamic primaryKey) {
    return streamQueryResults(
      tableName,
      where: 'id = ?',
      whereArgs: [primaryKey],
      limit: 1,
    ).map((results) => results.isNotEmpty ? results.first : null);
  }

  /// Creates a stream for SQL query results
  Stream<List<Map<String, dynamic>>> streamSqlResults(String sql, [List<dynamic>? arguments]) {
    // This would need to be implemented in the core library
    // For now, create a periodic stream that executes the query
    return Stream.periodic(const Duration(seconds: 1)).asyncMap((_) async {
      return await database.rawQuery(sql, arguments);
    }).distinct();
  }
}

