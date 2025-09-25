---
sidebar_position: 2
---

# Query Builder

The query builder provides a fluent, type-safe API for constructing SQL queries. It helps prevent syntax errors and makes your data access logic more readable and maintainable than raw SQL strings.

You can access the query builder in two ways:
1.  By passing a callback to `database.queryWithBuilder()`.
2.  By creating a `QueryBuilder` instance directly to generate a raw SQL string.

## Selecting Columns (`select`)

The `select` method specifies which columns to return. You can pass simple column names, aliases, or even complex expressions.

```dart
// Select specific columns
q.select('id, title, due_date')

// Use aliases for clarity
q.select('u.name as author_name, p.title as post_title')

// Use expressions and aggregate functions
q.select('COUNT(*) as total_tasks, AVG(priority) as avg_priority')
```

## Specifying the Source (`from`)

The `from` method specifies the main table for the query. You can also provide an alias for the table, which is highly recommended, especially when performing joins.

```dart
// Simple from
q.from('tasks')

// Using an alias
q.from('tasks', as: 't')
```

## Joining Tables (`join`)

You can join additional tables using the `join`, `leftJoin`, `rightJoin`, and `innerJoin` methods.

```dart
q.select('t.title, u.name as author')
  .from('tasks', as: 't')
  .join('users', on: 't.user_id = u.id', as: 'u')
```

## Filtering Results (`where`)

The `where` method filters the results. It accepts a `WhereClause` object, which can be constructed using helper functions.

### Condition Helpers

- `col(columnName)`: Refers to a column.
- `.eq(value)`: Equal to
- `.neq(value)`: Not equal to
- `.gt(value)`: Greater than
- `.gte(value)`: Greater than or equal to
- `.lt(value)`: Less than
- `.lte(value)`: Less than or equal to
- `.like(pattern)`: LIKE operator
- `.inList(values)`: IN operator
- `.isNull()`: IS NULL
- `.isNotNull()`: IS NOT NULL

### Logical Operators

- `and([...])`: Logical AND
- `or([...])`: Logical OR

### Example `where` Clauses

```dart
// Simple condition
q.where(col('is_completed').eq(1))

// Multiple conditions with AND
q.where(and([
  col('priority').gt(3),
  col('due_date').isNotNull(),
]))

// Complex condition with OR and AND
q.where(or([
  col('status').eq('urgent'),
  and([
    col('priority').gte(5),
    col('is_completed').eq(0),
  ])
]))
```

## Ordering Results (`orderBy`)

The `orderBy` method sorts the query results.

```dart
// Order by a single column, ascending (default)
q.orderBy('created_at')

// Order by a single column, descending
q.orderBy('created_at DESC')

// Order by multiple columns
q.orderBy('priority DESC, due_date ASC')
```

## Grouping Results (`groupBy`)

The `groupBy` method is used with aggregate functions to group rows that have the same values in specified columns into summary rows.

```dart
// Count the number of tasks per user
q.select('user_id, COUNT(*) as task_count')
  .from('tasks')
  .groupBy('user_id')
```

## Limiting Results (`limit` and `offset`)

- `limit(count)`: Restricts the number of rows returned.
- `offset(count)`: Skips a specified number of rows before beginning to return rows.

This is commonly used for pagination.

```dart
// Get the second page of 10 tasks
q.from('tasks')
  .orderBy('created_at DESC')
  .limit(10)
  .offset(10)
```

## Putting It All Together

Here is a complete example using `queryWithBuilder` to fetch the top 5 highest-priority, incomplete tasks assigned to a specific user, along with the user's name.

```dart
final highPriorityTasks = await database.queryWithBuilder((q) {
  q
      .select('t.id, t.title, t.priority, u.name as user_name')
      .from('tasks', as: 't')
      .join('users', on: 't.user_id = u.id', as: 'u')
      .where(and([
        col('t.user_id').eq('user-123'),
        col('t.is_completed').eq(0),
        col('t.priority').gte(4),
      ]))
      .orderBy('t.priority DESC, t.due_date ASC')
      .limit(5);
});

print(highPriorityTasks);
```
