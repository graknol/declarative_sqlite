import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { MemoryAdapter } from './memory-adapter';

describe('MemoryAdapter', () => {
  let adapter: MemoryAdapter;

  beforeEach(async () => {
    adapter = new MemoryAdapter();
    await adapter.open();
  });

  afterEach(async () => {
    await adapter.close();
  });

  it('executes DDL and reports open state', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT, b INTEGER)');
    expect(adapter.isOpen()).toBe(true);
  });

  it('runs a parameterised insert and reads it back', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT, b INTEGER)');
    const result = await adapter.run('INSERT INTO t (a, b) VALUES (?, ?)', ['x', 42]);
    expect(result.changes).toBe(1);

    const rows = await adapter.all<{ a: string; b: number }>('SELECT a, b FROM t WHERE b = ?', [42]);
    expect(rows).toEqual([{ a: 'x', b: 42 }]);
  });

  it('returns undefined from get when nothing matches', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT)');
    expect(await adapter.get('SELECT a FROM t WHERE a = ?', ['nope'])).toBeUndefined();
  });

  it('binds null and reads it back as null', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT)');
    await adapter.run('INSERT INTO t (a) VALUES (?)', [null]);
    expect(await adapter.get<{ a: string | null }>('SELECT a FROM t')).toEqual({ a: null });
  });

  it('rolls back an explicit transaction', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT)');
    await adapter.exec('BEGIN IMMEDIATE');
    await adapter.run('INSERT INTO t (a) VALUES (?)', ['x']);
    await adapter.exec('ROLLBACK');
    expect(await adapter.all('SELECT a FROM t')).toEqual([]);
  });

  it('throws when used before open', async () => {
    const closed = new MemoryAdapter();
    await expect(closed.exec('SELECT 1')).rejects.toThrow(/not open/i);
  });

  it('exports the database image', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT)');
    const bytes = await adapter.export();
    expect(bytes.byteLength).toBeGreaterThan(0);
  });
});
