import { describe, it, expect } from 'vitest';
import { VERSION } from './index';
import type { SQLiteAdapter, Schema } from './index';

describe('@declarative-sqlite/core', () => {
  it('exports VERSION constant', () => {
    expect(VERSION).toBe('2.0.0');
  });

  it('exports SQLiteAdapter type', () => {
    // Type test - this will fail to compile if type doesn't exist
    const adapter: SQLiteAdapter = {
      open: async () => {},
      close: async () => {},
      exec: async () => {},
      prepare: () => ({
        all: async () => [],
        get: async () => undefined,
        run: async () => ({ changes: 0, lastInsertRowid: 0 }),
        finalize: async () => {},
      }),
      transaction: async (cb) => cb(),
      isOpen: () => false,
    };
    
    expect(adapter).toBeDefined();
  });

  it('exports Schema type', () => {
    // Type test - this will fail to compile if type doesn't exist
    const schema: Schema = {
      tables: [],
      views: [],
      version: '1',
    };
    
    expect(schema).toBeDefined();
  });
});
