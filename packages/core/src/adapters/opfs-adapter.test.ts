import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { OpfsAdapter } from './opfs-adapter';
import { openAdapter } from './open-adapter';

/**
 * The SAH pool needs real OPFS sync access handles, which Node does not have,
 * so these tests run the adapter against a fake of sqlite-wasm's
 * `OpfsSAHPoolUtil` that keeps the same bookkeeping: a fixed number of slots,
 * one per file, keyed by the URL-normalised path, "SAH pool is full" when a
 * new file finds no free slot, and (from sqlite-wasm 3.50) pause/unpause,
 * which refuses while a file is open. `browser-test/` runs the real thing.
 */
class FakePool {
  capacity: number;
  paused = false;
  openFiles = 0;
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
        if (pool.paused) throw new Error('VFS is paused');
        this.path = new URL(filename, 'file://localhost/').pathname;
        if (!pool.files.has(this.path)) {
          if (pool.files.size >= pool.capacity) throw new Error(`SAH pool is full. Cannot create file ${this.path}`);
          pool.files.add(this.path);
        }
        pool.openFiles++;
      }
      close(): void {
        pool.openFiles--;
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
  async addCapacity(n: number): Promise<number> {
    this.capacity += n;
    return this.capacity;
  }
  async reserveMinimumCapacity(min: number): Promise<number> {
    return this.capacity < min ? this.addCapacity(min - this.capacity) : this.capacity;
  }
  unlink(filename: string): boolean {
    if (this.paused) throw new Error('VFS is paused');
    this.unlinked.push(filename);
    return this.files.delete(filename);
  }
  removeVfs = vi.fn(async () => true);
}

/** sqlite-wasm 3.50+: can hand its access handles back without deleting anything. */
class PausableFakePool extends FakePool {
  pauseVfs = vi.fn(() => {
    if (this.openFiles > 0) throw new Error('Cannot pause VFS because it has opened files.');
    this.paused = true;
    return this;
  });
  isPaused(): boolean {
    return this.paused;
  }
  unpauseVfs = vi.fn(async () => {
    this.paused = false;
    return this;
  });
}

const pools = new Map<string, FakePool>();
const installCalls: Record<string, unknown>[] = [];
let installFailure: Error | undefined;
let pausable = false;

vi.mock('./memory-adapter', () => ({
  loadSqlite3: async () => ({
    installOpfsSAHPoolVfs: async (options: Record<string, unknown>) => {
      installCalls.push(options);
      if (installFailure) throw installFailure;
      const name = options['name'] as string;
      let pool = pools.get(name);
      if (!pool) {
        const capacity = (options['initialCapacity'] as number | undefined) ?? 6;
        pools.set(name, (pool = pausable ? new PausableFakePool(capacity) : new FakePool(capacity)));
      }
      return pool;
    },
  }),
}));

beforeEach(() => {
  pools.clear();
  installCalls.length = 0;
  installFailure = undefined;
  pausable = false;
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
  vi.restoreAllMocks();
});

/** Puts files into a pool before any adapter touches it, as if earlier sessions had left them there. */
function seedPool(name: string, capacity: number, files: string[], Pool: typeof FakePool = FakePool): FakePool {
  const pool = new Pool(capacity);
  for (const f of files) pool.files.add(f);
  pools.set(name, pool);
  return pool;
}

function heldError(): Error {
  return Object.assign(new Error('Access Handles cannot be created'), { name: 'NoModificationAllowedError' });
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

  it('leaves room for one more database and its journal, so a full pool no longer fails to open', async () => {
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

  it('still opens an existing database when the headroom cannot be added, and warns', async () => {
    const pool = seedPool('declarative-sqlite', 1, ['/existing.db']);
    vi.spyOn(pool, 'addCapacity').mockRejectedValue(new Error('QuotaExceededError'));
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const adapter = new OpfsAdapter('existing.db');
    await adapter.open();
    expect(adapter.isOpen()).toBe(true);
    expect(warn).toHaveBeenCalledWith(expect.stringMatching(/headroom/), expect.any(Error));
    await adapter.close();
  });

  it('fails the open when an explicit minimumCapacity cannot be reached', async () => {
    const pool = seedPool('declarative-sqlite', 1, ['/strict.db']);
    vi.spyOn(pool, 'addCapacity').mockRejectedValue(new Error('QuotaExceededError'));
    const adapter = new OpfsAdapter('strict.db', { minimumCapacity: 16 });
    await expect(adapter.open()).rejects.toThrow(/QuotaExceededError/);
    expect(adapter.isOpen()).toBe(false);
  });

  it('does not wipe the pool when the database cannot be created', async () => {
    const pool = seedPool('declarative-sqlite', 1, ['/keep.db']);
    vi.spyOn(pool, 'addCapacity').mockRejectedValue(new Error('QuotaExceededError'));
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
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

  it("deletes another user's database from the same pool without closing its own", async () => {
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

  it('a never-opened adapter for the same name does not clear the open mark of one that is open', async () => {
    const pool = seedPool('declarative-sqlite', 6, []);
    const live = new OpfsAdapter('shared-name.db');
    await live.open();

    const stranger = new OpfsAdapter('shared-name.db');
    await stranger.close();
    await expect(stranger.deleteDatabase()).rejects.toThrow(/open through another OpfsAdapter/);

    expect(live.isOpen()).toBe(true);
    expect(pool.files.has('/shared-name.db')).toBe(true);
    await live.close();
  });

  it('one of two adapters on the same database closing leaves it marked open for the other', async () => {
    const pool = seedPool('declarative-sqlite', 6, []);
    const first = new OpfsAdapter('twice.db');
    const second = new OpfsAdapter('twice.db');
    await first.open();
    await second.open();

    await first.close();
    await first.close(); // a second close must not count down again
    await expect(OpfsAdapter.deleteDatabase('twice.db')).rejects.toThrow(/open through another OpfsAdapter/);
    expect(pool.files.has('/twice.db')).toBe(true);

    await second.close();
    await expect(OpfsAdapter.deleteDatabase('twice.db')).resolves.toBe(true);
  });

  it('the static helper uses the same URL-normalised key as open()', async () => {
    const pool = seedPool('shared', 6, ['/user%20a.db', '/user%20a.db-journal', '/b.db']);
    await expect(OpfsAdapter.deleteDatabase('user a.db', { poolName: 'shared' })).resolves.toBe(true);
    expect(pool.getFileNames()).toEqual(['/b.db']);
    await expect(OpfsAdapter.deleteDatabase('missing.db', { poolName: 'shared' })).resolves.toBe(false);
  });

  it('the static helper does not ask sqlite-wasm to retry a failed install; open() does', async () => {
    await OpfsAdapter.deleteDatabase('x.db', { poolName: 'no-retry' });
    expect(installCalls[0]).not.toHaveProperty('forceReinitIfPreviouslyFailed');
    const adapter = new OpfsAdapter('y.db', { poolName: 'no-retry' });
    await adapter.open();
    expect(installCalls[1]).toMatchObject({ forceReinitIfPreviouslyFailed: true });
    await adapter.close();
  });

  it('an adapter that was never opened deletes through the static path', async () => {
    const pool = seedPool('declarative-sqlite', 6, ['/never.db']);
    await expect(new OpfsAdapter('never.db').deleteDatabase()).resolves.toBe(true);
    expect(pool.files.size).toBe(0);
  });

  it('says another context holds the pool, with the browser error as cause, only when that is the error', async () => {
    const held = heldError();
    installFailure = held;
    const error = (await OpfsAdapter.deleteDatabase('x.db').then(
      () => undefined,
      (e: unknown) => e,
    )) as Error & { cause?: unknown };
    expect(error.message).toMatch(/another tab or worker holds the OPFS pool/);
    expect(error.cause).toBe(held);

    installFailure = new Error('Missing required OPFS APIs.');
    await expect(OpfsAdapter.deleteDatabase('x.db')).rejects.toThrow(/failed to open/);
  });

  it('fails loudly where OPFS is missing', async () => {
    vi.unstubAllGlobals();
    vi.stubGlobal('navigator', undefined);
    await expect(OpfsAdapter.deleteDatabase('x.db')).rejects.toThrow(/OPFS is not available/);
  });
});

describe('OpfsAdapter releasing the pool (sqlite-wasm 3.50+ pauseVfs)', () => {
  beforeEach(() => {
    pausable = true;
  });

  it('the static delete pauses a pool it installed, and the next open resumes it', async () => {
    const pool = seedPool('declarative-sqlite', 6, ['/gone.db', '/kept.db'], PausableFakePool) as PausableFakePool;
    await OpfsAdapter.deleteDatabase('gone.db');
    expect(pool.pauseVfs).toHaveBeenCalledTimes(1);
    expect(pool.paused).toBe(true);

    const adapter = new OpfsAdapter('kept.db');
    await adapter.open();
    expect(pool.unpauseVfs).toHaveBeenCalledTimes(1);
    expect(adapter.poolInfo().fileNames).toEqual(['/kept.db']);
    await adapter.close();
  });

  it('the static delete leaves the pool alone while a database is open through it', async () => {
    const pool = seedPool('declarative-sqlite', 6, ['/other.db'], PausableFakePool) as PausableFakePool;
    const adapter = new OpfsAdapter('open.db');
    await adapter.open();
    await OpfsAdapter.deleteDatabase('other.db');
    expect(pool.pauseVfs).not.toHaveBeenCalled();
    await adapter.close();
  });

  it('a failed open releases the pool it acquired instead of deleting it', async () => {
    const pool = seedPool('declarative-sqlite', 1, ['/keep.db'], PausableFakePool) as PausableFakePool;
    vi.spyOn(pool, 'addCapacity').mockRejectedValue(new Error('QuotaExceededError'));
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    await expect(new OpfsAdapter('late.db').open()).rejects.toThrow(/SAH pool is full/);
    expect(pool.pauseVfs).toHaveBeenCalledTimes(1);
    expect(pool.removeVfs).not.toHaveBeenCalled();
  });

  it('an instance delete after its own close resumes a pool the static delete paused', async () => {
    const pool = seedPool('declarative-sqlite', 6, ['/a.db', '/b.db'], PausableFakePool) as PausableFakePool;
    const adapter = new OpfsAdapter('a.db');
    await adapter.open();
    await adapter.close();
    await OpfsAdapter.deleteDatabase('b.db'); // pool known and not paused: this call did not acquire it
    expect(pool.pauseVfs).not.toHaveBeenCalled();
    pool.pauseVfs(); // e.g. paused by an earlier static delete
    await expect(adapter.deleteDatabase()).resolves.toBe(true);
    expect(pool.files.size).toBe(0);
  });
});

describe('OpfsAdapter.poolInfo', () => {
  it('needs an open adapter', () => {
    expect(() => new OpfsAdapter('closed.db').poolInfo()).toThrow(/open\(\)/);
  });
});
