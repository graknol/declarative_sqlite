import { loadSqlite3 } from './memory-adapter';
import { WasmAdapterBase } from './wasm';

/**
 * A database stored in the Origin Private File System through SQLite's
 * SAH-pool VFS. This is the backend to want: real file I/O, no image copying,
 * and it works on the main thread as well as in a worker without COOP/COEP
 * headers. It needs `createSyncAccessHandle`, which is Chrome/Edge 108+,
 * Firefox 111+ and Safari 17+; where that is missing, `open()` throws rather
 * than quietly producing a database that disappears on reload the way v2's
 * "IndexedDB backend" used to.
 */
export class OpfsAdapter extends WasmAdapterBase {
  constructor(
    private readonly name: string,
    private readonly options: { wasmDir?: string; poolName?: string } = {},
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
    if (typeof this.sqlite3.installOpfsSAHPoolVfs !== 'function') {
      throw new Error('OPFS SAH pool VFS is not present in this SQLite build');
    }
    const pool = await this.sqlite3.installOpfsSAHPoolVfs({ name: this.options.poolName ?? 'declarative-sqlite' });
    this.db = new pool.OpfsSAHPoolDb(`/${this.name}`);
  }
}
