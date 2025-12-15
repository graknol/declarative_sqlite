import { describe, it, expect, beforeEach } from 'vitest';
import { SchemaBuilder } from '../schema/builders/schema-builder';
import { SchemaMigrator } from './schema-migrator';
import { SQLiteAdapter } from '../adapters/adapter.interface';

describe('AutoMigrate Bug - Adding LWW Columns', () => {
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
            // Simulate existing database with c_ncr table WITHOUT responsible_person_id
            if (sql.includes('sqlite_master')) {
              return [{ name: 'c_ncr' }];
            }
            // Simulate PRAGMA table_info for c_ncr (original schema without new column)
            if (sql.includes('PRAGMA table_info')) {
              return [
                { name: 'ncr_no', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
                { name: 'description', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
                { name: 'nonconformance_code', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
                { name: 'severity_id', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
                { name: 'root_cause_id', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
                { name: 'root_cause_id__hlc', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
                // responsible_person_id and responsible_person_id__hlc are MISSING
                { name: 'target_completion_date', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
                { name: 'target_completion_date__hlc', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
                { name: 'system_id', type: 'GUID', notnull: 1, dflt_value: null, pk: 1 },
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

  it('should detect and add new LWW column', async () => {
    // Create schema with NEW column added
    const schema = new SchemaBuilder()
      .table('c_ncr', (table) => {
        table.text('ncr_no').maxLength(100);
        table.text('description').maxLength(2000);
        table.text('nonconformance_code').maxLength(100);
        table.text('severity_id').maxLength(100);
        table.text('root_cause_id').maxLength(50).lww();
        table.text('responsible_person_id').maxLength(50).lww(); // ← NEW COLUMN
        table.date('target_completion_date').lww();
        table.key('system_id').primary();
      })
      .build();

    const migrator = new SchemaMigrator(mockAdapter);
    const plan = await migrator.planMigration(schema);

    console.log('Migration plan:', JSON.stringify(plan, null, 2));

    // Should detect that columns need to be added
    expect(plan.hasOperations).toBe(true);

    // Should have operations to add the missing columns
    expect(plan.operations.length).toBeGreaterThan(0);

    // Execute migration
    await migrator.migrate(schema);

    console.log('Executed SQL:', mockExecCalls);

    // Should have executed table recreation flow (CREATE, INSERT, DROP, RENAME)
    const createTableCall = mockExecCalls.find(sql => sql.includes('CREATE TABLE "c_ncr_new"'));
    const insertCall = mockExecCalls.find(sql => sql.includes('INSERT INTO "c_ncr_new"'));
    const dropCall = mockExecCalls.find(sql => sql.includes('DROP TABLE "c_ncr"'));
    const renameCall = mockExecCalls.find(sql => sql.includes('ALTER TABLE "c_ncr_new" RENAME TO "c_ncr"'));

    expect(createTableCall).toBeDefined();
    expect(insertCall).toBeDefined();
    expect(dropCall).toBeDefined();
    expect(renameCall).toBeDefined();
    
    // Verify the new columns are in the CREATE TABLE statement
    expect(createTableCall).toContain('responsible_person_id');
    expect(createTableCall).toContain('responsible_person_id__hlc');
    
    // Verify the INSERT statement preserves existing columns
    expect(insertCall).toContain('root_cause_id');
    expect(insertCall).toContain('target_completion_date');
  });
});
