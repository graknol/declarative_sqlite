import { describe, it, expect } from 'vitest';
import { MemoryAdapter } from './memory-adapter';
import { WasmAdapterBase } from './wasm';
import { OpfsAdapter } from './opfs-adapter';

describe('WasmAdapterBase', () => {
  it('is what MemoryAdapter is built on', () => {
    expect(new MemoryAdapter()).toBeInstanceOf(WasmAdapterBase);
  });
});

describe('OpfsAdapter', () => {
  it('reports that OPFS is unavailable in Node', () => {
    expect(OpfsAdapter.isSupported()).toBe(false);
  });

  it('fails loudly instead of silently becoming an in-memory database', async () => {
    const adapter = new OpfsAdapter('smoke.db');
    await expect(adapter.open()).rejects.toThrow(/OPFS/i);
    expect(adapter.isOpen()).toBe(false);
  });
});
