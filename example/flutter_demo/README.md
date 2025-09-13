# Shop Floor Demo - Declarative SQLite

A comprehensive Flutter demonstration app showcasing offline-first collaborative data synchronization using the `declarative_sqlite` library. This demo implements a typical shop-floor/order management system with features commonly needed in industrial and collaborative applications.

## 🎯 Demo Scenarios

This application demonstrates the following key offline-first collaborative scenarios:

### 1. **Order List with Reactive Filtering**
- **Real-time Updates**: Order list automatically updates when data changes
- **Advanced Filtering**: Filter by status (pending, in-progress, completed) and priority (high, medium, low)
- **Search Functionality**: Full-text search across order numbers, customer names, and descriptions
- **Query Builder Integration**: Leverages declarative_sqlite's query builder for efficient database operations

### 2. **Order Detail Management**
- **Comprehensive Views**: Detailed order information with tabbed interface
- **Order Lines**: Individual line items with quantity, pricing, and status tracking
- **Status Updates**: Real-time order status changes with LWW conflict resolution
- **Data Validation**: Automatic validation of calculated totals and data integrity

### 3. **Collaborative Notes with Offline-First GUIDs**
- **Client-First Creation**: Notes created with GUIDs to avoid ID collisions
- **Multi-Device Support**: Notes track which device created them
- **Sync Status Tracking**: Visual indicators for synced vs. pending notes
- **Note Types**: Categorized notes (general, priority, quality, issue) with visual distinction
- **Conflict Resolution**: Demonstrates LWW (Last-Write-Wins) conflict resolution

### 4. **Offline-First Data Architecture**
- **GUID-Based Primary Keys**: All entities use GUIDs for offline-first creation
- **Sync Operation Tracking**: Built-in tracking for operations that need server sync
- **LWW Timestamps**: Last-Write-Wins conflict resolution for collaborative editing
- **Device Attribution**: Track which device/user made changes

## 🏗️ Architecture Highlights

### Database Schema
The app uses a comprehensive schema designed for offline-first operations:

```dart
// Orders with LWW conflict resolution
.table('orders', (table) => table
    .text('id', (col) => col.primaryKey()) // UUID for offline-first
    .text('order_number', (col) => col.notNull().unique())
    .text('customer_name', (col) => col.notNull())
    .text('status', (col) => col.notNull().withDefaultValue('pending'))
    .real('total_amount', (col) => col.withDefaultValue(0.0))
    .text('priority', (col) => col.withDefaultValue('medium'))
    // LWW columns for conflict resolution
    .text('status_lww_timestamp')
    .text('total_amount_lww_timestamp')
    .text('priority_lww_timestamp'))

// Notes with GUID support and sync tracking
.table('notes', (table) => table
    .text('id', (col) => col.primaryKey()) // UUID for offline-first
    .text('order_id', (col) => col.notNull())
    .text('content', (col) => col.notNull())
    .text('author', (col) => col.notNull())
    .text('note_type', (col) => col.withDefaultValue('general'))
    .integer('is_synced', (col) => col.withDefaultValue(0)) // Offline tracking
    .text('created_on_device')) // Device attribution
```

### Global Database Service
Centralized database management with reactive streams:

```dart
class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  
  // Reactive streams for UI updates
  Stream<List<Order>> get orderUpdates;
  Stream<List<OrderLine>> get orderLineUpdates;
  Stream<List<Note>> get noteUpdates;
  
  // LWW conflict resolution
  Future<void> updateOrderStatus(String orderId, String newStatus);
  
  // Offline-first note creation with GUIDs
  Future<String> addNote(String orderId, String content, String author);
}
```

### Widget Architecture
Clean separation of concerns with reusable components:

- **`OrderListPage`**: Main list with filtering and search
- **`OrderDetailPage`**: Detailed view with tabbed interface
- **`OrderCard`**: Reusable order display component
- **`NoteCard`**: Collaborative note display with sync indicators
- **`AddNoteDialog`**: Offline-first note creation

## 🚀 Key Features Demonstrated

### Reactive Data Access
- **StreamBuilder Integration**: UI automatically updates when data changes
- **Efficient Querying**: Query builder patterns for complex filtering
- **Real-time Sync**: Changes propagate immediately across the application

### Offline-First Design
- **GUID Generation**: Unique IDs generated client-side to prevent conflicts
- **Sync Tracking**: Visual indicators for data sync status
- **Device Attribution**: Track which device/user made changes
- **Conflict Resolution**: LWW timestamps for handling concurrent edits

### Collaborative Features
- **Multi-User Notes**: Multiple authors can add notes to orders
- **Type-Safe Operations**: Leverages declarative_sqlite's type safety
- **Data Validation**: Automatic validation of business rules and calculations
- **Error Handling**: Comprehensive error handling with user feedback

### Professional UI/UX
- **Material Design 3**: Modern Flutter UI with consistent theming
- **Responsive Layout**: Adapts to different screen sizes
- **Status Indicators**: Clear visual feedback for data states
- **Performance**: Efficient rendering with proper state management

## 🛠️ Technical Implementation

### Dependencies
- **Flutter**: UI framework
- **declarative_sqlite**: Schema management and data access
- **sqflite**: SQLite database engine
- **uuid**: GUID generation for offline-first IDs

### Schema Migration
Automatic schema creation and migration using declarative_sqlite:

```dart
final migrator = SchemaMigrator();
await migrator.migrate(database, schema);
```

### Data Access Layer
Type-safe CRUD operations with conflict resolution:

```dart
final dataAccess = await DataAccess.create(
  database: database,
  schema: schema,
  enableLWW: true, // Enable Last-Write-Wins conflict resolution
);
```

## 🎮 How to Use the Demo

1. **Browse Orders**: View the main order list with real-time updates
2. **Filter & Search**: Use the filter bar to find specific orders
3. **View Details**: Tap on any order to see detailed information
4. **Manage Status**: Update order status and see LWW conflict resolution
5. **Add Notes**: Create collaborative notes with different types
6. **Observe Sync**: Watch sync indicators show offline vs. synced state
7. **Test Conflicts**: Create simultaneous updates to see conflict resolution

## 🔬 Learning Outcomes

This demo showcases how to build production-ready offline-first applications with:

- **Declarative Schema Management**: Define database structure with code
- **Automatic Migration**: Handle schema changes seamlessly
- **Conflict Resolution**: Manage concurrent edits in collaborative environments
- **Type Safety**: Leverage Dart's type system for database operations
- **Reactive UI**: Build responsive interfaces that update automatically
- **Professional Architecture**: Organize code for maintainability and scalability

## 📚 Further Exploration

The demo provides a solid foundation for building more complex offline-first applications. Key areas for extension include:

- **Server Synchronization**: Add actual server sync implementation
- **User Authentication**: Integrate user management and permissions
- **Advanced Queries**: Explore more complex query patterns
- **Real-time Collaboration**: Add WebSocket support for live updates
- **Data Encryption**: Implement secure data storage
- **Batch Operations**: Handle large dataset synchronization

This demo proves that declarative_sqlite provides a powerful foundation for building sophisticated offline-first collaborative applications with clean, maintainable code.