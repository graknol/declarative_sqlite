import { loadSqlite3 } from './memory-adapter';
import { WasmAdapterBase, type Sqlite3Module } from './wasm';

/** How an `OpfsAdapter` finds and sizes its SAH pool. Every field is optional; the defaults are what 3.0.x always did. */
export interface OpfsAdapterOptions {
  /** Where the `.wasm` file is served from, e.g. `/assets`. */
  wasmDir?: string;
  /** The SAH-pool VFS name, and so its OPFS directory (`.<poolName>`). Default `declarative-sqlite`. */
  poolName?: string;
  /**
   * How many slots the pool gets when it is created for the first time on this
   * origin. Ignored once the pool exists (it keeps what it has). Default
   * sqlite-wasm's own, 6.
   */
  initialCapacity?: number;
  /**
   * The fewest slots the pool must have after it is installed; it grows (never
   * shrinks) to this, and the open fails if it cannot. Independently, the
   * adapter tries to keep `fileCount + 2` slots (room for one more database
   * and a journal), but only warns if that fails.
   */
  minimumCapacity?: number;
}

/** Diagnostics for the SAH pool: slots allocated, slots in use, and the names in use. */
export interface OpfsPoolInfo {
  /** Slots allocated in `.<poolName>/.opaque`. */
  capacity: number;
  /** Slots holding a file (databases and any leftover journals). */
  fileCount: number;
  /** The pool paths of those files, e.g. `/app.db`, `/app.db-journal`. */
  fileNames: string[];
}

/**
 * The subset of sqlite-wasm's `OpfsSAHPoolUtil` this adapter uses. The pause
 * methods exist from sqlite-wasm 3.50 on; with an older build they are
 * missing and the pool stays held by the context that installed it.
 */
export interface OpfsSahPool {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  OpfsSAHPoolDb: new (filename: string) => any;
  getCapacity(): number;
  getFileCount(): number;
  getFileNames(): string[];
  reserveMinimumCapacity(min: number): Promise<number>;
  unlink(filename: string): boolean;
  pauseVfs?(): unknown;
  isPaused?(): boolean;
  unpauseVfs?(): Promise<unknown>;
}

const DEFAULT_POOL_NAME = 'declarative-sqlite';

/**
 * The files SQLite may keep next to a database. The SAH pool does not do WAL
 * (no shared memory), but unlinking a name that is not there is a no-op, so
 * all four are cleared to be sure no slot is left behind.
 */
const COMPANION_SUFFIXES = ['', '-journal', '-wal', '-shm'];

/**
 * How many `OpfsAdapter`s in this JS realm have each database open, per pool,
 * so a delete can refuse to pull a file out from under one. Counted, not a
 * set: two adapters may open the same database, and one closing must not
 * clear the other's mark.
 */
const openInRealm = new Map<string, Map<string, number>>();

/** Pools this library has installed in this realm (sqlite-wasm caches them per name). */
const installedPools = new Map<string, OpfsSahPool>();

/**
 * The key the pool stores a database under. The adapter opens `/${name}`, and
 * the VFS normalises that through `new URL(path, 'file://localhost/').pathname`;
 * `unlink` takes its argument as-is, so without the same normalisation a name
 * with a space in it would silently miss.
 */
function poolPath(name: string): string {
  return new URL(`/${name}`, 'file://localhost/').pathname;
}

function openCount(poolName: string, name: string): number {
  return openInRealm.get(poolName)?.get(poolPath(name)) ?? 0;
}

function anyOpen(poolName: string): boolean {
  const names = openInRealm.get(poolName);
  return names !== undefined && [...names.values()].some((n) => n > 0);
}

function assertNotOpenElsewhere(poolName: string, name: string): void {
  if (openCount(poolName, name) > 0) {
    throw new Error(`Cannot delete '${name}': it is open through another OpfsAdapter here. Close that adapter first.`);
  }
}

/**
 * Installs (or, if this realm already did, returns) the named SAH pool,
 * resuming it if this library paused it, and makes sure it has room.
 * Resolves the pool and whether this call acquired its access handles (a
 * first install or an unpause), so a caller that only borrowed the pool can
 * hand it back with `releasePool`.
 *
 * `retryFailedInstall` passes sqlite-wasm's `forceReinitIfPreviouslyFailed`.
 * Without it a failed install (e.g. another tab held the pool) is cached and
 * replayed for the rest of the realm's life. With it the install runs again,
 * and every failed install runs upstream's cleanup, `removeVfs()`, which
 * tries to delete the pool directory recursively; while another context holds
 * the pool, only the browser's OPFS locks stop that. So only `open()` retries.
 */
async function installPool(
  sqlite3: Sqlite3Module,
  options: OpfsAdapterOptions,
  retryFailedInstall: boolean,
): Promise<{ pool: OpfsSahPool; acquired: boolean }> {
  if (typeof sqlite3.installOpfsSAHPoolVfs !== 'function') {
    throw new Error('OPFS SAH pool VFS is not present in this SQLite build');
  }
  const poolName = options.poolName ?? DEFAULT_POOL_NAME;
  const known = installedPools.get(poolName);
  const pool = (await sqlite3.installOpfsSAHPoolVfs({
    name: poolName,
    ...(retryFailedInstall ? { forceReinitIfPreviouslyFailed: true } : {}),
    ...(options.initialCapacity !== undefined ? { initialCapacity: options.initialCapacity } : {}),
  })) as OpfsSahPool;
  let acquired = known !== pool;
  if (pool.isPaused?.() && pool.unpauseVfs) {
    await pool.unpauseVfs();
    acquired = true;
  }
  installedPools.set(poolName, pool);

  if (options.minimumCapacity !== undefined) {
    await pool.reserveMinimumCapacity(options.minimumCapacity);
  }
  // Best effort: an existing database must still open when OPFS refuses to grow
  // (quota, storage pressure); only a new file would then fail, as before.
  try {
    await pool.reserveMinimumCapacity(pool.getFileCount() + 2);
  } catch (error) {
    console.warn(`declarative-sqlite: could not add headroom to the OPFS pool '${poolName}'`, error);
  }
  return { pool, acquired };
}

/**
 * Pauses a pool this call acquired when nothing is open through it, which
 * releases its access handles so another tab or worker can install it. A
 * no-op on sqlite-wasm builds without `pauseVfs` (before 3.50).
 */
function releasePool(pool: OpfsSahPool, poolName: string, acquired: boolean): void {
  if (!acquired || anyOpen(poolName) || typeof pool.pauseVfs !== 'function') return;
  try {
    pool.pauseVfs();
  } catch (error) {
    // Refused because something outside this library has a file open in the pool.
    console.warn(`declarative-sqlite: could not release the OPFS pool '${poolName}'`, error);
  }
}

/** Unlinks a database and its companion files from the pool, freeing their slots. True if the database file itself was there. */
function unlinkFromPool(pool: OpfsSahPool, name: string): boolean {
  const main = poolPath(name);
  let existed = false;
  for (const suffix of COMPANION_SUFFIXES) {
    const removed = pool.unlink(main + suffix);
    if (suffix === '') existed = removed;
  }
  return existed;
}

/**
 * A database stored in the Origin Private File System through SQLite's
 * SAH-pool VFS. This is the backend to want: real file I/O, no image copying,
 * and no COOP/COEP headers. It needs `createSyncAccessHandle`, which browsers
 * expose only in dedicated workers (Chrome/Edge 108+, Firefox 111+, Safari
 * 17+), so open it in a worker. Where that is missing, `open()` throws rather
 * than quietly producing a database that disappears on reload the way v2's
 * "IndexedDB backend" used to.
 *
 * The pool keeps every database in a fixed set of pre-allocated slots with
 * random file names, so a database can only be removed through the pool
 * (`deleteDatabase`), never by deleting a file at the OPFS root. The pool
 * holds exclusive access handles on all its slots, so only one JS realm (tab
 * or worker) per origin can have it installed at a time.
 */
export class OpfsAdapter extends WasmAdapterBase {
  private pool: OpfsSahPool | undefined;

  constructor(
    private readonly name: string,
    private readonly options: OpfsAdapterOptions = {},
  ) {
    super();
  }

  /** Whether this environment can host the SAH-pool VFS at all. Cheap and synchronous; `open()` is the real proof. */
  static isSupported(): boolean {
    return (
      typeof navigator !== 'undefined' &&
      typeof navigator.storage?.getDirectory === 'function' &&
      typeof FileSystemFileHandle !== 'undefined' &&
      'createSyncAccessHandle' in FileSystemFileHandle.prototype
    );
  }

  /**
   * Deletes a database from the pool without an open adapter, e.g. a previous
   * user's database on a shared device. Resolves `true` if it existed.
   *
   * Call it from the context (tab or worker) that owns your databases: the
   * pool allows one holder per origin. If this call had to install the pool
   * and nothing is open through it afterwards, it pauses the pool again
   * (sqlite-wasm 3.50+), so the context that owns the databases can still
   * open it. On older sqlite-wasm builds the pool stays held here until this
   * context ends.
   *
   * Throws if the database is open through an `OpfsAdapter` in this context.
   * If another context holds the pool, rejects with an error whose `cause`
   * is the browser's `DOMException` (`NoModificationAllowedError`) and
   * deletes nothing; sqlite-wasm caches that failure, so a later call from
   * this context rejects the same way.
   */
  static async deleteDatabase(name: string, options: OpfsAdapterOptions = {}): Promise<boolean> {
    if (!OpfsAdapter.isSupported()) {
      throw new Error('OPFS is not available in this environment (no createSyncAccessHandle)');
    }
    const poolName = options.poolName ?? DEFAULT_POOL_NAME;
    assertNotOpenElsewhere(poolName, name);
    const sqlite3 = await loadSqlite3(options.wasmDir);
    let installed: { pool: OpfsSahPool; acquired: boolean };
    try {
      installed = await installPool(sqlite3, options, false);
    } catch (cause) {
      const held = (cause as { name?: unknown } | null)?.name === 'NoModificationAllowedError';
      const error = new Error(
        held
          ? `Could not delete '${name}': another tab or worker holds the OPFS pool '${poolName}'`
          : `Could not delete '${name}': the OPFS pool '${poolName}' failed to open`,
      );
      throw Object.assign(error, { cause });
    }
    try {
      return unlinkFromPool(installed.pool, name);
    } finally {
      releasePool(installed.pool, poolName, installed.acquired);
    }
  }

  /**
   * Opens (creating if necessary) the named database inside an OPFS SAH-pool
   * VFS. Refuses outright when OPFS or the pool VFS is unavailable instead of
   * falling back to an in-memory database, so a caller that asked for
   * persistence and did not get it finds out immediately rather than after
   * the next reload has already lost their data.
   */
  override async open(): Promise<void> {
    if (this.db) return;
    if (!OpfsAdapter.isSupported()) {
      throw new Error('OPFS is not available in this environment (no createSyncAccessHandle)');
    }
    this.sqlite3 = await loadSqlite3(this.options.wasmDir);
    const { pool, acquired } = await installPool(this.sqlite3, this.options, true);
    try {
      this.db = new pool.OpfsSAHPoolDb(`/${this.name}`);
    } catch (error) {
      // Never `pool.removeVfs()` here: it deletes the pool's whole directory, i.e.
      // every other database in it. Pausing releases the handles instead, so a
      // fallback backend or another context is not blocked.
      releasePool(pool, this.poolName, acquired);
      throw error;
    }
    this.pool = pool;
    this.markOpen(+1);
  }

  override async close(): Promise<void> {
    const wasOpen = this.db !== undefined;
    await super.close();
    if (wasOpen) this.markOpen(-1);
  }

  /**
   * Deletes a database from this adapter's pool and frees its slots (and any
   * journal's). With no name, or this adapter's own name, the adapter is
   * closed first, and a later `open()` starts an empty database. The
   * database must not be open through another adapter in this context, or
   * this throws. Resolves `true` if the database existed. Like the static
   * method, call it from the context that owns the databases.
   */
  async deleteDatabase(name: string = this.name): Promise<boolean> {
    if (poolPath(name) === poolPath(this.name)) await this.close();
    if (!this.pool) return OpfsAdapter.deleteDatabase(name, this.options);
    assertNotOpenElsewhere(this.poolName, name);
    if (this.pool.isPaused?.()) return OpfsAdapter.deleteDatabase(name, this.options);
    return unlinkFromPool(this.pool, name);
  }

  /** Capacity and contents of the pool, for diagnostics. Needs the adapter to be open. */
  poolInfo(): OpfsPoolInfo {
    if (!this.pool || !this.db) throw new Error('The OPFS pool is not open. Call open() first.');
    return {
      capacity: this.pool.getCapacity(),
      fileCount: this.pool.getFileCount(),
      fileNames: this.pool.getFileNames(),
    };
  }

  private get poolName(): string {
    return this.options.poolName ?? DEFAULT_POOL_NAME;
  }

  private markOpen(delta: 1 | -1): void {
    const key = poolPath(this.name);
    let names = openInRealm.get(this.poolName);
    if (!names) openInRealm.set(this.poolName, (names = new Map()));
    const next = (names.get(key) ?? 0) + delta;
    if (next > 0) names.set(key, next);
    else names.delete(key);
  }
}
