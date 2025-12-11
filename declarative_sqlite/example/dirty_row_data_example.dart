/// Example demonstrating the dirty row data field functionality
/// 
/// This example shows how the DirtyRow.data field now captures the actual
/// values that were changed during insert/update operations, making it
/// possible for sync operations to know exactly what fields were modified.

import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() async {
  print('=== Dirty Row Data Field Example ===\n');

  // Create a simple in-memory database
  final schemaBuilder = SchemaBuilder();
  schemaBuilder.table('c_work_order', (table) {
    table.guid('id');
    table.text('rowstate');
    table.text('description');
    table.integer('priority');
    table.key(['id']).primary();
  });

  // Note: In a real application, you would use proper file paths
  // and database factories. This is just for demonstration.
  print('✅ Schema defined with c_work_order table\n');

  print('Example 1: Insert Operation');
  print('----------------------------');
  print('When inserting a new work order:');
  print('  await db.insert(\'c_work_order\', {');
  print('    \'rowstate\': \'WorkStarted\',');
  print('    \'description\': \'Fix the bug\',');
  print('    \'priority\': 1,');
  print('  });\n');
  print('The dirty row will contain:');
  print('  {');
  print('    tableName: \'c_work_order\',');
  print('    rowId: \'<system_id>\',');
  print('    data: {');
  print('      rowstate: \'WorkStarted\',');
  print('      description: \'Fix the bug\',');
  print('      priority: 1,');
  print('    },');
  print('    isFullRow: true,');
  print('  }\n');

  print('Example 2: Update Operation');
  print('----------------------------');
  print('When updating specific fields:');
  print('  await db.update(');
  print('    \'c_work_order\',');
  print('    {');
  print('      \'rowstate\': \'WorkCompleted\',');
  print('      \'priority\': 5,');
  print('    },');
  print('    where: \'system_id = ?\',');
  print('    whereArgs: [\'some-id\'],');
  print('  );\n');
  print('The dirty row will contain:');
  print('  {');
  print('    tableName: \'c_work_order\',');
  print('    rowId: \'some-id\',');
  print('    data: {');
  print('      rowstate: \'WorkCompleted\',');
  print('      priority: 5,');
  print('    },');
  print('    isFullRow: true,');
  print('  }\n');

  print('Example 3: Using Dirty Rows in Sync');
  print('------------------------------------');
  print('In your sync operation:');
  print('  final dirtyRows = await database.getDirtyRows();\n');
  print('  for (final dirtyRow in dirtyRows) {');
  print('    // ✅ Now you can access the changed data!');
  print('    if (dirtyRow.data != null) {');
  print('      for (final entry in dirtyRow.data!.entries) {');
  print('        print(\'Field \${entry.key} = \${entry.value}\');');
  print('      }');
  print('      ');
  print('      // Push these specific changes to your API');
  print('      await apiClient.updateRow(');
  print('        table: dirtyRow.tableName,');
  print('        id: dirtyRow.rowId,');
  print('        changes: dirtyRow.data!,');
  print('      );');
  print('    }');
  print('  }\n');

  print('Benefits');
  print('--------');
  print('✅ Sync operations know exactly which fields changed');
  print('✅ Reduces bandwidth by only sending changed fields');
  print('✅ Improves API efficiency and reduces conflicts');
  print('✅ Better debugging and logging capabilities');
  print('\n=== Example Complete ===');
}
