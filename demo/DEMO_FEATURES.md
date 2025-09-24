# Declarative SQLite Flutter Demo

This demo application showcases the key features of the declarative_sqlite packages and demonstrates reactive data updates.

## Features Demonstrated

### 1. Schema Definition
- **Users Table**: Stores user information (id, name, email, age, created_at)
- **Posts Table**: Stores posts with references to users (id, user_id, title, content, created_at, user_name)
- **Database Provider**: Manages the database lifecycle and makes it available throughout the widget tree

### 2. Reactive QueryListView
- **Automatic Updates**: The list automatically updates when data changes in the database
- **Real-time Filtering**: Switch between different age filters (All Users, Young ≤25, Older >25)
- **View Switching**: Toggle between Users list and Posts list

### 3. Interactive Controls

#### Data Manipulation:
- **Add User**: Creates random users with different ages and details
- **Add Post**: Creates posts linked to existing users
- **Edit User**: Tap on a user to edit their name and age

#### Demonstration Buttons:
- **Update Random User Age**: Updates a user within the current filter - you'll see the list update immediately
- **Update User (Outside Filter)**: Updates a user to move them outside the current filter - you'll see them disappear from the list

### 4. Filter Testing
The app demonstrates that QueryListView correctly handles data changes:

1. **Within Result Set**: When you update a user's age but they still match the current filter, the list updates in place
2. **Outside Result Set**: When you update a user's age to move them outside the current filter, they automatically disappear from the list
3. **Real-time Updates**: All changes are reflected immediately without manual refresh

## How to Test

1. **Start with some data**: Tap "Add User" several times to create users with different ages
2. **Test filtering**: Use the age filter buttons to see different subsets of users
3. **Test reactive updates**:
   - Select "Young (≤25)" filter
   - Tap "Update Random User Age" - see updates within the result set
   - Tap "Update User (Outside Filter)" - see users disappear when they no longer match
4. **Add posts**: Create some posts and switch to the Posts view to see them
5. **Edit users**: Tap on any user to edit their details and see immediate updates

## Technical Highlights

- **DatabaseProvider**: Manages database initialization and provides access throughout the widget tree
- **QueryListView**: Reactive ListView that automatically updates when query results change
- **WhereClause API**: Type-safe query building with `col('age').lte(25)` syntax
- **Automatic Schema Migration**: Schema changes are automatically applied to the database
- **Real-time Streaming**: Uses streaming queries for live data updates

This demo shows how declarative_sqlite makes it easy to build reactive, data-driven Flutter applications with minimal boilerplate code.