import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:flutter/widgets.dart';

class DatabaseProvider extends StatelessWidget {
  final void Function(SchemaBuilder builder) schema;
  final String databaseName;
  final Widget child;

  const DatabaseProvider({
    super.key,
    required this.schema,
    required this.databaseName,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Database initialization logic will be added later
    return child;
  }
}
