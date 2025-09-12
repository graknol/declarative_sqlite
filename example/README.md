# 🏭 Shop Floor & Advanced Query Demo Applications

This directory contains comprehensive demonstration applications showcasing the full power of `declarative_sqlite` for building offline-first collaborative data sync applications.

## 🚀 Demo Applications

### 1. Shop Floor Console Demo (`shop_floor_console_demo.dart`)

A complete demonstration of offline-first collaborative data synchronization for a shop floor/order management system.

**Run the demo:**
```bash
dart run example/shop_floor_console_demo.dart
```

**Key Features Demonstrated:**
- ✅ **Order Management** with reactive filtering and search
- ✅ **Collaborative Notes** with GUID-based offline-first creation
- ✅ **Conflict Resolution** using Last-Write-Wins timestamps
- ✅ **Offline-First Workflow** with sync operation tracking
- ✅ **GUID Primary Keys** for collision-free offline data creation

### 2. Advanced Query Builder Demo (`advanced_query_builder_demo.dart`)

A sophisticated demonstration of complex database query patterns using declarative_sqlite's query capabilities.

**Run the demo:**
```bash
dart run example/advanced_query_builder_demo.dart
```

**Key Features Demonstrated:**
- ✅ **Basic & Advanced Filtering** with complex WHERE conditions
- ✅ **Aggregation Queries** with COUNT, SUM, AVG, MIN, MAX
- ✅ **Join Operations** including INNER JOIN, LEFT JOIN, three-way joins
- ✅ **Subquery Patterns** with correlated subqueries and EXISTS clauses
- ✅ **View-Style Queries** with CTEs and analytical functions

### 3. Flutter Demo App (`flutter_demo/`)

A complete Flutter application demonstrating professional UI patterns with offline-first data sync.

**Features:**
- 📱 **Material Design 3** UI with reactive updates
- 🔄 **Real-time Data Streams** using StreamBuilder
- 🎯 **Advanced Filtering** with status, priority, and search
- 📝 **Collaborative Notes** with offline creation and sync tracking
- 🏗️ **Clean Architecture** with separated concerns

## 🎯 Scenarios Demonstrated

### Offline-First Collaborative Data Sync

All demos showcase production-ready patterns for building offline-first applications:

1. **Client-First Data Creation**
   - GUIDs generated client-side to prevent ID collisions
   - Data created without server connectivity
   - Sync operations tracked for later server upload

2. **Conflict Resolution**
   - Last-Write-Wins (LWW) timestamps for concurrent edits
   - Conflict detection and resolution strategies
   - Multi-device collaboration scenarios

3. **Reactive Data Access**
   - Stream-based UI updates with real-time synchronization
   - Query builder integration for complex filtering
   - Type-safe database operations

4. **Professional Architecture**
   - Declarative schema management with automatic migration
   - Centralized database service with global access
   - Clean separation of concerns and reusable components

## 📊 Database Schema Examples

### Shop Floor Schema
```dart
SchemaBuilder()
  // Orders with GUID primary keys
  .table('orders', (table) => table
      .text('id', (col) => col.primaryKey()) // UUID for offline-first
      .text('order_number', (col) => col.notNull().unique())
      .text('customer_name', (col) => col.notNull())
      .text('status', (col) => col.notNull().withDefaultValue('pending'))
      .real('total_amount', (col) => col.withDefaultValue(0.0))
      .text('priority', (col) => col.withDefaultValue('medium'))
      .index('idx_order_status', ['status']))
  
  // Notes with collaborative editing support
  .table('notes', (table) => table
      .text('id', (col) => col.primaryKey()) // UUID for offline-first
      .text('order_id', (col) => col.notNull())
      .text('content', (col) => col.notNull())
      .text('author', (col) => col.notNull())
      .integer('is_synced', (col) => col.withDefaultValue(0)) // Sync tracking
      .text('created_on_device')) // Device attribution
```

### Advanced Query Examples
```dart
// Complex aggregation with joins
final revenueByRegion = await database.rawQuery('''
  SELECT 
    c.region,
    COUNT(o.id) as order_count,
    SUM(o.total_amount) as total_revenue,
    AVG(o.total_amount) as avg_order_value
  FROM customers c
  JOIN orders o ON c.id = o.customer_id
  WHERE o.status = 'completed'
  GROUP BY c.region
  ORDER BY total_revenue DESC
''');

// Subquery patterns
final topCustomers = await database.rawQuery('''
  SELECT company_name, industry, region
  FROM customers
  WHERE id IN (
    SELECT customer_id 
    FROM orders 
    WHERE total_amount > (
      SELECT AVG(total_amount) FROM orders WHERE status = 'completed'
    )
  )
''');
```

## 🛠️ Technical Highlights

### Declarative Schema Management
- **Type-Safe Schema Definition**: Define database structure with Dart code
- **Automatic Migration**: Handle schema changes seamlessly
- **Index Management**: Optimize query performance with declarative indexes
- **Constraint Support**: Primary keys, unique constraints, and NOT NULL validation

### Advanced Data Access
- **Query Builder Integration**: Complex filtering with type safety
- **Stream-Based Updates**: Reactive UI patterns with automatic data refresh
- **Bulk Operations**: Efficient handling of large datasets
- **Error Handling**: Comprehensive error management with user feedback

### Offline-First Architecture
- **GUID Generation**: Collision-free client-side ID creation
- **Sync Operation Tracking**: Monitor operations requiring server sync
- **Conflict Resolution**: LWW timestamps for collaborative editing
- **Device Attribution**: Track which device/user made changes

### Professional UI Patterns (Flutter Demo)
- **Material Design 3**: Modern Flutter UI with consistent theming
- **Reactive Architecture**: StreamBuilder integration for real-time updates
- **Component Separation**: Reusable widgets with clean interfaces
- **State Management**: Proper state handling with global database service

## 🎮 How to Use the Demos

### Quick Start
1. **Run the Console Demo**: See immediate results in your terminal
   ```bash
   dart run example/shop_floor_console_demo.dart
   ```

2. **Explore Advanced Queries**: Learn complex SQL patterns
   ```bash
   dart run example/advanced_query_builder_demo.dart
   ```

3. **Study the Flutter App**: Examine professional UI implementation
   ```bash
   cd example/flutter_demo
   # Examine the code structure and patterns
   ```

### Learning Path
1. **Start with Console Demo**: Understand core concepts and data flow
2. **Explore Query Builder**: Learn advanced database query patterns
3. **Study Flutter Implementation**: See how to build production UI
4. **Examine Schema Design**: Understand offline-first database patterns

## 📚 Key Learning Outcomes

### Database Design
- Design schemas for offline-first collaborative applications
- Use GUIDs effectively for distributed data creation
- Implement conflict resolution strategies
- Create efficient indexes for query performance

### Application Architecture
- Structure applications for offline-first scenarios
- Implement reactive data access patterns
- Design clean separation of concerns
- Handle complex query requirements

### User Experience
- Build responsive UIs that update automatically
- Provide clear feedback for sync status
- Handle error conditions gracefully
- Support collaborative editing workflows

## 🔬 Production Readiness

These demos showcase production-ready patterns suitable for:

- **Industrial Applications**: Shop floor management, inventory tracking
- **Collaborative Tools**: Multi-user editing, real-time updates
- **Mobile Applications**: Offline-first mobile apps with sync
- **Enterprise Software**: Complex data relationships and reporting
- **IoT Systems**: Device data collection and synchronization

The patterns demonstrated here have been designed to scale from prototype to production with minimal changes, providing a solid foundation for building sophisticated offline-first applications.

## 🚀 Next Steps

After exploring these demos, consider:

1. **Integrate Server Sync**: Add REST API integration for actual server synchronization
2. **Add User Authentication**: Implement user management and permissions
3. **Extend Schema**: Add more complex relationships and business logic
4. **Performance Optimization**: Implement advanced caching and indexing strategies
5. **Testing Strategy**: Add comprehensive testing for offline scenarios

These demos provide the foundation for building production-grade offline-first collaborative applications with declarative_sqlite.