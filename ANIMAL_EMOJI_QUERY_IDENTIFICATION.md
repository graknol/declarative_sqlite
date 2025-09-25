# Animal Emoji Query Identification

## Overview
To improve log readability when working with multiple streaming queries, all query-related log messages now include unique animal emojis based on the query ID. This makes it much easier to track different queries in log output.

## How It Works

### Emoji Generation
- Each query ID is hashed using Dart's built-in `hashCode`
- The hash is used with modulo operation to select from 100 different animal emojis
- Same query ID will always get the same emoji (consistent across app runs)
- Different query IDs will get different emojis (distributed evenly)

### Implementation
The functionality is implemented in `query_emoji_utils.dart` and used across:
- `StreamingQuery` - Core query lifecycle logs
- `QueryStreamManager` - Query registration and refresh logs  
- `QueryListView` - Flutter widget query creation logs

### Example Log Output

#### Before (Hard to Track)
```
QueryStreamManager.unregister: Unregistering query id="query_list_view_1695734521234"
QueryStreamManager._processTableChange: Refreshing query id="query_list_view_1695734521234" for table="users"
StreamingQuery.dispose: Disposing query id="query_list_view_1695734521234"
QueryStreamManager.unregister: Unregistering query id="user_search_1695734521567"  
QueryStreamManager._processTableChange: Refreshing query id="user_search_1695734521567" for table="users"
```

#### After (Easy to Track)
```
QueryStreamManager.unregister: 🐶 Unregistering query id="query_list_view_1695734521234"
QueryStreamManager._processTableChange: 🐶 Refreshing query id="query_list_view_1695734521234" for table="users"
StreamingQuery.dispose: 🐶 Disposing query id="query_list_view_1695734521234"
QueryStreamManager.unregister: 🦊 Unregistering query id="user_search_1695734521567"
QueryStreamManager._processTableChange: 🦊 Refreshing query id="user_search_1695734521567" for table="users"
```

## Available Emojis
The system uses 100 different animal emojis including:
- Common pets: 🐶 🐱 🐭 🐹 🐰
- Wild animals: 🦊 🐻 🐼 🐨 🐯 🦁
- Birds: 🐧 🦅 🦉 🐔 🦆
- Sea creatures: 🐟 🐬 🐳 🦈 🐙
- Insects: 🐝 🦋 🐞 🕷️
- And many more...

## Benefits

### Development Experience
- **Quick Visual Identification**: Instantly spot which logs belong to which query
- **Reduced Cognitive Load**: No need to memorize long timestamp-based IDs
- **Better Debugging**: Easier to follow query lifecycle through logs
- **Improved Team Communication**: "The 🐶 query is having issues" vs "The query_list_view_1695734521234 query is having issues"

### Production Monitoring
- Faster incident response when tracking multiple concurrent queries
- Clearer log analysis when multiple queries are interacting
- Better performance monitoring per query type

## Technical Details

### Hash Distribution
The emoji selection uses query ID hash modulo 100, providing:
- Even distribution across available emojis
- Deterministic selection (same ID = same emoji)
- Low collision probability for typical query counts

### Performance Impact
- Minimal: Only computes hash when logging (which is already conditional)
- No runtime overhead when logging is disabled
- Emoji lookup is O(1) array access

### Unicode Compatibility
All selected emojis are widely supported across:
- Modern terminal applications
- IDE console outputs
- Log aggregation tools
- Mobile debugging tools

## Usage Examples

### Debugging Multiple Queries
```dart
// When you have multiple QueryListViews
QueryListView<User>(query: (q) => q.from('users').where('active = ?', [true])) // Gets 🐶
QueryListView<Post>(query: (q) => q.from('posts').orderBy('created_at DESC')) // Gets 🦊  
QueryListView<Comment>(query: (q) => q.from('comments').join('users', ...)) // Gets 🐱
```

Each query gets its own emoji, making logs easy to follow:
```
QueryListView: 🐶 Creating new streaming query with id="query_list_view_1695734521234"
QueryListView: 🦊 Creating new streaming query with id="query_list_view_1695734521567"  
QueryListView: 🐱 Creating new streaming query with id="query_list_view_1695734521890"
QueryStreamManager._processTableChange: 🐶 Refreshing query for table="users"
QueryStreamManager._processTableChange: 🦊 Refreshing query for table="posts"
```

This enhancement maintains all existing functionality while significantly improving the developer experience when working with multiple streaming queries.