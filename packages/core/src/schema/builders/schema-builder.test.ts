import { describe, it, expect } from 'vitest';
import { SchemaBuilder } from './schema-builder';

describe('SchemaBuilder', () => {
  it('creates an empty schema with system tables', () => {
    const schema = new SchemaBuilder().build();
    
    expect(schema.tables).toHaveLength(3); // 3 system tables
    expect(schema.views).toHaveLength(0);
    expect(schema.version).toBeTruthy();
    
    // Check system tables exist
    const tableNames = schema.tables.map(t => t.name);
    expect(tableNames).toContain('__settings');
    expect(tableNames).toContain('__files');
    expect(tableNames).toContain('__dirty_rows');
  });
  
  it('creates a schema with a simple table', () => {
    const schema = new SchemaBuilder()
      .table('users', (t) => {
        t.text('name').notNull('');
        t.integer('age').notNull(0);
      })
      .build();
    
    // Should have 1 user table + 3 system tables
    expect(schema.tables).toHaveLength(4);
    
    const usersTable = schema.tables.find(t => t.name === 'users');
    expect(usersTable).toBeDefined();
    expect(usersTable?.isSystem).toBe(false);
    
    // Check columns (including system columns)
    expect(usersTable?.columns).toHaveLength(6); // name, age + 4 system columns
    
    const nameColumn = usersTable?.columns.find(c => c.name === 'name');
    expect(nameColumn?.type).toBe('TEXT');
    expect(nameColumn?.notNull).toBe(true);
    expect(nameColumn?.defaultValue).toBe('');
    
    const ageColumn = usersTable?.columns.find(c => c.name === 'age');
    expect(ageColumn?.type).toBe('INTEGER');
    expect(ageColumn?.notNull).toBe(true);
    expect(ageColumn?.defaultValue).toBe(0);
  });
  
  it('creates a schema with multiple tables', () => {
    const schema = new SchemaBuilder()
      .table('users', (t) => {
        t.guid('id').notNull('');
        t.text('name').notNull('');
        t.key('id').primary();
      })
      .table('posts', (t) => {
        t.guid('id').notNull('');
        t.text('title').notNull('');
        t.guid('user_id').notNull('');
        t.key('id').primary();
        t.key('user_id').index();
      })
      .build();
    
    // 2 user tables + 3 system tables
    expect(schema.tables).toHaveLength(5);
    
    const userTables = schema.tables.filter(t => !t.isSystem);
    expect(userTables).toHaveLength(2);
    expect(userTables.map(t => t.name)).toEqual(['users', 'posts']);
  });
  
  it('supports LWW columns', () => {
    const schema = new SchemaBuilder()
      .table('users', (t) => {
        t.text('name').lww();
        t.integer('score').lww();
      })
      .build();
    
    const usersTable = schema.tables.find(t => t.name === 'users');
    const nameColumn = usersTable?.columns.find(c => c.name === 'name');
    const scoreColumn = usersTable?.columns.find(c => c.name === 'score');
    
    expect(nameColumn?.lww).toBe(true);
    expect(scoreColumn?.lww).toBe(true);
  });
  
  it('supports fileset columns with constraints', () => {
    const schema = new SchemaBuilder()
      .table('documents', (t) => {
        t.fileset('attachments').max(10).maxFileSize(1024 * 1024);
      })
      .build();
    
    const documentsTable = schema.tables.find(t => t.name === 'documents');
    const attachmentsColumn = documentsTable?.columns.find(c => c.name === 'attachments');
    
    expect(attachmentsColumn?.type).toBe('FILESET');
    expect(attachmentsColumn?.maxFileCount).toBe(10);
    expect(attachmentsColumn?.maxFileSize).toBe(1024 * 1024);
  });
  
  it('supports text column with maxLength', () => {
    const schema = new SchemaBuilder()
      .table('users', (t) => {
        t.text('bio').maxLength(500);
      })
      .build();
    
    const usersTable = schema.tables.find(t => t.name === 'users');
    const bioColumn = usersTable?.columns.find(c => c.name === 'bio');
    
    expect(bioColumn?.maxLength).toBe(500);
  });
  
  it('supports various key types', () => {
    const schema = new SchemaBuilder()
      .table('users', (t) => {
        t.guid('id');
        t.text('email');
        t.text('username');
        
        t.key('id').primary();
        t.key('email').unique();
        t.key('username').index();
      })
      .build();
    
    const usersTable = schema.tables.find(t => t.name === 'users');
    
    expect(usersTable?.keys).toHaveLength(3);
    
    const primaryKey = usersTable?.keys.find(k => k.type === 'PRIMARY');
    expect(primaryKey?.columns).toEqual(['id']);
    
    const uniqueKey = usersTable?.keys.find(k => k.type === 'UNIQUE');
    expect(uniqueKey?.columns).toEqual(['email']);
    
    const indexKey = usersTable?.keys.find(k => k.type === 'INDEX');
    expect(indexKey?.columns).toEqual(['username']);
  });
  
  it('supports composite keys', () => {
    const schema = new SchemaBuilder()
      .table('user_roles', (t) => {
        t.guid('user_id');
        t.guid('role_id');
        
        t.key('user_id', 'role_id').primary();
      })
      .build();
    
    const userRolesTable = schema.tables.find(t => t.name === 'user_roles');
    const primaryKey = userRolesTable?.keys.find(k => k.type === 'PRIMARY');
    
    expect(primaryKey?.columns).toEqual(['user_id', 'role_id']);
  });
  
  it('generates consistent schema versions', () => {
    const schema1 = new SchemaBuilder()
      .table('users', (t) => {
        t.text('name');
      })
      .build();
    
    const schema2 = new SchemaBuilder()
      .table('users', (t) => {
        t.text('name');
      })
      .build();
    
    expect(schema1.version).toBe(schema2.version);
  });
  
  it('generates different versions for different schemas', () => {
    const schema1 = new SchemaBuilder()
      .table('users', (t) => {
        t.text('name');
      })
      .build();
    
    const schema2 = new SchemaBuilder()
      .table('users', (t) => {
        t.text('name');
        t.integer('age');
      })
      .build();
    
    expect(schema1.version).not.toBe(schema2.version);
  });
  
  it('includes system columns in all tables', () => {
    const schema = new SchemaBuilder()
      .table('users', (t) => {
        t.text('name');
      })
      .build();
    
    const usersTable = schema.tables.find(t => t.name === 'users');
    const columnNames = usersTable?.columns.map(c => c.name) ?? [];
    
    expect(columnNames).toContain('system_id');
    expect(columnNames).toContain('system_created_at');
    expect(columnNames).toContain('system_version');
    expect(columnNames).toContain('system_is_local_origin');
  });
});
