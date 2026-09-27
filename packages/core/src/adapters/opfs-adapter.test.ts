import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { OpfsAdapter } from './opfs-adapter';
import { openAdapter } from './open-adapter';

/**
 * The SAH pool needs real OPFS sync access handles, which Node does not have,
 * so these tests run the adapter against a fake of sqlite-wasm's
 * `OpfsSAHPoolUtil` that keeps the same bookkeeping: a fixed number of slots,
 * one per file, keyed by the URL-normalised path, and "SAH pool is full" when
 * a new file finds no free slot.
 */
class FakePool {
  capacity: number;
  readonly files = new Set<string>();
  readonly closed: string[] = [];
  readonly unlinked: string[] = [];

  readonly OpfsSAHPoolDb: new (filename: string) => { close(): void };

  constructor(initialCapacity: number) {
    this.capacity = initialCapacity;
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    const pool = this;
    this.OpfsSAHPoolDb = class {
      readonly path: string;
      constructor(filename: string) {
        this.path = new URL(filename, 'file://localhost/').pathname;
        if (!pool.files.has(this.path)) {
          if (pool.files.size >= pool.capacity) throw new Error(`SAH pool is full. Cannot create file ${this.path}`);
          pool.files.add(this.path);
        }
      }
      close(): void {
        pool.closed.push(this.path);
      }
    };
  }

  getCapacity(): number {
    return this.capacity;
  }
  getFileCount(): number {
    return this.files.size;
  }
  getFileNames(): string[] {
    return [...this.files];
  }
  async reserveMinimumCapacity(min: number): Promise<number> {
    if (this.capacity < min) this.capacity = min;
    return this.capacity;
  }
  unlink(filename: string): boolean {
    this.unlinked.push(filename);
    return this.files.delete(filename);
  }
  removeVfs = vi.fn(async () => true);
}

const pools = new Map<string, FakePool>();
const installCalls: Record<string, unknown>[] = [];
let installFailure: Error | undefined;

vi.mock('./memory-adapter', () => ({
  loadSqlite3: async () => ({
    installOpfsSAHPoolVfs: async (options: Record<string, unknown>) => {
      installCalls.push(options);
      if (installFailure) throw installFailure;
      const name = options['name'] as string;
      let pool = pools.get(name);
      if (!pool) pools.set(name, (pool = new FakePool((options['initialCapacity'] as number | undefined) ?? 6)));
      return pool;
    },
  }),
}));

beforeEach(() => {
  pools.clear();
  installCalls.length = 0;
  installFailure = undefined;
  vi.stubGlobal('navigator', { storage: { getDirectory: async () => ({}) } });
  vi.stubGlobal(
    'FileSystemFileHandle',
    class {
      createSyncAccessHandle(): void {}
    },
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
});

/** Puts files into a pool before any adapter touches it, as if earlier sessions had left them there. */
function seedPool(name: string, capacity: number, files: string[]): FakePool {
  const pool = new FakePool(capacity);
  for (const f of files) pool.files.add(f);
  pools.set(name, pool);
  return pool;
}

describe('OpfsAdapter pool capacity', () => {
  it('keeps the old defaults: pool "declarative-sqlite", no initialCapacity override', async () => {
    const adapter = new OpfsAdapter('defaults.db');
    await adapter.open();
    expect(installCalls[0]).toEqual({ name: 'declarative-sqlite', forceReinitIfPreviouslyFailed: true });
    expect(adapter.poolInfo()).toEqual({ capacity: 6, fileCount: 1, fileNames: ['/defaults.db'] });
    await adapter.close();
  });

  it('passes initialCapacity and grows the pool to minimumCapacity', async () => {
    const adapter = new OpfsAdapter('sized.db', { initialCapacity: 8, minimumCapacity: 16 });
    await adapter.open();
    expect(installCalls[0]).toMatchObject({ initialCapacity: 8 });
    expect(adapter.poolInfo().capacity).toBe(16);
    await adapter.close();
  });

  it('always leaves room for one more database and its journal, so a nearly full pool no longer fails to open', async () => {
    const pool = seedPool('declarative-sqlite', 6, ['/u1.db', '/u2.db', '/u3.db', '/u4.db', '/u5.db', '/u6.db']);
    const adapter = new OpfsAdapter('u7.db');
    await adapter.open();
    expect(pool.capacity).toBe(8);
    expect(pool.files.has('/u7.db')).toBe(true);
    await adapter.close();
  });

  it('never shrinks a pool that is already larger than asked for', async () => {
    const pool = seedPool('declarative-sqlite', 20, []);
    const adapter = new OpfsAdapter('big.db', { minimumCapacity: 16 });
    await adapter.open();
    expect(pool.capacity).toBe(20);
    await adapter.close();
  });

  it('does not wipe the pool when the database cannot be constructed', async () => {
    const pool = seedPool('declarative-sqlite', 1, ['/keep.db']);
    vi.spyOn(pool, 'reserveMinimumCapacity').mockResolvedValue(1);
    const adapter = new OpfsAdapter('late.db');
    await expect(adapter.open()).rejects.toThrow(/SAH pool is full/);
    expect(adapter.isOpen()).toBe(false);
    expect(pool.removeVfs).not.toHaveBeenCalled();
    expect(pool.getFileNames()).toEqual(['/keep.db']);
  });

  it('openAdapter forwards the opfs options', async () => {
    const opened = await openAdapter({
      name: 'forwarded.db',
      backend: 'opfs',
      wasmDir: '/assets',
      opfs: { poolName: 'custom', minimumCapacity: 16 },
    });
    expect(installCalls[0]).toMatchObject({ name: 'custom' });
    expect((opened.adapter as OpfsAdapter).poolInfo().capacity).toBe(16);
    await opened.adapter.close();
  });
});

describe('OpfsAdapter.deleteDatabase', () => {
  it('closes its own database first, then frees the slots of the database and its journal', async () => {
    const adapter = new OpfsAdapter('mine.db');
    await adapter.open();
    const pool = pools.get('declarative-sqlite')!;
    pool.files.add('/mine.db-journal');

    await expect(adapter.deleteDatabase()).resolves.toBe(true);

    expect(adapter.isOpen()).toBe(false);
    expect(pool.closed).toEqual(['/mine.db']);
    expect(pool.unlinked).toEqual(['/mine.db', '/mine.db-journal', '/mine.db-wal', '/mine.db-shm']);
    expect(pool.files.size).toBe(0);
  });

  it('can reopen an empty database after deleting its own', async () => {
    const adapter = new OpfsAdapter('again.db');
    await adapter.open();
    await adapter.deleteDatabase();
    await adapter.open();
    expect(adapter.poolInfo().fileNames).toEqual(['/again.db']);
    await adapter.close();
  });

  it('deletes another user\'s database from the same pool without closing its own', async () => {
    seedPool('declarative-sqlite', 6, ['/old-user.db']);
    const adapter = new OpfsAdapter('current.db');
    await adapter.open();
    await expect(adapter.deleteDatabase('old-user.db')).resolves.toBe(true);
    expect(adapter.isOpen()).toBe(true);
    expect(adapter.poolInfo().fileNames).toEqual(['/current.db']);
    await adapter.close();
  });

  it('refuses to delete a database another adapter here has open', async () => {
    const holder = new OpfsAdapter('held.db');
    await holder.open();
    const other = new OpfsAdapter('other.db');
    await other.open();
    await expect(other.deleteDatabase('held.db')).rejects.toThrow(/open through another OpfsAdapter/);
    await expect(OpfsAdapter.deleteDatabase('held.db')).rejects.toThrow(/open through another OpfsAdapter/);
    expect(holder.isOpen()).toBe(true);
    await holder.close();
    await expect(OpfsAdapter.deleteDatabase('held.db')).resolves.toBe(true);
    await other.close();
  });

  it('the static helper installs the pool itself and uses the same URL-normalised key as open()', async () => {
    const pool = seedPool('shared', 6, ['/user%20a.db', '/user%20a.db-journal', '/b.db']);
    await expect(OpfsAdapter.deleteDatabase('user a.db', { poolName: 'shared' })).resolves.toBe(true);
    expect(pool.getFileNames()).toEqual(['/b.db']);
    await expect(OpfsAdapter.deleteDatabase('missing.db', { poolName: 'shared' })).resolves.toBe(false);
  });

  it('an adapter that was never opened deletes through the static path', async () => {
    const pool = seedPool('declarative-sqlite', 6, ['/never.db']);
    await expect(new OpfsAdapter('never.db').deleteDatabase()).resolves.toBe(true);
    expect(pool.files.size).toBe(0);
  });

  it('says so, with the browser error as cause, when another tab or worker holds the pool', async () => {
    const held = Object.assign(new Error('Access Handles cannot be created'), { name: 'NoModificationAllowedError' });
    installFailure = held;
    const error = (await OpfsAdapter.deleteDatabase('x.db').then(
      () => undefined,
      (e: unknown) => e,
    )) as Error & { cause?: unknown };
    expect(error.message).toMatch(/another tab or worker/);
    expect(error.cause).toBe(held);
  });

  it('fails loudly where OPFS is missing', async () => {
    vi.unstubAllGlobals();
    vi.stubGlobal('navigator', undefined);
    await expect(OpfsAdapter.deleteDatabase('x.db')).rejects.toThrow(/OPFS is not available/);
  });
});

describe('OpfsAdapter.poolInfo', () => {
  it('needs an open adapter', () => {
    expect(() => new OpfsAdapter('closed.db').poolInfo()).toThrow(/open\(\)/);
  });
});
