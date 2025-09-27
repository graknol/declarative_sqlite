# GitHub Copilot Instructions for the `declarative_sqlite` Project

This document provides guidance for GitHub Copilot to offer the most relevant and helpful suggestions for the `declarative_sqlite` library and its related packages.

## Project Overview

`declarative_sqlite` is a sophisticated Dart library ecosystem designed to provide a fluent, declarative, and type-safe way to define and interact with SQLite databases. The core philosophy is to define the entire database schema in code and let the library handle the complexities of database creation, migration, data access, synchronization, and file management.

The project consists of four main packages:

1.  **`declarative_sqlite`**: The core library for schema definition, automatic migration, data access, LWW conflict resolution, file management, and synchronization logic.
2.  **`declarative_sqlite_flutter`**: Flutter-specific reactive widgets and helpers for seamless UI integration with the core library.
3.  **`declarative_sqlite_generator`**: Build-time code generation for type-safe data classes and repository patterns.
4.  **`ifs_cloud_auth`**: Authentication library for IFS Cloud instances integration.

## Core Concepts

### 1. Declarative Schema Definition

The database schema is the single source of truth and is defined using a `SchemaBuilder`. This builder provides a fluent API for defining tables, columns, keys, views, and relationships. The schema includes both user-defined tables and automatically generated system tables for managing metadata, files, and synchronization state.

**Example:**

```dart
final schemaBuilder = SchemaBuilder();
schemaBuilder.table('users', (table) {
  table.guid('id').notNull('00000000-0000-0000-0000-000000000000');
  table.text('name').notNull('Default Name');
  table.integer('age').notNull(0);
  table.real('balance').lww(); // Last-Write-Wins column
  table.fileset('documents').max(10); // File management
  table.key(['id']).primary();
  table.key(['name']).index();
});
schemaBuilder.view('user_summary', (view) {
  view.select('id').select('name').select('balance').from('users').where(/* conditions */);
});
final schema = schemaBuilder.build();
```

**When assisting with schema definition, Copilot should:**

- Encourage the use of fluent builder methods (`.notNull()`, `.primary()`, `.lww()`, etc.).
- Remember that `.notNull()` **requires** a default value parameter.
- Guide users to define parent tables before child tables when there are logical dependencies.
- Suggest appropriate data types: `guid()`, `text()`, `integer()`, `real()`, `date()`, `fileset()`.
- Recommend using `.lww()` for columns that need conflict resolution in distributed scenarios.
- Suggest `fileset()` columns for managing file attachments with built-in versioning and metadata.

### 2. Automatic Migration System

A cornerstone feature is the sophisticated automatic migration system. The library compares the declarative schema with the live database schema and generates the necessary SQL scripts to update it safely.

**Migration Process:**
1. **Introspect**: Read the current database schema using SQLite PRAGMA statements
2. **Diff**: Compare declarative schema with live schema to identify differences
3. **Generate**: Create migration scripts to resolve differences
4. **Execute**: Apply changes within a single transaction for atomicity

**Key Migration Features:**
- **Safe Table Recreation**: For unsupported ALTER TABLE operations (dropping columns, changing constraints, modifying primary keys)
- **Data Preservation**: Uses temporary tables and careful data copying to prevent data loss
- **Constraint Handling**: Automatically applies default values when adding NOT NULL constraints
- **Index Management**: Creates and drops indices as needed

**When helping with migrations, Copilot should:**

- Remind users that complex schema changes (dropping columns, adding NOT NULL constraints) are handled automatically through table recreation
- Emphasize that default values are required when adding NOT NULL constraints to existing tables
- Explain that the migration process is atomic - either all changes succeed or none are applied
- Suggest using `SchemaMigrator.planMigration()` to preview changes before applying them

### 3. Last-Write-Wins (LWW) Conflict Resolution

The library implements sophisticated conflict resolution using Hybrid Logical Clocks (HLC) for distributed, offline-first applications.

**LWW Concepts:**
- **HLC Timestamps**: Combine physical time with logical counters for conflict-free ordering
- **Automatic Conflict Resolution**: Latest write wins based on HLC timestamps
- **LWW Columns**: Use `.lww()` modifier to enable conflict resolution for specific columns
- **Metadata Tracking**: Automatic creation of `__hlc` columns for conflict resolution

**HLC Format**: `<milliseconds>:<counter>:<nodeId>`

**Example:**
```dart
table.real('balance').lww(); // Creates balance__hlc column automatically
table.text('status').lww(); // Creates status__hlc column automatically
```

**When working with LWW, Copilot should:**

- Suggest `.lww()` for columns that may be modified concurrently across devices
- Explain that LWW columns automatically get companion `__hlc` columns for timestamp tracking
- Recommend LWW for user-editable fields in offline-capable applications
- Warn that LWW is not suitable for columns requiring strict consistency (like account balances in financial systems)

### 4. File Management with Filesets

The library provides built-in file management through `fileset` columns, which handle file storage, versioning, and metadata tracking.

**Fileset Features:**
- **Automatic Metadata**: Size, MIME type, creation/modification timestamps
- **Version Control**: File versioning with HLC timestamps
- **Storage Abstraction**: Pluggable storage backends (filesystem, cloud storage)
- **Constraint Support**: Maximum file count, file size limits
- **System Tables**: Automatic `__files` table for metadata management

**Example:**
```dart
table.fileset('attachments').max(16).maxFileSize.mb(8); // Up to 16 files, 8MB each
table.fileset('gallery').max(64).maxFileSize.mb(30); // Up to 64 images, 30MB each
```

**When working with filesets, Copilot should:**

- Suggest `fileset()` columns for any file attachment requirements
- Recommend appropriate file count and size limits based on use case
- Explain that fileset metadata is automatically managed in system tables
- Guide users to use the `FileSet` API for programmatic file operations

### 5. System Tables and Internal Architecture

The library automatically creates and manages system tables for internal operations:

- **`__settings`**: Key-value configuration storage
- **`__files`**: File metadata for fileset columns
- **`__dirty_rows`**: Change tracking for synchronization

**When working with system tables, Copilot should:**

- Explain that system tables (prefixed with `__`) are automatically managed
- Discourage direct manipulation of system tables
- Suggest using the appropriate APIs (`FileSet`, `DirtyRowStore`, etc.) instead of direct SQL
- Remind users that system tables are included in schema migrations

## API Patterns and Coding Style

The project follows strict architectural and coding principles that should be consistently applied across all code suggestions.

### Core Library Design Principles

**Fluent Builder Pattern:**
- All schema definition uses method chaining for clarity and discoverability
- Builder methods return `this` to enable chaining
- Terminal methods like `.build()` return immutable objects
- Example: `table.guid('id').notNull('default').primary()`

**Immutable Data Structures:**
- Schema, Table, Column, and View objects are immutable after creation
- Use builders for construction, immutable objects for runtime
- Avoid setter methods; prefer constructor-based initialization

**Composition Over Inheritance:**
- Prefer composing smaller, focused classes over deep inheritance hierarchies
- Use interfaces (`abstract class`) to define contracts
- Implement features directly in target classes rather than through proxy layers

**Separation of Concerns:**
- **Schema Layer**: Pure data structures representing database schema
- **Builder Layer**: Fluent APIs for constructing schema objects
- **Migration Layer**: Schema comparison and SQL generation
- **Database Layer**: Execution and transaction management
- **Sync Layer**: Conflict resolution and change tracking

### Error Handling Patterns

**Validation at Build Time:**
- Validate schema constraints during `.build()` calls
- Throw descriptive exceptions for invalid configurations
- Example: Required default values, circular references, invalid column names

**Graceful Error Recovery:**
- Migration failures should rollback cleanly
- File operations should handle I/O errors gracefully
- Sync operations should retry with exponential backoff

### Naming Conventions

**Dart/Flutter Standards:**
- Use `camelCase` for variables, methods, and properties
- Use `PascalCase` for classes and types
- Use `snake_case` for database table and column names
- Prefix system tables with `__` (double underscore)

**API Consistency:**
- Builder classes end with `Builder` (e.g., `TableBuilder`, `SchemaBuilder`)
- Fluent methods use descriptive verbs (`.notNull()`, `.primary()`, `.lww()`)
- Query methods follow SQL terminology (`.select()`, `.from()`, `.where()`)

### Testing Patterns

**Unit Test Structure:**
- Use `group()` for organizing related tests
- Use descriptive test names that explain the expected behavior
- Test both success paths and error conditions
- Example: `'can build table with lww columns and system table generation'`

**Test Helpers:**
- Use `test_helper.dart` for common test utilities
- Create reusable schema builders for complex scenarios
- Use in-memory databases for isolation

**Integration Testing:**
- Test complete migration scenarios
- Verify data preservation across schema changes
- Test synchronization workflows end-to-end

### Performance Considerations

**Query Optimization:**
- Encourage appropriate index creation for common query patterns
- Suggest batch operations for bulk data changes
- Recommend streaming for large result sets

**Memory Management:**
- Use lazy evaluation for query results where possible
- Dispose of streams and subscriptions properly
- Avoid loading large datasets entirely into memory

**Database Connection Management:**
- Reuse database connections when possible
- Use transactions for multi-operation consistency
- Close resources properly in finally blocks

## Flutter Integration Guidelines

When working with the Flutter package (`declarative_sqlite_flutter`), follow these additional principles:

### Widget Design Philosophy

**Stateless Over Stateful:**
- Avoid creating stateful widgets unless absolutely necessary
- Prefer stateless widgets that rebuild when underlying data changes
- Use reactive patterns with StreamBuilder for dynamic content

**Composition Over Inheritance:**
- Build complex widgets by composing smaller, focused widgets
- Avoid deep inheritance hierarchies
- Create reusable widget components for common patterns

**Uni-directional Data Flow:**
- Properties flow down the widget tree
- Avoid bi-directional prop passing or callback chains
- Use reactive streams for upward data communication

**Flutter API Consistency:**
- Imitate the API style of core Flutter widgets
- When wrapping widgets (e.g., `ListView`), expose and forward relevant properties
- Example: `ReactiveListView` should accept `scrollDirection` and pass it to the underlying `ListView`

**No Proxy Pattern:**
- Implement features directly in target classes
- Avoid creating helper classes that just delegate calls
- Prefer direct integration over abstraction layers

### Iteration and Simplification

**Continuous Improvement:**
- Never hesitate to refactor and simplify existing code
- Break down long methods and deeply nested functions
- Converge toward clean, generic implementations
- No backwards compatibility concerns during active development

**Breaking Changes Welcome:**
- Suggest breaking changes if they lead to cleaner APIs
- Focus on long-term maintainability over short-term stability
- Prioritize developer experience and code clarity

## Practical Examples and Best Practices

### Complete Schema Definition Example

```dart
final schema = SchemaBuilder()
  .table('work_orders', (table) {
    table.guid('id').notNull('00000000-0000-0000-0000-000000000000');
    table.text('customer_id').notNull('default_customer');
    table.real('total').notNull(0.0).lww(); // Editable by users
    table.date('start_date').notNull('1970-01-01');
    table.fileset('attachments').max(16).maxFileSize.mb(8);
    table.fileset('photos').max(64).maxFileSize.mb(30);
    table.key(['id']).primary();
    table.key(['start_date']).index(); // For sorting
    table.key(['customer_id']).index(); // For filtering
  })
  .table('work_order_lines', (table) {
    table.guid('work_order_id').notNull('00000000-0000-0000-0000-000000000000').parent();
    table.integer('line_no').notNull(1);
    table.text('description').maxLength(500);
    table.real('quantity').notNull(0.0).lww();
    table.key(['work_order_id', 'line_no']).primary();
    table.key(['work_order_id']).index(); // Performance index for queries
  })
  .view('work_order_summary', (view) {
    view
      .select('wo.id').select('wo.customer_id').select('wo.total')
      .selectSubQuery((sub) => sub.count().from('work_order_lines', 'wol')
        .where(/* wol.work_order_id = wo.id */), 'line_count')
      .from('work_orders', 'wo')
      .where(/* wo.total > 1000 */);
  })
  .build();
```

### Migration Best Practices

```dart
// Check migration plan before applying
final migrator = SchemaMigrator();
final plan = await migrator.planMigration(database, schema);

if (plan.hasOperations) {
  print('Migration required:');
  print('Tables to create: ${plan.tablesToCreate.map((t) => t.name)}');
  print('Tables to alter: ${plan.tablesToAlter.map((t) => t.name)}');
  
  // Apply migration in transaction
  await migrator.migrate(database, schema);
  print('Migration completed successfully');
}
```

### File Management with Filesets

```dart
// Adding files to a fileset
final fileId = await database.files.addFile(
  'work_order_attachments',
  'invoice.pdf',
  pdfBytes,
);

// Retrieving file content
final content = await database.files.getFileContent(fileId);

// Querying file metadata
final files = await database.queryTable('__files', 
  where: 'fileset = ?', 
  whereArgs: ['work_order_attachments']
);
```

### LWW Conflict Resolution

```dart
// Setting LWW values (automatically handles HLC timestamps)
await database.updateLww('work_orders', workOrderId, {
  'total': 15000.0,
  'status': 'completed',
});

// Reading LWW values with timestamps
final row = await database.queryTable('work_orders', 
  where: 'id = ?', 
  whereArgs: [workOrderId]
).first;

final total = row['total']; // Current value
final totalHlc = Hlc.parse(row['total__hlc']); // Conflict resolution timestamp
```

## Common Patterns and Anti-Patterns

### ✅ Recommended Patterns

**Schema Evolution:**
```dart
// Add new optional column
table.text('notes'); // Defaults to NULL, safe to add

// Add new required column with default
table.integer('priority').notNull(1); // Safe with default value

// Add LWW column for user editing
table.text('status').lww(); // Enables conflict resolution
```

**Query Organization:**
```dart
// Use views for complex, reusable queries
builder.view('active_work_orders', (view) {
  view.selectAll().from('work_orders')
    .where(/* status IN ('active', 'pending') */);
});

// Use indices for common query patterns
table.key(['customer_id', 'status']).index(); // Composite index
```

### ❌ Anti-Patterns to Avoid

**Schema Mistakes:**
```dart
// ❌ NOT NULL without default value
table.text('required_field').notNull(); // Missing default!

// ❌ Using LWW for system-critical data
table.real('account_balance').lww(); // Don't use LWW for financial data!

// ❌ Missing indices for related columns
table.guid('parent_id'); // Should add .index() for performance
```

**Code Organization:**
```dart
// ❌ Creating unnecessary helper classes
class DatabaseHelper {
  static Future<void> insertUser(Database db, User user) { /* ... */ }
}

// ✅ Use the database API directly
await database.insert('users', user.toMap());
```

## Development Workflow

### Testing Strategy
1. Write unit tests for schema builders and validation
2. Test migration scenarios with before/after data verification
3. Integration test synchronization workflows
4. Performance test with realistic data volumes

### Debugging Tips
- Use `SchemaMigrator.planMigration()` to preview schema changes
- Enable SQL logging to debug query performance
- Monitor HLC timestamp progression for conflict resolution issues
- Validate fileset constraints during development

### Performance Optimization
- Create indices for all related/reference columns
- Use composite indices for multi-column WHERE clauses
- Batch bulk operations for better performance
- Consider view materialization for expensive computations

## Package Publishing to pub.dev

The declarative_sqlite ecosystem consists of three packages that can be published independently to pub.dev. Automated publishing is set up through GitHub Actions with workflow_dispatch triggers.

### Package Overview

The three publishable packages are:

1. **`declarative_sqlite`** (Core library)
   - Path: `/declarative_sqlite/`
   - Current version: 1.0.2
   - Tag pattern: `declarative_sqlite-{{version}}`

2. **`declarative_sqlite_flutter`** (Flutter integration)
   - Path: `/declarative_sqlite_flutter/`
   - Current version: 1.0.2  
   - Tag pattern: `declarative_sqlite_flutter-{{version}}`

3. **`declarative_sqlite_generator`** (Code generation)
   - Path: `/declarative_sqlite_generator/`
   - Current version: 1.0.2
   - Tag pattern: `declarative_sqlite_generator-{{version}}`

### Publishing Instructions

**When asked to publish a new version of any package, follow these steps:**

#### 1. Version Increment Guidelines

Follow semantic versioning (semver) principles:

- **Patch version (x.y.Z)**: Bug fixes, documentation updates, minor improvements
- **Minor version (x.Y.z)**: New features, non-breaking API additions
- **Major version (X.y.z)**: Breaking changes, major API redesigns

**Examples:**
- `1.0.2` → `1.0.3` (patch: bug fix)
- `1.0.2` → `1.1.0` (minor: new feature)
- `1.0.2` → `2.0.0` (major: breaking change)

#### 2. Update Package Version

For each package being published, update the following files:

**Required files to update:**
1. `pubspec.yaml` - Update the `version:` field
2. `CHANGELOG.md` - Add new version entry with changes

**Example for declarative_sqlite:**
```yaml
# In /declarative_sqlite/pubspec.yaml
name: declarative_sqlite
description: A dart package for declaratively creating SQLite tables and automatically migrating them.
version: 1.0.3  # Updated version
```

```markdown
# In /declarative_sqlite/CHANGELOG.md
## 1.0.3

### Bug Fixes
- Fixed issue with schema migration edge case
- Improved error handling in query builder

## 1.0.2
# ... existing entries
```

#### 3. Update Inter-package Dependencies

**Critical**: When publishing core packages, ensure dependent packages reference the correct versions:

- If publishing `declarative_sqlite`, check and update:
  - `declarative_sqlite_flutter/pubspec.yaml` dependency
  - `declarative_sqlite_generator/pubspec.yaml` dependency
  - Demo app and test project dependencies

**Example dependency update:**
```yaml
# In declarative_sqlite_flutter/pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  declarative_sqlite: ^1.0.3  # Updated to match published version
```

#### 4. Create Git Tags

Create properly formatted git tags for each package being published:

**Single package:**
```bash
git tag declarative_sqlite-1.0.3
git push origin declarative_sqlite-1.0.3
```

**Multiple packages (if publishing together):**
```bash
git tag declarative_sqlite-1.0.3
git tag declarative_sqlite_flutter-1.0.3
git tag declarative_sqlite_generator-1.0.3
git push origin --tags
```

#### 5. Trigger Automated Publishing

The publishing process is automated through GitHub Actions workflow_dispatch. The tags created in step 4 will trigger the appropriate publishing workflows on pub.dev.

**Verification steps:**
1. Check that tags were pushed successfully: `git ls-remote --tags origin`
2. Monitor GitHub Actions for workflow execution
3. Verify packages appear on pub.dev with correct versions
4. Test installation of newly published packages

#### 6. Example Publishing Scenarios

**Scenario 1: Bug fix in core library**
```
User request: "Publish a patch version of declarative_sqlite with the recent bug fixes"

Actions:
1. Update declarative_sqlite/pubspec.yaml: 1.0.2 → 1.0.3
2. Update declarative_sqlite/CHANGELOG.md with bug fix details
3. Create tag: declarative_sqlite-1.0.3
4. Push tag to trigger automated publishing
```

**Scenario 2: New feature in Flutter package**
```
User request: "Publish a minor version of declarative_sqlite_flutter with the new widget"

Actions:
1. Update declarative_sqlite_flutter/pubspec.yaml: 1.0.2 → 1.1.0
2. Update declarative_sqlite_flutter/CHANGELOG.md with feature details
3. Create tag: declarative_sqlite_flutter-1.1.0
4. Push tag to trigger automated publishing
```

**Scenario 3: Coordinated release of all packages**
```
User request: "Publish new versions of all packages with the latest changes"

Actions:
1. Increment versions appropriately for each package
2. Update all pubspec.yaml files and CHANGELOGs
3. Update inter-package dependencies
4. Create all three tags
5. Push all tags simultaneously
```

### Publishing Best Practices

**Pre-publishing Checklist:**
- [ ] Version numbers follow semantic versioning
- [ ] CHANGELOG.md entries are comprehensive and accurate
- [ ] Inter-package dependencies are updated and consistent
- [ ] All tests pass (`dart test` or `flutter test`)
- [ ] Documentation is updated if API changes occurred
- [ ] No breaking changes in patch/minor versions

**Post-publishing Verification:**
- [ ] New versions appear on pub.dev
- [ ] Package scores and analysis are acceptable
- [ ] Installation works: `dart pub add package_name:^new_version`
- [ ] Demo applications work with new versions

**Common Pitfalls to Avoid:**
- Publishing with outdated inter-package dependencies
- Forgetting to update CHANGELOG.md
- Using incorrect tag patterns (must match workflow expectations)
- Publishing breaking changes as minor/patch versions
- Not testing packages before publishing

**When Multiple Packages Need Updates:**
- Always publish core library (`declarative_sqlite`) first
- Then publish dependent packages (`declarative_sqlite_flutter`, `declarative_sqlite_generator`)
- Ensure version consistency across the ecosystem
- Consider whether changes require coordinated releases

By following these instructions, GitHub Copilot can act as an expert on this specific codebase, providing suggestions that are not just syntactically correct but also align with the project's sophisticated architecture, distributed data patterns, and design philosophy.

**Remember:** Always think about the problem holistically first, considering schema design, data flow, conflict resolution, and user experience. Then apply these specific patterns and guidelines to create robust, maintainable solutions.
