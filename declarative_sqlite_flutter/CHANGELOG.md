## 1.3.0

### Updates
- Updated to use declarative_sqlite ^1.3.0
- Enhanced compatibility with new constraint violation handling features
- Improved data safety when working with server synchronization and constraint violations in Flutter widgets
- Fixed the `recreateDatabase` parameter not getting passed from the `DatabaseProvider` widget to the `DeclarativeDatabase.open(...)` call

## 1.2.0

### Updates
- Updated to use declarative_sqlite ^1.2.0
- Enhanced compatibility with unified save() method
- Improved developer experience with simplified CRUD operations in Flutter widgets

## 1.1.0

### Updates
- Updated to use declarative_sqlite ^1.1.0
- Enhanced compatibility with non-LWW column protection features
- Improved data safety when working with server-origin data in Flutter widgets

## 1.0.2

### Updates
- Updated to use declarative_sqlite ^1.0.2
- Aligned with foreign key removal changes

## 1.0.1

### Updates
- Updated to use declarative_sqlite ^1.0.1
- Added missing dependencies for proper pub.dev publication
- Updated documentation examples

## 1.0.0

### Features
- `DatabaseProvider` widget for managing database lifecycle in Flutter
- `QueryListView` reactive widget for displaying database query results
- Seamless integration with DeclarativeSQLite streaming queries
- Automatic UI updates when database changes
- Type-safe database record handling with `DbRecord`

### Widgets
- **DatabaseProvider**: Provides database context to widget tree
- **QueryListView**: Reactive ListView that updates with database changes

### Documentation
- Complete Flutter integration guide
- Widget usage examples
- Best practices for reactive UIs