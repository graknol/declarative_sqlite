import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// A provider widget that makes DataAccess available to all descendant widgets.
/// 
/// This widget uses the InheritedWidget pattern to provide a DataAccess instance
/// to the entire widget tree, allowing other reactive widgets to access the
/// database without requiring an explicit dataAccess parameter.
/// 
/// ## Usage
/// 
/// Place this widget at the root of your app or at the top of the widget tree
/// where you want database access to be available:
/// 
/// ```dart
/// DataAccessProvider(
///   dataAccess: dataAccess,
///   child: MaterialApp(
///     home: MyHomePage(),
///   ),
/// )
/// ```
/// 
/// Then, any descendant widgets can omit the dataAccess parameter and the
/// widgets will automatically use the provided instance:
/// 
/// ```dart
/// // No need to pass dataAccess - it will be retrieved from the provider
/// ReactiveListView.builder(
///   tableName: 'users',
///   itemBuilder: (context, user) => UserCard(user: user),
/// )
/// ```
class DataAccessProvider extends InheritedWidget {
  /// The DataAccess instance to provide to descendant widgets
  final DataAccess dataAccess;

  const DataAccessProvider({
    super.key,
    required this.dataAccess,
    required super.child,
  });

  /// Retrieve the DataAccess instance from the widget tree.
  /// 
  /// This method looks for the nearest DataAccessProvider ancestor and returns
  /// its DataAccess instance. If no provider is found, returns null.
  /// 
  /// Use [maybeOf] when you want to handle the case where no provider exists,
  /// or use [of] when you want an exception to be thrown if no provider is found.
  static DataAccess? maybeOf(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<DataAccessProvider>();
    return provider?.dataAccess;
  }

  /// Retrieve the DataAccess instance from the widget tree.
  /// 
  /// This method looks for the nearest DataAccessProvider ancestor and returns
  /// its DataAccess instance. If no provider is found, throws a FlutterError
  /// with helpful debugging information.
  /// 
  /// This is the preferred method when you expect a DataAccessProvider to always
  /// be present in the widget tree.
  static DataAccess of(BuildContext context) {
    final dataAccess = maybeOf(context);
    if (dataAccess == null) {
      throw FlutterError.fromParts([
        ErrorSummary('No DataAccessProvider found in widget tree.'),
        ErrorDescription(
          'The widget that called DataAccessProvider.of() does not have a '
          'DataAccessProvider ancestor.',
        ),
        ErrorHint(
          'To fix this, wrap your app or a parent widget with DataAccessProvider:\n\n'
          'DataAccessProvider(\n'
          '  dataAccess: dataAccess,\n'
          '  child: MyWidget(),\n'
          ')',
        ),
        context.describeElement('The specific widget that could not find a DataAccessProvider was'),
      ]);
    }
    return dataAccess;
  }

  @override
  bool updateShouldNotify(DataAccessProvider oldWidget) {
    return dataAccess != oldWidget.dataAccess;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<DataAccess>('dataAccess', dataAccess));
  }
}

/// Extension on BuildContext to provide convenient access to DataAccess.
/// 
/// This extension adds convenience methods to BuildContext for accessing
/// the DataAccess instance from a DataAccessProvider.
extension DataAccessContext on BuildContext {
  /// Retrieve the DataAccess instance from the widget tree.
  /// 
  /// Equivalent to calling `DataAccessProvider.of(context)`.
  /// Throws a FlutterError if no DataAccessProvider is found.
  DataAccess get dataAccess => DataAccessProvider.of(this);

  /// Retrieve the DataAccess instance from the widget tree, or null if not found.
  /// 
  /// Equivalent to calling `DataAccessProvider.maybeOf(context)`.
  /// Returns null if no DataAccessProvider is found.
  DataAccess? get dataAccessOrNull => DataAccessProvider.maybeOf(this);
}

/// Helper function to get DataAccess instance with fallback logic.
/// 
/// This utility function implements the common pattern used by reactive widgets:
/// 1. Use the provided dataAccess if not null
/// 2. Fall back to the DataAccessProvider if available
/// 3. Throw an error with helpful message if neither is available
/// 
/// This is used internally by reactive widgets to support both explicit
/// dataAccess parameters and provider-based access.
DataAccess getDataAccess(BuildContext context, DataAccess? explicitDataAccess) {
  if (explicitDataAccess != null) {
    return explicitDataAccess;
  }
  
  final providerDataAccess = DataAccessProvider.maybeOf(context);
  if (providerDataAccess != null) {
    return providerDataAccess;
  }
  
  throw FlutterError.fromParts([
    ErrorSummary('No DataAccess instance available.'),
    ErrorDescription(
      'The widget requires a DataAccess instance but none was provided '
      'either explicitly through the dataAccess parameter or through a '
      'DataAccessProvider ancestor.',
    ),
    ErrorHint(
      'To fix this, either:\n\n'
      '1. Provide dataAccess explicitly:\n'
      '   MyWidget(dataAccess: dataAccess, ...)\n\n'
      '2. Or wrap your app with DataAccessProvider:\n'
      '   DataAccessProvider(\n'
      '     dataAccess: dataAccess,\n'
      '     child: MyApp(),\n'
      '   )',
    ),
    context.describeElement('The specific widget that could not find DataAccess was'),
  ]);
}