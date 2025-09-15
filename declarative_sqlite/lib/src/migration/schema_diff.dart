import 'package:declarative_sqlite/src/schema/column.dart';
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
  // TODO: Add key/index changes
  AlterTable(this.liveTable, this.targetTable, this.columnChanges);
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
