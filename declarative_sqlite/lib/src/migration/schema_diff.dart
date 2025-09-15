import 'package:declarative_sqlite/src/schema/column.dart';
import 'package:declarative_sqlite/src/schema/key.dart';
import 'package:declarative_sqlite/src/schema/reference.dart';
import 'package:declarative_sqlite/src/schema/live_schema.dart';
import 'package:declarative_sqlite/src/schema/table.dart';
import 'package:declarative_sqlite/src/schema/view.dart';

abstract class SchemaChange {}

// Table changes
class CreateTable extends SchemaChange {
  final Table table;
  CreateTable(this.table);
}

class DropTable extends SchemaChange {
  final LiveTable table;
  DropTable(this.table);
}

class AlterTable extends SchemaChange {
  final LiveTable liveTable;
  final Table targetTable;
  final List<ColumnChange> columnChanges;
  final List<KeyChange> keyChanges;
  final List<ReferenceChange> referenceChanges;
  AlterTable(this.liveTable, this.targetTable, this.columnChanges,
      this.keyChanges, this.referenceChanges);
}

// Column changes
abstract class ColumnChange {}

class AddColumn extends ColumnChange {
  final Column column;
  AddColumn(this.column);
}

class DropColumn extends ColumnChange {
  final LiveColumn column;
  DropColumn(this.column);
}

class AlterColumn extends ColumnChange {
  final LiveColumn liveColumn;
  final Column targetColumn;
  AlterColumn(this.liveColumn, this.targetColumn);
}

// Key changes
abstract class KeyChange {}

class AddKey extends KeyChange {
  final Key key;
  AddKey(this.key);
}

class DropKey extends KeyChange {
  final LiveKey key;
  DropKey(this.key);
}

// Reference changes
abstract class ReferenceChange {}

class AddReference extends ReferenceChange {
  final Reference reference;
  AddReference(this.reference);
}

class DropReference extends ReferenceChange {
  final Reference reference;
  DropReference(this.reference);
}

// View changes
class CreateView extends SchemaChange {
  final View view;
  CreateView(this.view);
}

class DropView extends SchemaChange {
  final LiveView view;
  DropView(this.view);
}

class AlterView extends SchemaChange {
  final LiveView liveView;
  final View targetView;
  AlterView(this.liveView, this.targetView);
}
