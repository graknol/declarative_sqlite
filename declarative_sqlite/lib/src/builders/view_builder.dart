import 'package:declarative_sqlite/src/schema/view.dart';

class ViewBuilder {
  final String name;
  final StringBuffer _definition = StringBuffer();

  ViewBuilder(this.name);

  ViewBuilder select(String expression, [String? alias]) {
    if (_definition.isEmpty) {
      _definition.write('SELECT ');
    } else {
      _definition.write(', ');
    }
    _definition.write(expression);
    if (alias != null) {
      _definition.write(' AS $alias');
    }
    return this;
  }

  ViewBuilder selectSubQuery(
      void Function(dynamic sub) callback, String alias) {
    // This is a simplified version. A real implementation would need a subquery builder.
    _definition.write(', (SELECT ...) AS $alias');
    return this;
  }

  ViewBuilder from(String table, [String? alias]) {
    _definition.write(' FROM $table');
    if (alias != null) {
      _definition.write(' AS $alias');
    }
    return this;
  }

  ViewBuilder where(dynamic condition) {
    // This is a simplified version. A real implementation would need a condition builder.
    _definition.write(' WHERE ...');
    return this;
  }

  View build() {
    return View(name: name, definition: _definition.toString());
  }
}
