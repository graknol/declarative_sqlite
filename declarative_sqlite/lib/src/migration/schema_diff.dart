import 'package:declarative_sqlite/src/schema/column.dart';
import 'package:declarative_sqlite/src/schema/key.dart';
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
  AlterTable(
      this.liveTable, this.targetTable, this.columnChanges, this.keyChanges);
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

// View changes
abstract class ViewChange extends SchemaChange {}

class CreateView extends ViewChange {
  final View view;
  CreateView(this.view);
}

class AlterView extends ViewChange {
  final LiveView liveView;
  final View targetView;
  AlterView(this.liveView, this.targetView);
}

class DropView extends ViewChange {
  final LiveView view;
  DropView(this.view);
}