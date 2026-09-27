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
   * The fewest slots the pool should have after it is installed. The pool
   * grows (it never shrinks) to `max(minimumCapacity, fileCount + 2)`, so
   * there is always room for one more database plus its journal. Default 0:
   * only that headroom rule applies.
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

/** The subset of sqlite-wasm's `OpfsSAHPoolUtil` this adapter uses. */
export interface OpfsSahPool {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  OpfsSAHPoolDb: new (filename: string) => any;
  getCapacity(): number;
  getFileCount(): number;
  getFileNames(): string[];
  reserveMinimumCapacity(min: number): Promise<number>;
  unlink(filename: string): boolean;
}

const DEFAULT_POOL_NAME = 'declarative-sqlite';

/**
 * The files SQLite may keep next to a database. The SAH pool does not do WAL
 * (no shared memory), but unlinking a name that is not there is a no-op, so
 * all four are cleared to be sure no slot is left behind.
 */
const COMPANION_SUFFIXES = ['', '-journal', '-wal', '-shm'];

/** Databases open through an `OpfsAdapter` in this JS realm, per pool, so a delete can refuse to pull a file out from under one. */
const openInRealm = new Map<string, Set<string>>();

/**
 * The key the pool stores a database under. The adapter opens `/${name}`, and
 * the VFS normalises that through `new URL(path, 'file://localhost/').pathname`;
 * `unlink` takes its argument as-is, so without the same normalisation a name
 * with a space in it would silently miss.
 */
function poolPath(name: string): string {
  return new URL(`/${name}`, 'file://localhost/').pathname;
}

/**
 * Installs (or, if this realm already did, returns) the named SAH pool and
 * makes sure it has headroom. `installOpfsSAHPoolVfs` caches the pool per
 * name, so every adapter and the static helper share one instance and one set
 * of access handles. `forceReinitIfPreviouslyFailed` lets a later call retry
 * after, say, another tab held the pool, instead of replaying the old
 * rejection for the rest of the realm's life.
 */
async function installPool(sqlite3: Sqlite3Module, options: OpfsAdapterOptions): Promise<OpfsSahPool> {
  if (typeof sqlite3.installOpfsSAHPoolVfs !== 'function') {
    throw new Error('OPFS SAH pool VFS is not present in this SQLite build');
  }
  const pool = (await sqlite3.installOpfsSAHPoolVfs({
    name: options.poolName ?? DEFAULT_POOL_NAME,
    forceReinitIfPreviouslyFailed: true,
    ...(options.initialCapacity !== undefined ? { initialCapacity: options.initialCapacity } : {}),
  })) as OpfsSahPool;
  await pool.reserveMinimumCapacity(Math.max(options.minimumCapacity ?? 0, pool.getFileCount() + 2));
  return pool;
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

function assertNotOpenElsewhere(poolName: string, name: string): void {
  if (openInRealm.get(poolName)?.has(poolPath(name))) {
    throw new Error(`Cannot delete '${name}': it is open through another OpfsAdapter here. Close that adapter first.`);
  }
}

/**
 * A database stored in the Origin Private File System through SQLite's
 * SAH-pool VFS. This is the backend to want: real file I/O, no image copying,
 * and it works on the main thread as well as in a worker without COOP/COEP
 * headers. It needs `createSyncAccessHandle`, which is Chrome/Edge 108+,
 * Firefox 111+ and Safari 17+; where that is missing, `open()` throws rather
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
   * user's database on a shared device. Installs the pool in this realm if
   * nothing has yet; it then stays installed, holding its access handles,
   * until the realm ends, so call this from the same tab or worker that opens
   * your databases. Resolves `true` if the database existed.
   *
   * Throws if that database is open through an `OpfsAdapter` in this realm
   * (close it, or use the instance method). If another tab or worker holds
   * the pool, rejects with an error whose `cause` is the browser's
   * `DOMException` (usually `NoModificationAllowedError`); nothing is deleted.
   */
  static async deleteDatabase(name: string, options: OpfsAdapterOptions = {}): Promise<boolean> {
    if (!OpfsAdapter.isSupported()) {
      throw new Error('OPFS is not available in this environment (no createSyncAccessHandle)');
    }
    const poolName = options.poolName ?? DEFAULT_POOL_NAME;
    assertNotOpenElsewhere(poolName, name);
    const sqlite3 = await loadSqlite3(options.wasmDir);
    let pool: OpfsSahPool;
    try {
      pool = await installPool(sqlite3, options);
    } catch (cause) {
      const error = new Error(
        `Could not open the OPFS pool '${poolName}' to delete '${name}'; another tab or worker may be holding it`,
      );
      throw Object.assign(error, { cause });
    }
    return unlinkFromPool(pool, name);
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
    const pool = await installPool(this.sqlite3, this.options);
    // If constructing the database throws, the pool stays installed on purpose:
    // it is cached per realm and the next open() reuses it. `pool.removeVfs()`
    // would delete the pool's whole directory, i.e. every other database in it.
    this.db = new pool.OpfsSAHPoolDb(`/${this.name}`);
    this.pool = pool;
    this.trackOpen(true);
  }

  override async close(): Promise<void> {
    await super.close();
    this.trackOpen(false);
  }

  /**
   * Deletes a database from this adapter's pool and frees its slots (and any
   * journal's). With no name, or this adapter's own name, the adapter is
   * closed first, and a later `open()` starts an empty database. Another name
   * must not be open through a different adapter in this realm, or this
   * throws. Resolves `true` if the database existed.
   */
  async deleteDatabase(name: string = this.name): Promise<boolean> {
    if (poolPath(name) === poolPath(this.name)) await this.close();
    if (!this.pool) return OpfsAdapter.deleteDatabase(name, this.options);
    assertNotOpenElsewhere(this.options.poolName ?? DEFAULT_POOL_NAME, name);
    return unlinkFromPool(this.pool, name);
  }

  /** Capacity and contents of the pool, for diagnostics. Needs the adapter to have been opened once. */
  poolInfo(): OpfsPoolInfo {
    if (!this.pool) throw new Error('The OPFS pool is not installed. Call open() first.');
    return {
      capacity: this.pool.getCapacity(),
      fileCount: this.pool.getFileCount(),
      fileNames: this.pool.getFileNames(),
    };
  }

  private trackOpen(open: boolean): void {
    const poolName = this.options.poolName ?? DEFAULT_POOL_NAME;
    const key = poolPath(this.name);
    let names = openInRealm.get(poolName);
    if (open) {
      if (!names) openInRealm.set(poolName, (names = new Set()));
      names.add(key);
    } else {
      names?.delete(key);
    }
  }
}
