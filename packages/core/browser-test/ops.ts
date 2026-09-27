// The operations a spec drives, shared by the page (main thread) and the
// worker so both contexts run the same library code against the same OPFS.
import { OpfsAdapter, type OpfsAdapterOptions } from '../src/adapters/opfs-adapter';
import { loadSqlite3 } from '../src/adapters/memory-adapter';

const adapters = new Map<string, OpfsAdapter>();

/** Errors cross postMessage/evaluate as plain data, keeping the cause's DOMException name. */
export interface OpResult {
  ok: boolean;
  value?: unknown;
  message?: string;
  causeName?: string;
}

async function run(work: () => Promise<unknown> | unknown): Promise<OpResult> {
  try {
    return { ok: true, value: await work() };
  } catch (error) {
    const e = error as Error & { cause?: { name?: string } };
    return { ok: false, message: e.message, causeName: e.cause?.name };
  }
}

function adapter(name: string): OpfsAdapter {
  const a = adapters.get(name);
  if (!a) throw new Error(`no adapter for ${name}`);
  return a;
}

export const ops = {
  open: (name: string, options: OpfsAdapterOptions = {}) =>
    run(async () => {
      const a = new OpfsAdapter(name, options);
      await a.open();
      adapters.set(name, a);
    }),
  exec: (name: string, sql: string) => run(() => adapter(name).exec(sql)),
  all: (name: string, sql: string) => run(() => adapter(name).all(sql)),
  close: (name: string) => run(() => adapter(name).close()),
  poolInfo: (name: string) => run(() => adapter(name).poolInfo()),
  deleteOwn: (name: string) => run(() => adapter(name).deleteDatabase()),
  deleteStatic: (name: string, options: OpfsAdapterOptions = {}) =>
    run(() => OpfsAdapter.deleteDatabase(name, options)),

  /**
   * Builds the state an app on the old library ends up in: the default pool at
   * its default 6 slots, all taken by databases, through sqlite-wasm directly.
   * Returns what creating one more file does there.
   */
  seedFullDefaultPool: () =>
    run(async () => {
      const sqlite3 = await loadSqlite3();
      const pool = await sqlite3.installOpfsSAHPoolVfs({ name: 'declarative-sqlite' });
      for (let i = 1; i <= 6; i++) {
        const db = new pool.OpfsSAHPoolDb(`/u${i}.db`);
        // Writing needs a journal slot too, so the last one stays empty.
        if (i < 6) db.exec('CREATE TABLE t(x); INSERT INTO t VALUES (1)');
        db.close();
      }
      let seventh = 'opened';
      try {
        new pool.OpfsSAHPoolDb('/u7.db').close();
      } catch (error) {
        seventh = String((error as Error).message);
      }
      return { capacity: pool.getCapacity(), fileCount: pool.getFileCount(), seventh };
    }),

  /** Whether this sqlite-wasm build can pause the pool (3.50+). Installs and removes a throwaway pool. */
  hasPause: () =>
    run(async () => {
      const sqlite3 = await loadSqlite3();
      const probe = await sqlite3.installOpfsSAHPoolVfs({ name: 'pause-probe' });
      const has = typeof probe.pauseVfs === 'function';
      await probe.removeVfs();
      return { has, libVersion: sqlite3.version.libVersion as string };
    }),
};

export type Op = keyof typeof ops;
