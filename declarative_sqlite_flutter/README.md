# Declarative SQLite Flutter

A Flutter package that provides seamless integration of [declarative_sqlite](../declarative_sqlite) with Flutter widgets, forms, and UI patterns.

## Features

- **Reactive ListView Widgets**: Automatically update when database changes
- **LWW Form Integration**: Form widgets with Last-Write-Wins column binding
- **Master-Detail Patterns**: Built-in support for database-driven navigation
- **Input Field Widgets**: Text fields, sliders, dropdowns that sync with database columns
- **Stream-based UI Updates**: Reactive widgets that respond to database changes
- **Helper Utilities**: Validators, formatters, and common UI patterns

## Quick Start

### 1. Add Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  declarative_sqlite_flutter:
    path: ../declarative_sqlite_flutter
  sqflite: ^2.3.4
```

### 2. Initialize Database Service

```dart
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: DatabaseServiceProvider(
        schema: _createSchema(),
        databaseName: 'app.db',
        enableLWW: true,
        child: HomePage(),
      ),
    );
  }

  SchemaBuilder _createSchema() {
    return SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull())
          .text('email', (col) => col.notNull().unique())
          .integer('age')
          .integer('active', (col) => col.withDefaultValue(1)));
  }
}
```

### 3. Use Reactive Widgets

```dart
class UserListPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final service = DatabaseProvider.of(context);
    
    return ReactiveListView.builder(
      dataAccess: service!.dataAccess!,
      tableName: 'users',
      orderBy: 'name ASC',
      itemBuilder: (context, user) {
        return ListTile(
          title: Text(user['name']),
          subtitle: Text(user['email']),
          trailing: Icon(
            user['active'] == 1 ? Icons.check : Icons.close,
            color: user['active'] == 1 ? Colors.green : Colors.red,
          ),
        );
      },
    );
  }
}
```

## Core Widgets

### ReactiveListView

Automatically updates when the underlying database table changes:

```dart
ReactiveListView.builder(
  dataAccess: dataAccess,
  tableName: 'users',
  where: 'active = 1',
  orderBy: 'name ASC',
  itemBuilder: (context, item) => UserCard(user: item),
)
```

### LWW Forms

Forms that automatically sync with Last-Write-Wins columns:

```dart
LWWForm(
  dataAccess: dataAccess,
  tableName: 'users',
  primaryKey: userId,
  autoSave: true,
  child: Column(
    children: [
      LWWTextField(
        columnName: 'name',
        decoration: InputDecoration(labelText: 'Name'),
      ),
      LWWTextField(
        columnName: 'email',
        decoration: InputDecoration(labelText: 'Email'),
        validator: WidgetHelpers.email(),
      ),
      LWWSlider(
        columnName: 'age',
        min: 0,
        max: 120,
        label: 'Age',
      ),
    ],
  ),
)
```

### Master-Detail Views

Built-in support for master-detail patterns:

```dart
SimpleMasterDetailView(
  dataAccess: dataAccess,
  masterTable: 'orders',
  detailTable: 'order_items',
  foreignKeyColumn: 'order_id',
  masterTitle: (order) => 'Order #${order['id']}',
  detailTitle: (item) => item['product_name'],
)
```

### Database Stream Builders

Reactive widgets for custom database queries:

```dart
DatabaseQueryBuilder(
  dataAccess: dataAccess,
  tableName: 'products',
  where: 'category = ?',
  whereArgs: ['electronics'],
  builder: (context, products) {
    return GridView.builder(
      itemCount: products.length,
      itemBuilder: (context, index) => ProductCard(products[index]),
    );
  },
)
```

## Input Widgets

### Text Fields

```dart
LWWTextField(
  columnName: 'name',
  decoration: InputDecoration(labelText: 'Name'),
  validator: WidgetHelpers.required(),
)

LWWTextArea(
  columnName: 'description',
  decoration: InputDecoration(labelText: 'Description'),
  minLines: 3,
)

LWWPasswordField(
  columnName: 'password',
  decoration: InputDecoration(labelText: 'Password'),
  showVisibilityToggle: true,
)
```

### Sliders

```dart
LWWSlider(
  columnName: 'rating',
  min: 0,
  max: 5,
  divisions: 10,
  label: 'Rating',
)

LWWIntSlider(
  columnName: 'quantity',
  min: 0,
  max: 100,
  label: 'Quantity',
)
```

### Dropdowns

```dart
LWWDropdown<String>(
  columnName: 'status',
  items: [
    DropdownMenuItem(value: 'active', child: Text('Active')),
    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
  ],
)

LWWDatabaseDropdown(
  columnName: 'category_id',
  dataAccess: dataAccess,
  optionsTable: 'categories',
  valueColumn: 'id',
  displayColumn: 'name',
)
```

## Reactive Widgets

Pre-built reactive widgets for common patterns:

```dart
// Status cards with live data
ReactiveWidgets.statusCard(
  dataAccess: dataAccess,
  tableName: 'orders',
  title: 'Total Orders',
  valueColumn: 'COUNT',
  icon: Icons.shopping_cart,
)

// Progress indicators
ReactiveWidgets.progressIndicator(
  dataAccess: dataAccess,
  tableName: 'tasks',
  statusColumn: 'status',
  completedValue: 'completed',
)

// Count badges
ReactiveWidgets.countBadge(
  dataAccess: dataAccess,
  tableName: 'notifications',
  where: 'read = 0',
  child: Icon(Icons.notifications),
)

// Live data tables
ReactiveWidgets.dataTable(
  dataAccess: dataAccess,
  tableName: 'users',
  columns: ['name', 'email', 'created_at'],
  columnLabels: {
    'name': 'Name',
    'email': 'Email Address',
    'created_at': 'Created',
  },
)
```

## Utility Functions

### Validators

```dart
TextFormField(
  validator: WidgetHelpers.combine([
    WidgetHelpers.required(),
    WidgetHelpers.email(),
    WidgetHelpers.minLength(3),
  ]),
)
```

### Responsive Layouts

```dart
WidgetHelpers.responsive(
  context: context,
  mobile: MobileLayout(),
  tablet: TabletLayout(),
  desktop: DesktopLayout(),
)

WidgetHelpers.adaptiveGrid(
  children: widgets,
  minColumns: 1,
  maxColumns: 4,
  minItemWidth: 200,
)
```

### Notifications

```dart
WidgetHelpers.showSuccessSnackBar(context, 'Data saved!');
WidgetHelpers.showErrorSnackBar(context, 'Save failed');

final confirmed = await WidgetHelpers.showConfirmDialog(
  context: context,
  title: 'Delete Item',
  message: 'Are you sure you want to delete this item?',
);
```

## Examples

See the [example](example/) directory for a complete demo application showing:

- User management with reactive lists
- Form-based data entry with validation
- Master-detail navigation patterns
- Live dashboard with status cards
- Responsive layouts

## Integration with Core Library

This package extends [declarative_sqlite](../declarative_sqlite) with Flutter-specific features:

- Uses the same schema definitions and data access patterns
- Leverages LWW (Last-Write-Wins) conflict resolution
- Integrates with reactive streams for real-time UI updates
- Provides Flutter-specific error handling and loading states

## Architecture

- **Reactive Patterns**: Widgets automatically rebuild when database data changes
- **State Management**: Built-in state management for forms and data synchronization
- **Performance**: Efficient stream-based updates with debouncing and batching
- **Modularity**: Each widget can be used independently or combined together

## License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.