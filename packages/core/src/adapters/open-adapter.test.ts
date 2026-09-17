import { describe, it, expect } from 'vitest';
import { openAdapter } from './open-adapter';
import { MemoryAdapter } from './memory-adapter';

describe('openAdapter', () => {
  it('falls back to memory when nothing persistent is available, and says so', async () => {
    const opened = await openAdapter({ name: 'test.db', capabilities: { opfs: () => false, indexedDb: () => false } });
    expect(opened.backend).toBe('memory');
    expect(opened.adapter).toBeInstanceOf(MemoryAdapter);
    expect(opened.warnings.join(' ')).toMatch(/not persistent/i);
    await opened.adapter.close();
  });

  it('opens the requested backend without probing when one is named', async () => {
    const opened = await openAdapter({ name: 'test.db', backend: 'memory' });
    expect(opened.backend).toBe('memory');
    expect(opened.warnings).toEqual([]);
    await opened.adapter.close();
  });

  it('falls back from a failing OPFS to memory when IndexedDB is missing too', async () => {
    const opened = await openAdapter({
      name: 'test.db',
      capabilities: { opfs: () => true, indexedDb: () => false },
      opfsTimeoutMs: 50,
    });
    expect(opened.backend).toBe('memory');
    expect(opened.warnings.join(' ')).toMatch(/OPFS/i);
    await opened.adapter.close();
  });

  it('gives up on an OPFS open that hangs', async () => {
    const started = Date.now();
    const opened = await openAdapter({
      name: 'test.db',
      capabilities: { opfs: () => true, indexedDb: () => false },
      opfsTimeoutMs: 50,
    });
    expect(Date.now() - started).toBeLessThan(3000);
    expect(opened.backend).toBe('memory');
    await opened.adapter.close();
  });

  it('opens a usable database whichever backend it lands on', async () => {
    const opened = await openAdapter({ name: 'test.db', capabilities: { opfs: () => false, indexedDb: () => false } });
    await opened.adapter.exec('CREATE TABLE t (a TEXT)');
    await opened.adapter.run('INSERT INTO t (a) VALUES (?)', ['x']);
    expect(await opened.adapter.all('SELECT a FROM t')).toEqual([{ a: 'x' }]);
    await opened.adapter.close();
  });
});
