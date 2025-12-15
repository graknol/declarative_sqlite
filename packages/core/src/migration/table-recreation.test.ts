import { describe, it, expect, beforeEach } from 'vitest';
import { SchemaBuilder } from '../schema/builders/schema-builder';
import { SchemaMigrator } from './schema-migrator';
import { SQLiteAdapter } from '../adapters/adapter.interface';

describe('Table Recreation - Complex Schema Changes', () => {
  let mockAdapter: SQLiteAdapter;
  let mockStatements: any[] = [];
  let mockExecCalls: string[] = [];

  beforeEach(() => {
    mockStatements = [];
    mockExecCalls = [];

    // Mock adapter
    mockAdapter = {
      isOpen: () => true,
      prepare: (sql: string) => {
        const stmt = {
          sql,
          run: async (...args: any[]) => ({ changes: 1, lastInsertRowid: 1 }),
          all: async () => {
            // Simulate existing database with users table
            if (sql.includes('sqlite_master')) {
              return [{ name: 'users' }];
            }
            // Simulate PRAGMA table_info for users (original schema)
            if (sql.includes('PRAGMA table_info')) {
              return [
                { name: 'id', type: 'TEXT', notnull: 1, dflt_value: null, pk: 1 },
                { name: 'name', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
                { name: 'age', type: 'INTEGER', notnull: 0, dflt_value: null, pk: 0 },
                { name: 'email', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
                { name: 'legacy_field', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
              ];
            }
            // Simulate PRAGMA index_list
            if (sql.includes('PRAGMA index_list')) {
              return [];
            }
            return [];
          },
          finalize: async () => {},
        };
        mockStatements.push(stmt);
        return stmt;
      },
      exec: async (sql: string) => {
        mockExecCalls.push(sql);
      },
      transaction: async (callback: () => Promise<void>) => {
        await callback();
      },
    } as any;
  });

  it('should recreate table when dropping columns', async () => {
    // Create schema WITHOUT legacy_field (column drop)
    const schema = new SchemaBuilder()
      .table('users', (table) => {
        table.text('id').notNull('');
        table.text('name');
        table.integer('age');
        table.text('email');
        // legacy_field is intentionally removed
        table.key('id').primary();
      })
      .build();

    const migrator = new SchemaMigrator(mockAdapter);
    const plan = await migrator.planMigration(schema);

    // Should detect table recreation needed
    expect(plan.hasOperations).toBe(true);
    const recreateOp = plan.operations.find(op => op.description.includes('Recreate table'));
    expect(recreateOp).toBeDefined();
    expect(recreateOp?.description).toContain('1 column(s) dropped');

    // Execute migration
    await migrator.migrate(schema);

    // Verify table recreation flow
    const createTableCall = mockExecCalls.find(sql => sql.includes('CREATE TABLE "users_new"'));
    const insertCall = mockExecCalls.find(sql => sql.includes('INSERT INTO "users_new"'));
    const dropCall = mockExecCalls.find(sql => sql.includes('DROP TABLE "users"'));
    const renameCall = mockExecCalls.find(sql => sql.includes('ALTER TABLE "users_new" RENAME TO "users"'));

    expect(createTableCall).toBeDefined();
    expect(insertCall).toBeDefined();
    expect(dropCall).toBeDefined();
    expect(renameCall).toBeDefined();
    
    // Verify legacy_field is NOT in the new table
    expect(createTableCall).not.toContain('legacy_field');
    
    // Verify data is preserved for remaining columns
    expect(insertCall).toContain('id');
    expect(insertCall).toContain('name');
    expect(insertCall).toContain('age');
    expect(insertCall).toContain('email');
    expect(insertCall).not.toContain('legacy_field');
  });

  it('should recreate table when modifying column types', async () => {
    // Create schema with age changed from INTEGER to TEXT
    const schema = new SchemaBuilder()
      .table('users', (table) => {
        table.text('id').notNull('');
        table.text('name');
        table.text('age'); // Changed from INTEGER to TEXT
        table.text('email');
        table.text('legacy_field');
        table.key('id').primary();
      })
      .build();

    const migrator = new SchemaMigrator(mockAdapter);
    const plan = await migrator.planMigration(schema);

    // Should detect table recreation needed
    expect(plan.hasOperations).toBe(true);
    const recreateOp = plan.operations.find(op => op.description.includes('Recreate table'));
    expect(recreateOp).toBeDefined();
    expect(recreateOp?.description).toContain('column(s) modified');

    // Execute migration
    await migrator.migrate(schema);

    // Verify table recreation flow
    const createTableCall = mockExecCalls.find(sql => sql.includes('CREATE TABLE "users_new"'));
    expect(createTableCall).toBeDefined();
    
    // Verify age column is now TEXT
    expect(createTableCall).toContain('"age" TEXT');
  });

  it('should handle combination of adds, drops, and modifications', async () => {
    // Create schema with multiple changes
    const schema = new SchemaBuilder()
      .table('users', (table) => {
        table.text('id').notNull('');
        table.text('name');
        // age column dropped
        table.text('email');
        // legacy_field dropped
        table.text('phone'); // NEW column added
        table.text('status').lww(); // NEW LWW column added
        table.key('id').primary();
      })
      .build();

    const migrator = new SchemaMigrator(mockAdapter);
    const plan = await migrator.planMigration(schema);

    // Should detect table recreation needed
    expect(plan.hasOperations).toBe(true);
    const recreateOp = plan.operations.find(op => op.description.includes('Recreate table'));
    expect(recreateOp).toBeDefined();
    
    const description = recreateOp?.description || '';
    expect(description).toContain('column(s) added'); // phone, status, status__hlc + system columns
    expect(description).toContain('2 column(s) dropped'); // age, legacy_field

    // Execute migration
    await migrator.migrate(schema);

    // Verify table recreation
    const createTableCall = mockExecCalls.find(sql => sql.includes('CREATE TABLE "users_new"'));
    const insertCall = mockExecCalls.find(sql => sql.includes('INSERT INTO "users_new"'));

    expect(createTableCall).toBeDefined();
    expect(insertCall).toBeDefined();
    
    // Verify new columns in create
    expect(createTableCall).toContain('phone');
    expect(createTableCall).toContain('status');
    expect(createTableCall).toContain('status__hlc');
    
    // Verify dropped columns not in create
    expect(createTableCall).not.toContain('age');
    expect(createTableCall).not.toContain('legacy_field');
    
    // Verify only preserved columns are in insert
    expect(insertCall).toContain('id');
    expect(insertCall).toContain('name');
    expect(insertCall).toContain('email');
    expect(insertCall).not.toContain('age');
    expect(insertCall).not.toContain('legacy_field');
    expect(insertCall).not.toContain('phone'); // New column, no data to insert
    expect(insertCall).not.toContain('status'); // New column, no data to insert
  });
});
