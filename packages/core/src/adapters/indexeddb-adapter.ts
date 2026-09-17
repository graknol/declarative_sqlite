import { loadSqlite3 } from './memory-adapter';
import type { RunResult } from './adapter';
import type { SqlValue } from '../types';
import { WasmAdapterBase } from './wasm';

const DB_NAME = 'declarative-sqlite';
const STORE = 'images';

function idbRequest<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('IndexedDB request failed'));
  });
}

async function openStore(): Promise<IDBDatabase> {
  const request = indexedDB.open(DB_NAME, 1);
  request.onupgradeneeded = () => {
    if (!request.result.objectStoreNames.contains(STORE)) request.result.createObjectStore(STORE);
  };
  return idbRequest(request);
}

/**
 * A database kept in memory whose image is persisted to IndexedDB. The official
 * SQLite WASM build has no IndexedDB VFS, so this is the only honest way to
 * persist where OPFS is unavailable: the whole image is exported after writes
 * settle (250 ms by default) and restored with `sqlite3_deserialize` on open.
 * Two consequences the caller must know: a crash can lose the last debounce
 * window, and the cost of a save grows with the database, so prefer OPFS when
 * the browser has it. Call `flush()` on `pagehide` to close the window.
 */
export class IndexedDbAdapter extends WasmAdapterBase {
  private saveTimer: ReturnType<typeof setTimeout> | undefined;
  private saving: Promise<void> | undefined;

  constructor(
    private readonly name: string,
    private readonly options: { wasmDir?: string; saveDebounceMs?: number } = {},
  ) {
    super();
  }

  /** Whether this environment has an IndexedDB implementation at all. Does not prove a save will succeed (quota, private browsing, etc.). */
  static isSupported(): boolean {
    return typeof indexedDB !== 'undefined';
  }

  override async open(): Promise<void> {
    if (this.db) return;
    if (!IndexedDbAdapter.isSupported()) throw new Error('IndexedDB is not available in this environment');
    this.sqlite3 = await loadSqlite3(this.options.wasmDir);
    this.db = new this.sqlite3.oo1.DB(':memory:');

    const store = await openStore();
    try {
      const bytes = await idbRequest<ArrayBuffer | undefined>(store.transaction(STORE, 'readonly').objectStore(STORE).get(this.name));
      if (bytes) this.deserialize(new Uint8Array(bytes));
    } finally {
      store.close();
    }
  }

  override async exec(sql: string): Promise<void> {
    await super.exec(sql);
    this.scheduleSave();
  }

  override async run(sql: string, params: SqlValue[] = []): Promise<RunResult> {
    const result = await super.run(sql, params);
    this.scheduleSave();
    return result;
  }

  override async close(): Promise<void> {
    await this.flush();
    await super.close();
  }

  /** Writes the pending image now. Call it from `pagehide`/`visibilitychange` so backgrounding the app cannot lose the last writes. */
  async flush(): Promise<void> {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = undefined;
    }
    await this.save();
  }

  private scheduleSave(): void {
    if (this.saveTimer) return;
    this.saveTimer = setTimeout(() => {
      this.saveTimer = undefined;
      void this.save().catch((error) => console.error('[declarative-sqlite] IndexedDB save failed', error));
    }, this.options.saveDebounceMs ?? 250);
  }

  private async save(): Promise<void> {
    if (!this.db) return;
    if (this.saving) {
      await this.saving;
      return;
    }
    const bytes = await this.export();
    this.saving = (async () => {
      const store = await openStore();
      try {
        const tx = store.transaction(STORE, 'readwrite');
        await idbRequest(tx.objectStore(STORE).put(bytes.buffer, this.name));
      } finally {
        store.close();
      }
    })().finally(() => {
      this.saving = undefined;
    });
    await this.saving;
  }

  private deserialize(bytes: Uint8Array): void {
    const capi = this.sqlite3.capi;
    const pointer = this.sqlite3.wasm.allocFromTypedArray(bytes);
    const rc = capi.sqlite3_deserialize(
      this.db.pointer,
      'main',
      pointer,
      bytes.byteLength,
      bytes.byteLength,
      capi.SQLITE_DESERIALIZE_FREEONCLOSE | capi.SQLITE_DESERIALIZE_RESIZEABLE,
    );
    this.db.checkRc(rc);
  }
}
