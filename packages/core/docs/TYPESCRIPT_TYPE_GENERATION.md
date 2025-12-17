# TypeScript Type Generation from Schema

This guide explains how to generate TypeScript types from declarative-sqlite schema definitions to ensure type safety matches the actual database structure.

## Overview

When you define a schema using the declarative-sqlite API, the library automatically enhances your tables with additional columns. To generate accurate TypeScript types for your database records, you need to account for:

1. Your explicitly defined columns
2. Auto-generated system columns (for non-system tables)
3. Auto-generated LWW companion columns (for conflict resolution)

## Column Properties

Each column in your schema is defined by a `DbColumn` interface with these key properties:

- **`name`**: The column name (always in snake_case)
- **`type`**: One of: `'TEXT'`, `'INTEGER'`, `'REAL'`, `'BLOB'`, `'GUID'`, `'DATE'`, `'FILESET'`
- **`notNull`**: Boolean indicating if the column is required (NOT NULL)
- **`defaultValue`**: Optional default value for the column
- **`lww`**: Boolean indicating if this is a Last-Write-Wins (LWW) column for CRDT conflict resolution
- **`maxLength`**: Optional maximum length for TEXT fields
- **`maxFileCount`**: Optional maximum file count for FILESET fields
- **`maxFileSize`**: Optional maximum file size for FILESET fields
- **`validValues`**: Optional array of allowed values (for enums)

## Auto-Generated Columns

### System Columns

For **non-system tables** (tables where `isSystemTable !== true`), the following columns are automatically added:

```typescript
{
  name: 'system_id',
  type: 'GUID',
  notNull: true
}
{
  name: 'system_created_at',
  type: 'TEXT',
  notNull: true
}
{
  name: 'system_version',
  type: 'TEXT',
  notNull: true
}
{
  name: 'system_is_local_origin',
  type: 'INTEGER',
  notNull: true
}
```

### LWW Companion Columns

For **every column** where `lww: true`, a companion column is automatically added:

```typescript
{
  name: `${columnName}__hlc`,
  type: 'TEXT',
  notNull: false  // Always nullable
}
```

The `__hlc` suffix stands for "Hybrid Logical Clock" and stores the timestamp for conflict resolution.

## Type Mapping

Map SQLite/declarative-sqlite column types to TypeScript types:

| Column Type | TypeScript Type | Notes |
|-------------|-----------------|-------|
| `TEXT` | `string` | Standard text |
| `GUID` | `string` | UUID string |
| `DATE` | `string` | ISO 8601 date string |
| `INTEGER` | `number` | Whole numbers |
| `REAL` | `number` | Floating point |
| `BLOB` | `Uint8Array` | Binary data |
| `FILESET` | `any` | File references |

## Nullability Rules

- If `notNull === true`, the property is **required** (non-nullable)
- If `notNull === false` or `notNull === undefined`, the property is **optional** (nullable)
- All LWW companion columns (`__hlc` suffix) are **always nullable**

In TypeScript:
- Required: `propertyName: Type`
- Optional: `propertyName?: Type | null`

## Type Generation Algorithm

```typescript
function generateTableType(table: DbTable): string {
  const properties: string[] = [];
  
  // 1. Add user-defined columns
  for (const column of table.columns) {
    const tsType = mapColumnTypeToTS(column.type);
    const nullable = !column.notNull;
    const property = nullable 
      ? `${column.name}?: ${tsType} | null`
      : `${column.name}: ${tsType}`;
    properties.push(property);
  }
  
  // 2. Add system columns (if not a system table)
  if (!table.isSystemTable) {
    properties.push('system_id: string');
    properties.push('system_created_at: string');
    properties.push('system_version: string');
    properties.push('system_is_local_origin: number');
  }
  
  // 3. Add LWW companion columns
  for (const column of table.columns) {
    if (column.lww) {
      properties.push(`${column.name}__hlc?: string | null`);
    }
  }
  
  return `export interface ${pascalCase(table.name)} {\n  ${properties.join(';\n  ')};\n}`;
}

function mapColumnTypeToTS(type: ColumnType): string {
  switch (type) {
    case 'TEXT':
    case 'GUID':
    case 'DATE':
      return 'string';
    case 'INTEGER':
    case 'REAL':
      return 'number';
    case 'BLOB':
      return 'Uint8Array';
    case 'FILESET':
      return 'any';
  }
}
```

## Example

Given this schema definition:

```typescript
const schema = new SchemaBuilder()
  .table('users', t => t
    .text('username').notNull()
    .text('email').notNull()
    .integer('age')
    .text('status').lww() // LWW column for conflict resolution
  )
  .build();
```

The generated TypeScript type should be:

```typescript
export interface Users {
  // User-defined columns
  username: string;
  email: string;
  age?: number | null;
  status?: string | null;
  
  // Auto-generated system columns
  system_id: string;
  system_created_at: string;
  system_version: string;
  system_is_local_origin: number;
  
  // Auto-generated LWW companion column
  status__hlc?: string | null;
}
```

## Best Practices

1. **Always check `table.isSystemTable`** before adding system columns
2. **Scan all columns for `lww: true`** to add companion `__hlc` columns
3. **Use snake_case** for all property names (matches database convention)
4. **Handle nullability correctly** - TypeScript's strict null checks require explicit `| null`
5. **Consider creating utility types** for common patterns:
   ```typescript
   type SystemColumns = {
     system_id: string;
     system_created_at: string;
     system_version: string;
     system_is_local_origin: number;
   };
   
   type WithLWW<T extends string> = {
     [K in `${T}__hlc`]?: string | null;
   };
   ```

## Additional Record Properties

When querying records from the database, you may encounter these additional properties on the returned objects (not part of the database schema):

- **`xRec`**: Snapshot of original values (used internally for change tracking)
- **`__tableName`**: Internal property tracking which table the record belongs to

These properties are implementation details and should not be included in your generated types unless you specifically need them for advanced use cases.

## Notes

- All column names are stored in **snake_case** in the database
- System columns are prefixed with `system_`
- LWW companion columns are suffixed with `__hlc`
- The type generation should be idempotent - running it multiple times produces the same output
- Consider generating a separate type file per table or one file with all table types
