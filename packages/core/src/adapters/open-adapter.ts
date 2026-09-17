import type { SQLiteAdapter } from './adapter';
import { IndexedDbAdapter } from './indexeddb-adapter';
import { MemoryAdapter } from './memory-adapter';
import { OpfsAdapter } from './opfs-adapter';

/** Which concrete adapter backed the database `openAdapter` returned. */
export type AdapterBackend = 'opfs' | 'indexeddb' | 'memory';

/** Injectable capability probes, so the selection logic is testable in Node. */
export interface AdapterCapabilities {
  opfs(): boolean;
  indexedDb(): boolean;
}

/** What to open and how hard to try before giving up on a persistent backend. */
export interface OpenAdapterOptions {
  /** The database file name, e.g. `apply-work.db`. */
  name: string;
  /** `auto` (default) probes; naming a backend skips probing and fails loudly if it cannot open. */
  backend?: AdapterBackend | 'auto';
  /** Where the `.wasm` file is served from, e.g. `/assets`. */
  wasmDir?: string;
  /** How long to wait for OPFS before falling back. Safari has been seen to hang here; default 5000 ms. */
  opfsTimeoutMs?: number;
  capabilities?: AdapterCapabilities;
}

/** The result of `openAdapter`: the live adapter, which backend it actually landed on, and anything the caller should tell the user. */
export interface OpenedAdapter {
  adapter: SQLiteAdapter;
  backend: AdapterBackend;
  /** Anything the app should log or show: a fallback that happened, or that this session is not persistent. */
  warnings: string[];
}

const defaultCapabilities: AdapterCapabilities = {
  opfs: () => OpfsAdapter.isSupported(),
  indexedDb: () => IndexedDbAdapter.isSupported(),
};

async function withTimeout<T>(work: Promise<T>, ms: number, message: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      work,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error(message)), ms);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

/**
 * Opens the best storage this browser can actually give: OPFS when it has
 * `createSyncAccessHandle`, otherwise an IndexedDB-persisted image, otherwise
 * memory. OPFS is opened behind a timeout because a Safari that reports support
 * has been seen to hang forever on the first handle. The result says which
 * backend won and what went wrong on the way, so the app can log it and warn the
 * user when the session is not persistent.
 */
export async function openAdapter(options: OpenAdapterOptions): Promise<OpenedAdapter> {
  const capabilities = options.capabilities ?? defaultCapabilities;
  const warnings: string[] = [];
  const requested = options.backend ?? 'auto';

  if (requested !== 'auto') {
    const adapter =
      requested === 'opfs'
        ? new OpfsAdapter(options.name, options.wasmDir ? { wasmDir: options.wasmDir } : {})
        : requested === 'indexeddb'
          ? new IndexedDbAdapter(options.name, options.wasmDir ? { wasmDir: options.wasmDir } : {})
          : new MemoryAdapter(options.wasmDir ? { wasmDir: options.wasmDir } : {});
    await adapter.open();
    return { adapter, backend: requested, warnings };
  }

  if (capabilities.opfs()) {
    const adapter = new OpfsAdapter(options.name, options.wasmDir ? { wasmDir: options.wasmDir } : {});
    try {
      await withTimeout(adapter.open(), options.opfsTimeoutMs ?? 5000, 'OPFS did not open in time');
      return { adapter, backend: 'opfs', warnings };
    } catch (error) {
      warnings.push(`OPFS unavailable (${error instanceof Error ? error.message : String(error)}); falling back`);
      await adapter.close().catch(() => undefined);
    }
  }

  if (capabilities.indexedDb()) {
    const adapter = new IndexedDbAdapter(options.name, options.wasmDir ? { wasmDir: options.wasmDir } : {});
    try {
      await adapter.open();
      return { adapter, backend: 'indexeddb', warnings };
    } catch (error) {
      warnings.push(`IndexedDB unavailable (${error instanceof Error ? error.message : String(error)}); falling back`);
    }
  }

  warnings.push('Storage is not persistent: this session runs in memory and everything is lost on reload');
  const adapter = new MemoryAdapter(options.wasmDir ? { wasmDir: options.wasmDir } : {});
  await adapter.open();
  return { adapter, backend: 'memory', warnings };
}
