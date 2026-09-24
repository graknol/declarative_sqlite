# declarative-sqlite v3 — the sync data layer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `packages/core` (npm `declarative-sqlite`) from scratch as a sync data layer whose primitives — server-truth tables, outbox, draft store, overlay, cursor/pull/push/tick services and non-brittle live queries — are enforced by the API instead of by convention, with no HLC and no client-side conflict resolution.

**Architecture:** Five layers with a one-way dependency direction `react → sync → live → db → adapters`, plus `schema/migration → db`. Nothing above `db` executes SQL. Every write goes through one path that records `(table, rowKey, scopeValues)` on the transaction; on commit an invalidation bus emits one event, live queries whose declared reads intersect that event re-run, pass their rows through the overlay (pending outbox columns win) and the draft holds, diff against the previous snapshot and emit only when something actually changed. A `MemoryAdapter` over the official SQLite WASM build makes the whole stack — including every race in the spec — a vitest unit test with no browser.

**Tech Stack:** TypeScript 5 (strict), `@sqlite.org/sqlite-wasm` 3.47, vitest 1, tsup 8 (ESM + CJS, two entries), React 18 as an optional peer for the `declarative-sqlite/react` subpath. No RxJS. No runtime dependency other than the SQLite WASM build.

**Spec:** `docs/superpowers/specs/2026-09-17-v3-sync-data-layer-design.md` (the authority).
Consumer requirements: `PLAN - Sync v3 without HLC.md` Part A + the Phase 3 framing (owner's Desktop, folder `jan reidar apply work`).
Wire contract the transport types mirror: `C:\repos\Apply AS\IFS\CLOUD\workspace\cwork\docs\sync-v3\wire-format.md`.

## Global Constraints

- **Package manager: npm.** `packages/core/package-lock.json` is the lockfile. Every command in this plan runs from `C:\repos\Apply AS\declarative_sqlite\packages\core`. Never run `pnpm install` there.
- **TypeScript strict.** `tsconfig.json` keeps every flag v2 had: `strict`, `noUnusedLocals`, `noUnusedParameters`, `noImplicitReturns`, `noFallthroughCasesInSwitch`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `noPropertyAccessFromIndexSignature`.
- **ESM + CJS via tsup**, two entries: `src/index.ts` → `dist/index.{js,cjs,d.ts}` and `src/react/index.ts` → `dist/react/index.{js,cjs,d.ts}`.
- **vitest** is the only test runner. Node environment by default; React tests opt into `happy-dom` with a `/** @vitest-environment happy-dom */` docblock.
- **No RxJS.** Subscriptions are plain callbacks that return an unsubscribe function.
- **No HLC, no LWW, no dirty rows, no `__hlc` columns, no `forceOverwrite`, no `bulkLoad` merge, no `files/`, no fluent WHERE builder.** The server decides; the client records and overlays.
- **Synced tables are writable only through the capability object.** `.synced()` tables expose no write methods on `db.tables`, and the `ServerWriteCapability` is minted inside `sync/` and never exported from `src/index.ts`.
- **Every public API carries a one-paragraph JSDoc** (what it does, when to call it, what it guarantees). Enforced by review.
- **Spec §11's three open questions use these defaults** (the owner has not ruled; revisit if he does):
  - (a) The React binding ships as the subpath export `declarative-sqlite/react`, with `react` as an **optional peer dependency `>=18`**. No separate npm package.
  - (b) Reads are SQL strings. Only `db.tables.<name>` gets a minimal typed CRUD builder (insert / update / upsert / delete / get by row key).
  - (c) `.synced()` scope columns are **trusted from the schema**. An optional `validateScopes(schema, allowList)` hook exists and is **off by default**; the app may call it once at startup with the server's `IS_SCOPE` list.
- **Wire compatibility:** `RowsPage`, `PushBatch`, `PushResult` mirror `wire-format.md` (camelCase, `data` nested, uppercase IFS column names on the wire, lowercase locally). Limits the library enforces locally before the server can: `batchId` ≤ 36 characters, one JSON-encoded scalar ≤ 4000 characters, ≤ 500 changes per batch, ≤ 4 scope pairs, no comma inside a scope value.
- **Version `3.0.0-alpha.1`.** The published 2.x line is untouched; v2 source lives in git history only — Task 1 deletes `packages/core/src` now that the reference reading behind this plan is done.
- **Commits: one per task**, and every message ends with the trailer:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  ```
- **Norwegian is the app's problem, not the library's.** Every string the library produces (errors, statuses) is English; the app translates.

## File Structure

```
packages/core
  package.json            rewritten: 3.0.0-alpha.1, two exports, react optional peer
  tsup.config.ts          new: two entries, esm+cjs+dts
  tsconfig.json           same flags, include src
  vitest.config.ts        node environment, alias for the sqlite-wasm node build
  src/
    index.ts              root entry: schema, migration, adapters, db, live, sync, testing
    types.ts              SqlValue, Row, ScopeValues
    schema/
      types.ts            ColumnDef, KeyDef, SyncedDef, TableDef, Schema
      column-builder.ts   text/integer/real/date/guid builders: notNull, maxLength
      table-builder.ts    columns, keys, system columns, .synced()
      schema-builder.ts   schema.table(...), library tables, build()
      scopes.ts           formatScope, parseScope, validateScopes
    migration/
      introspect.ts       sqlite_master + PRAGMA → live Schema
      diff.ts             declared vs live → MigrationDiff (additive only)
      generate.ts         MigrationDiff → MigrationOperation[]
      migrate.ts          plan / auto / off, allowRecreate guard
    adapters/
      adapter.ts          SQLiteAdapter, RunResult
      memory-adapter.ts   WASM in-memory (node + browser)
      wasm.ts             loadSqlite3(), WasmAdapterBase
      opfs-adapter.ts     OPFS SAH-pool VFS
      indexeddb-adapter.ts in-memory image + debounced IndexedDB snapshot
      open-adapter.ts     openAdapter({ backend: 'auto' | ... }) with the Safari timeout
    db/
      sql.ts              identifier quoting, value coercion, row helpers
      invalidation-bus.ts InvalidationEvent, subscribe / emit
      transaction.ts      Transaction: query / execute / tables / markWritten
      tables.ts           typed CRUD per table; synced tables read-only
      server-truth.ts     ServerWriteCapability + ServerWriter (not exported)
      database.ts         Database.open, query, transaction, live, close
    live/
      diff-rows.ts        snapshot diff with row identity preservation
      live-query.ts       LiveQuery: subscribe / snapshot / refresh / close
      registry.ts         invalidation → matching queries → one re-run
    sync/
      wire.ts             wire types, name mapping, scalar encode/decode, limits
      transport.ts        SyncTransport interface
      outbox.ts           change groups, statuses, counts, purge
      overlay.ts          pending/sending columns win
      drafts.ts           focus lifecycle, holds, tombstones, exit paths
      cursor-store.ts     per (table, scope) cursor
      pull-applier.ts     one transaction per page, holds honoured, seq guard
      pull-service.ts     paging, window rule, open scopes
      push-service.ts     debounce, groups intact, idempotent batch, backoff
      tick-coalescer.ts   ~1.5 s coalescing, scope filtering
      runtime.ts          createSyncRuntime: wires all of the above onto a Database
      scenarios.test.ts   the named races from spec §9
    testing/
      fake-transport.ts   scripted server for tests (exported)
      test-db.ts          openTestDb(schema) helper (exported)
    react/
      index.ts            subpath entry
      provider.tsx        SyncProvider: runtime context + exit paths
      use-live-query.ts   useSyncExternalStore over LiveQuery
      use-draft-field.ts  the only way an editable field is written
      use-outbox-counts.ts
      use-sync-status.ts
  examples/browser-smoke/ index.html + main.ts: the manual OPFS / IndexedDB check
  CHANGELOG.md            3.0.0-alpha.1
  README.md               rewritten around the five layers
  MIGRATION-v2-to-v3.md   Apply Work migration guide
```

Tests are co-located: `src/<area>/<file>.test.ts` beside the file they exercise. `tsconfig.json` excludes `**/*.test.ts` from the build.

---

### Task 1: Clear the decks and stand up the v3 skeleton

v2's `src/` is reference material that has already been read; it now goes away so nothing can be copied by accident. This task leaves a package that installs, type-checks, tests and builds — with one module in it.

**Files:**
- Delete: everything under `packages/core/src/`
- Delete: `packages/core/BROWSER_MIGRATION.md`, `COMLINK_INTEGRATION.md`, `PERSISTENCE.md`, `PERSISTENCE_IMPLEMENTATION.md`, `bulkload-logging.txt`, `docs/`
- Modify: `packages/core/package.json`
- Modify: `packages/core/vitest.config.ts`
- Modify: `packages/core/tsconfig.json`
- Create: `packages/core/tsup.config.ts`
- Create: `packages/core/src/index.ts`
- Test: `packages/core/src/index.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: `export const VERSION: string` from `src/index.ts`; the npm scripts `test`, `typecheck`, `build`; the vitest alias `@sqlite.org/sqlite-wasm/sqlite-wasm/jswasm/sqlite3-node.mjs` that later tasks rely on to open SQLite in Node.

- [ ] **Step 1: Delete v2 source and its stray docs**

```bash
cd "C:/repos/Apply AS/declarative_sqlite/packages/core"
git rm -r --quiet src docs BROWSER_MIGRATION.md COMLINK_INTEGRATION.md PERSISTENCE.md PERSISTENCE_IMPLEMENTATION.md bulkload-logging.txt
mkdir -p src
```

- [ ] **Step 2: Rewrite `package.json`**

```json
{
  "name": "declarative-sqlite",
  "version": "3.0.0-alpha.1",
  "description": "Offline-first sync data layer for SQLite in the browser: declarative schema, automatic migration, live queries, outbox, drafts and cursor-based sync",
  "type": "module",
  "main": "./dist/index.cjs",
  "module": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js",
      "require": "./dist/index.cjs"
    },
    "./react": {
      "types": "./dist/react/index.d.ts",
      "import": "./dist/react/index.js",
      "require": "./dist/react/index.cjs"
    }
  },
  "files": ["dist", "README.md", "CHANGELOG.md", "MIGRATION-v2-to-v3.md", "LICENSE"],
  "scripts": {
    "build": "tsup",
    "dev": "tsup --watch",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc --noEmit",
    "prepublishOnly": "npm run typecheck && npm test && npm run build"
  },
  "keywords": ["sqlite", "offline-first", "sync", "outbox", "live-query", "pwa", "capacitor", "typescript"],
  "author": "graknol",
  "license": "MIT",
  "repository": { "type": "git", "url": "https://github.com/graknol/declarative_sqlite.git", "directory": "packages/core" },
  "dependencies": {
    "@sqlite.org/sqlite-wasm": "^3.47.2-build1"
  },
  "peerDependencies": {
    "react": ">=18"
  },
  "peerDependenciesMeta": {
    "react": { "optional": true }
  },
  "devDependencies": {
    "@testing-library/react": "^16.0.1",
    "@types/react": "^18.3.12",
    "@vitest/coverage-v8": "^1.0.0",
    "happy-dom": "^20.0.0",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "tsup": "^8.0.1",
    "typescript": "^5.3.0",
    "vitest": "^1.0.0"
  }
}
```

- [ ] **Step 3: Replace `vitest.config.ts` and add `tsup.config.ts`**

`vitest.config.ts` — node environment (the SQLite WASM node build is loaded directly; happy-dom is opted into per React test file):

```ts
import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    coverage: { provider: 'v8', reporter: ['text'], exclude: ['dist/', '**/*.test.ts'] },
  },
  resolve: {
    alias: {
      '@sqlite.org/sqlite-wasm/sqlite-wasm/jswasm/sqlite3-node.mjs': path.resolve(
        __dirname,
        'node_modules/@sqlite.org/sqlite-wasm/sqlite-wasm/jswasm/sqlite3-node.mjs',
      ),
    },
  },
});
```

`tsup.config.ts`:

```ts
import { defineConfig } from 'tsup';

export default defineConfig({
  entry: { index: 'src/index.ts', 'react/index': 'src/react/index.ts' },
  format: ['esm', 'cjs'],
  dts: true,
  clean: true,
  sourcemap: true,
  treeshake: true,
  external: ['react', '@sqlite.org/sqlite-wasm'],
});
```

Leave `tsconfig.json` as it is except for adding `"jsx": "react-jsx"` to `compilerOptions` (the React entry has a `.tsx` file) and keeping `"exclude": ["node_modules", "dist", "**/*.test.ts"]`.

- [ ] **Step 4: Write the failing test**

`src/index.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { VERSION } from './index';

describe('declarative-sqlite', () => {
  it('reports the v3 alpha version', () => {
    expect(VERSION).toBe('3.0.0-alpha.1');
  });
});
```

- [ ] **Step 5: Run it and watch it fail**

Run: `npm test -- src/index.test.ts`
Expected: FAIL — `Failed to resolve import "./index"`.

- [ ] **Step 6: Create the entry point**

`src/index.ts`:

```ts
/**
 * declarative-sqlite — an offline-first sync data layer for SQLite in the browser.
 * The package is built in layers: `adapters` (raw SQLite), `db` (one write path and
 * an invalidation bus), `live` (queries that re-run only for their own scope),
 * `sync` (outbox, drafts, cursors, pull and push) and the `declarative-sqlite/react`
 * subpath. Import `Database` and a schema to get started; see README.md.
 */
export const VERSION = '3.0.0-alpha.1';
```

- [ ] **Step 7: Install, then run test, typecheck and build**

```bash
cd "C:/repos/Apply AS/declarative_sqlite/packages/core"
npm install
npm test
npm run typecheck
npm run build
```
Expected: 1 test passes, no type errors, `dist/index.js` and `dist/index.cjs` exist. The `react/index` entry does not exist yet — comment it out in `tsup.config.ts` with `// re-enabled in Task 33` until Task 33 adds the file, so `npm run build` stays green.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'MSG'
chore!: delete v2 source and stand up the v3 package skeleton

v2 lives in git history only; v3 is a full rewrite per
docs/superpowers/specs/2026-09-17-v3-sync-data-layer-design.md.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: `SQLiteAdapter` interface and `MemoryAdapter`

Everything above this task is tested in Node against a real SQLite. The adapter interface is deliberately statement-free: the `db` layer builds SQL strings and binds arrays, so an adapter only has to answer `all`, `get`, `run` and `exec`. Transactions are driven from `db` (`BEGIN IMMEDIATE` / `COMMIT` / `ROLLBACK`) because the single write path owns them.

**Files:**
- Create: `packages/core/src/types.ts`
- Create: `packages/core/src/adapters/adapter.ts`
- Create: `packages/core/src/adapters/memory-adapter.ts`
- Test: `packages/core/src/adapters/memory-adapter.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `type SqlValue = string | number | null | Uint8Array`
  - `type Row = Record<string, SqlValue>`
  - `type ScopeValues = Record<string, string | number>`
  - `interface RunResult { changes: number; lastInsertRowid: number }`
  - `interface SQLiteAdapter { open(): Promise<void>; close(): Promise<void>; exec(sql: string): Promise<void>; all<T>(sql: string, params?: SqlValue[]): Promise<T[]>; get<T>(sql: string, params?: SqlValue[]): Promise<T | undefined>; run(sql: string, params?: SqlValue[]): Promise<RunResult>; isOpen(): boolean; export(): Promise<Uint8Array> }`
  - `class MemoryAdapter implements SQLiteAdapter { constructor(); }`

- [ ] **Step 1: Write the failing test**

`src/adapters/memory-adapter.test.ts`:

```ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { MemoryAdapter } from './memory-adapter';

describe('MemoryAdapter', () => {
  let adapter: MemoryAdapter;

  beforeEach(async () => {
    adapter = new MemoryAdapter();
    await adapter.open();
  });

  afterEach(async () => {
    await adapter.close();
  });

  it('executes DDL and reports open state', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT, b INTEGER)');
    expect(adapter.isOpen()).toBe(true);
  });

  it('runs a parameterised insert and reads it back', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT, b INTEGER)');
    const result = await adapter.run('INSERT INTO t (a, b) VALUES (?, ?)', ['x', 42]);
    expect(result.changes).toBe(1);

    const rows = await adapter.all<{ a: string; b: number }>('SELECT a, b FROM t WHERE b = ?', [42]);
    expect(rows).toEqual([{ a: 'x', b: 42 }]);
  });

  it('returns undefined from get when nothing matches', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT)');
    expect(await adapter.get('SELECT a FROM t WHERE a = ?', ['nope'])).toBeUndefined();
  });

  it('binds null and reads it back as null', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT)');
    await adapter.run('INSERT INTO t (a) VALUES (?)', [null]);
    expect(await adapter.get<{ a: string | null }>('SELECT a FROM t')).toEqual({ a: null });
  });

  it('rolls back an explicit transaction', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT)');
    await adapter.exec('BEGIN IMMEDIATE');
    await adapter.run('INSERT INTO t (a) VALUES (?)', ['x']);
    await adapter.exec('ROLLBACK');
    expect(await adapter.all('SELECT a FROM t')).toEqual([]);
  });

  it('throws when used before open', async () => {
    const closed = new MemoryAdapter();
    await expect(closed.exec('SELECT 1')).rejects.toThrow(/not open/i);
  });

  it('exports the database image', async () => {
    await adapter.exec('CREATE TABLE t (a TEXT)');
    const bytes = await adapter.export();
    expect(bytes.byteLength).toBeGreaterThan(0);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/adapters/memory-adapter.test.ts`
Expected: FAIL — `Failed to resolve import "./memory-adapter"`.

- [ ] **Step 3: Write `src/types.ts` and `src/adapters/adapter.ts`**

`src/types.ts`:

```ts
/** A value SQLite can store and bind: text, number, null or a byte array. Booleans are coerced to 0/1 before they reach this type. */
export type SqlValue = string | number | null | Uint8Array;

/** One database row as a plain object, keyed by lowercase column name. Every read in the library produces rows of this shape before typing is layered on top. */
export type Row = Record<string, SqlValue>;

/** The values of a synced table's scope columns for one row, e.g. `{ wo_no: 3188 }`. Used to decide which live queries an invalidation touches and which cursor a pull belongs to. */
export type ScopeValues = Record<string, string | number>;
```

`src/adapters/adapter.ts`:

```ts
import type { SqlValue } from '../types';

/** What a write statement reports back: how many rows it changed and the rowid SQLite assigned to the last insert. */
export interface RunResult {
  changes: number;
  lastInsertRowid: number;
}

/**
 * The whole surface the library needs from a SQLite build. It is deliberately
 * statement-free — callers pass a SQL string and a parameter array — so that an
 * adapter can be a WASM database, a native bridge or a test double without
 * modelling prepared statements. Transactions are NOT part of this interface:
 * the `db` layer issues `BEGIN IMMEDIATE`/`COMMIT`/`ROLLBACK` through `exec`
 * so that the single write path owns transaction boundaries.
 */
export interface SQLiteAdapter {
  open(): Promise<void>;
  close(): Promise<void>;
  exec(sql: string): Promise<void>;
  all<T = Record<string, SqlValue>>(sql: string, params?: SqlValue[]): Promise<T[]>;
  get<T = Record<string, SqlValue>>(sql: string, params?: SqlValue[]): Promise<T | undefined>;
  run(sql: string, params?: SqlValue[]): Promise<RunResult>;
  isOpen(): boolean;
  export(): Promise<Uint8Array>;
}
```

- [ ] **Step 4: Write `src/adapters/memory-adapter.ts`**

```ts
import type { SqlValue } from '../types';
import type { RunResult, SQLiteAdapter } from './adapter';

/** The initialised sqlite3 WASM namespace. Typed as `any` because the official build ships no types for `oo1`/`capi`. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Sqlite3Module = any;

/**
 * Loads the official SQLite WASM build for the current environment: the
 * `sqlite3-node.mjs` entry under Node (tests) and the package's browser entry
 * everywhere else. The module is initialised once per process and cached, so
 * opening several adapters costs one WASM instantiation.
 */
let modulePromise: Promise<Sqlite3Module> | undefined;

export async function loadSqlite3(wasmDir?: string): Promise<Sqlite3Module> {
  if (!modulePromise) {
    modulePromise = (async () => {
      const isNode = typeof process !== 'undefined' && process.versions?.node !== undefined;
      const mod = isNode
        ? await import(nodeSqliteEntryUrl())  // resolved via createRequire; the subpath is not in the package exports map
        : await import('@sqlite.org/sqlite-wasm');
      const init = (mod as { default: (config: unknown) => Promise<Sqlite3Module> }).default;
      const config: Record<string, unknown> = { print: () => {}, printErr: console.error };
      if (wasmDir) {
        config['locateFile'] = (file: string) => `${wasmDir}/${file}`;
      }
      return init(config);
    })();
  }
  return modulePromise;
}

/**
 * An in-memory SQLite database over the official WASM build. It is the adapter
 * every test in this package uses and the last-resort browser backend when
 * neither OPFS nor IndexedDB is usable: nothing survives a reload, but the SQL
 * semantics are byte-for-byte the ones the persistent adapters give.
 */
export class MemoryAdapter implements SQLiteAdapter {
  protected sqlite3: Sqlite3Module | undefined;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  protected db: any;

  async open(): Promise<void> {
    if (this.db) return;
    this.sqlite3 = await loadSqlite3();
    this.db = new this.sqlite3.oo1.DB(':memory:');
  }

  async close(): Promise<void> {
    if (!this.db) return;
    this.db.close();
    this.db = undefined;
  }

  isOpen(): boolean {
    return this.db !== undefined;
  }

  async exec(sql: string): Promise<void> {
    this.ensureOpen();
    this.db.exec(sql);
  }

  async all<T>(sql: string, params: SqlValue[] = []): Promise<T[]> {
    this.ensureOpen();
    const stmt = this.db.prepare(sql);
    try {
      this.bind(stmt, params);
      const rows: T[] = [];
      while (stmt.step()) rows.push(stmt.get({}) as T);
      return rows;
    } finally {
      stmt.finalize();
    }
  }

  async get<T>(sql: string, params: SqlValue[] = []): Promise<T | undefined> {
    const rows = await this.all<T>(sql, params);
    return rows[0];
  }

  async run(sql: string, params: SqlValue[] = []): Promise<RunResult> {
    this.ensureOpen();
    const stmt = this.db.prepare(sql);
    try {
      this.bind(stmt, params);
      stmt.step();
    } finally {
      stmt.finalize();
    }
    return { changes: this.db.changes(), lastInsertRowid: Number(this.sqlite3.capi.sqlite3_last_insert_rowid(this.db)) };
  }

  async export(): Promise<Uint8Array> {
    this.ensureOpen();
    return new Uint8Array(this.sqlite3.capi.sqlite3_js_db_export(this.db.pointer));
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  protected bind(stmt: any, params: SqlValue[]): void {
    for (let i = 0; i < params.length; i++) {
      stmt.bind(i + 1, params[i] ?? null);
    }
  }

  protected ensureOpen(): void {
    if (!this.db) throw new Error('Database is not open. Call open() first.');
  }
}
```

- [ ] **Step 5: Run the test and watch it pass**

Run: `npm test -- src/adapters/memory-adapter.test.ts`
Expected: PASS, 7 tests.

- [ ] **Step 6: Export from the entry point**

Append to `src/index.ts`:

```ts
export type { SqlValue, Row, ScopeValues } from './types';
export type { SQLiteAdapter, RunResult } from './adapters/adapter';
export { MemoryAdapter, loadSqlite3 } from './adapters/memory-adapter';
```

- [ ] **Step 7: Commit**

```bash
git add src/types.ts src/adapters src/index.ts
git commit -m "$(cat <<'MSG'
feat: SQLiteAdapter interface and MemoryAdapter over the WASM build

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---
### Task 3: Schema types and column builders

The fluent shape must survive verbatim so the app's `schema.ts` only loses `.lww()`: `t.text('x').notNull('').maxLength(50)`, `t.real('y')`, `t.integer('z').notNull(0)`, `t.date('d')`. One change from v2 removes a whole class of spurious migrations: a column now carries a **storage type** (what SQLite sees) separately from its **logical type** (what the app meant). `date()` and `guid()` store `TEXT`, so introspection round-trips cleanly instead of producing a `DATE` vs `TEXT` diff on every startup.

**Files:**
- Create: `packages/core/src/schema/types.ts`
- Create: `packages/core/src/schema/column-builder.ts`
- Test: `packages/core/src/schema/column-builder.test.ts`

**Interfaces:**
- Consumes: `SqlValue` from `src/types.ts`.
- Produces:
  - `type StorageType = 'TEXT' | 'INTEGER' | 'REAL' | 'BLOB'`
  - `type LogicalType = 'text' | 'integer' | 'real' | 'date' | 'guid' | 'blob'`
  - `interface ColumnDef { name: string; type: StorageType; logical: LogicalType; notNull: boolean; defaultValue?: SqlValue; maxLength?: number }`
  - `type KeyType = 'PRIMARY' | 'UNIQUE' | 'INDEX'`
  - `interface KeyDef { columns: string[]; type: KeyType; name?: string }`
  - `interface SyncedDef { key: string; scope: string[] }`
  - `interface TableDef { name: string; columns: ColumnDef[]; keys: KeyDef[]; synced?: SyncedDef; library: boolean }`
  - `interface Schema { tables: TableDef[] }`
  - `class SchemaError extends Error`
  - `class ColumnBuilder { constructor(name: string, type: StorageType, logical: LogicalType); notNull(defaultValue: SqlValue): this; maxLength(n: number): this; build(): ColumnDef }`

- [ ] **Step 1: Write the failing test**

`src/schema/column-builder.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { ColumnBuilder } from './column-builder';

describe('ColumnBuilder', () => {
  it('builds a plain text column', () => {
    expect(new ColumnBuilder('part_no', 'TEXT', 'text').build()).toEqual({
      name: 'part_no', type: 'TEXT', logical: 'text', notNull: false,
    });
  });

  it('keeps notNull with its default and chains maxLength in either order', () => {
    const a = new ColumnBuilder('contract', 'TEXT', 'text').notNull('').maxLength(5).build();
    const b = new ColumnBuilder('contract', 'TEXT', 'text').maxLength(5).notNull('').build();
    expect(a).toEqual({ name: 'contract', type: 'TEXT', logical: 'text', notNull: true, defaultValue: '', maxLength: 5 });
    expect(b).toEqual(a);
  });

  it('stores a date as TEXT but remembers it is a date', () => {
    const col = new ColumnBuilder('planned_start', 'TEXT', 'date').build();
    expect(col.type).toBe('TEXT');
    expect(col.logical).toBe('date');
  });

  it('rejects a notNull default of the wrong shape', () => {
    expect(() => new ColumnBuilder('qty', 'REAL', 'real').notNull('nope' as never)).toThrow(/qty/);
  });

  it('rejects a non-positive maxLength', () => {
    expect(() => new ColumnBuilder('a', 'TEXT', 'text').maxLength(0)).toThrow(/maxLength/);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/schema/column-builder.test.ts`
Expected: FAIL — `Failed to resolve import "./column-builder"`.

- [ ] **Step 3: Write `src/schema/types.ts`**

```ts
import type { SqlValue } from '../types';

/** The four types SQLite actually stores. What the migration layer compares. */
export type StorageType = 'TEXT' | 'INTEGER' | 'REAL' | 'BLOB';

/** What the declaration meant. `date` and `guid` are stored as TEXT; keeping the intent lets the app and the docs stay honest without confusing the differ. */
export type LogicalType = 'text' | 'integer' | 'real' | 'date' | 'guid' | 'blob';

/** One declared column. `maxLength` is advisory metadata for the app's forms — SQLite does not enforce it and neither does this library. */
export interface ColumnDef {
  name: string;
  type: StorageType;
  logical: LogicalType;
  notNull: boolean;
  defaultValue?: SqlValue;
  maxLength?: number;
}

export type KeyType = 'PRIMARY' | 'UNIQUE' | 'INDEX';

/** A primary key, a unique constraint or a plain index. `name` is generated for indexes when it is not given. */
export interface KeyDef {
  columns: string[];
  type: KeyType;
  name?: string;
}

/** What `.synced()` declares: the column holding the server row key, and the columns a pull may filter on. Both are trusted from the schema; see `validateScopes` for the optional server check. */
export interface SyncedDef {
  key: string;
  scope: string[];
}

/** One table. `library: true` marks the tables this package owns (`outbox`, `sync_cursor`) so the app cannot redeclare them and the server-truth guard can ignore them. */
export interface TableDef {
  name: string;
  columns: ColumnDef[];
  keys: KeyDef[];
  synced?: SyncedDef;
  library: boolean;
}

/** The built, immutable schema: what `Database.open` migrates towards and what every typed API reads its shape from. */
export interface Schema {
  tables: TableDef[];
}

/** Thrown while building or validating a schema. Always names the table or column at fault. */
export class SchemaError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SchemaError';
  }
}
```

- [ ] **Step 4: Write `src/schema/column-builder.ts`**

```ts
import type { SqlValue } from '../types';
import { SchemaError, type ColumnDef, type LogicalType, type StorageType } from './types';

/**
 * Declares one column. Instances come from the table builder (`t.text('x')`),
 * never from application code directly, and every modifier returns `this` so
 * `.notNull('')`, `.maxLength(50)` and their reverse order all read the same.
 * `notNull` always takes the default value that existing rows get when the
 * column is added by an automatic migration — a NOT NULL column without one
 * cannot be added to a populated table.
 */
export class ColumnBuilder {
  private _notNull = false;
  private _defaultValue: SqlValue | undefined;
  private _maxLength: number | undefined;

  constructor(
    private readonly name: string,
    private readonly type: StorageType,
    private readonly logical: LogicalType,
  ) {}

  notNull(defaultValue: SqlValue): this {
    if (this.type === 'INTEGER' || this.type === 'REAL') {
      if (typeof defaultValue !== 'number') {
        throw new SchemaError(`Column ${this.name}: notNull() on a numeric column needs a number default, got ${typeof defaultValue}`);
      }
    } else if (this.type === 'TEXT' && typeof defaultValue !== 'string') {
      throw new SchemaError(`Column ${this.name}: notNull() on a text column needs a string default, got ${typeof defaultValue}`);
    }
    this._notNull = true;
    this._defaultValue = defaultValue;
    return this;
  }

  maxLength(length: number): this {
    if (!Number.isInteger(length) || length <= 0) {
      throw new SchemaError(`Column ${this.name}: maxLength must be a positive integer, got ${length}`);
    }
    this._maxLength = length;
    return this;
  }

  build(): ColumnDef {
    const def: ColumnDef = { name: this.name, type: this.type, logical: this.logical, notNull: this._notNull };
    if (this._defaultValue !== undefined) def.defaultValue = this._defaultValue;
    if (this._maxLength !== undefined) def.maxLength = this._maxLength;
    return def;
  }
}
```

- [ ] **Step 5: Run the test and watch it pass**

Run: `npm test -- src/schema/column-builder.test.ts`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add src/schema
git commit -m "$(cat <<'MSG'
feat(schema): column definitions and the fluent column builder

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: Table builder, system columns and `.synced()`

The app declares `system_removed` itself on all 19 tables and declares `key('system_id').primary()` for a column it never declares — both have to keep working. So the table builder adds the system columns it owns only when the app has not already declared them, and it adds the primary key only when none was declared.

**Files:**
- Create: `packages/core/src/schema/table-builder.ts`
- Test: `packages/core/src/schema/table-builder.test.ts`

**Interfaces:**
- Consumes: `ColumnBuilder`, `ColumnDef`, `KeyDef`, `SyncedDef`, `TableDef`, `SchemaError`.
- Produces:
  - `class KeyBuilder { constructor(columns: string[]); primary(): void; unique(name?: string): void; index(name?: string): void; build(tableName: string): KeyDef }`
  - `class TableBuilder { readonly name: string; text(n: string): ColumnBuilder; integer(n: string): ColumnBuilder; real(n: string): ColumnBuilder; date(n: string): ColumnBuilder; guid(n: string): ColumnBuilder; blob(n: string): ColumnBuilder; key(...columns: string[]): KeyBuilder; markSynced(def: SyncedDef): void; markLibrary(): void; build(): TableDef }`
  - Constants `SYSTEM_ID_COLUMN = 'system_id'`, `SYNC_SEQ_COLUMN = 'sync_seq'`, `SYSTEM_REMOVED_COLUMN = 'system_removed'`

- [ ] **Step 1: Write the failing test**

`src/schema/table-builder.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { TableBuilder } from './table-builder';

describe('TableBuilder', () => {
  it('adds the system columns the app did not declare', () => {
    const t = new TableBuilder('c_work_order');
    t.text('description').maxLength(200);
    const table = t.build();
    const names = table.columns.map((c) => c.name);
    expect(names).toEqual(['system_id', 'system_removed', 'description']);
    expect(table.columns[0]).toMatchObject({ name: 'system_id', type: 'TEXT', notNull: true, defaultValue: '' });
    expect(table.columns[1]).toMatchObject({ name: 'system_removed', type: 'INTEGER', notNull: true, defaultValue: 0 });
  });

  it('does not duplicate a system column the app declared itself', () => {
    const t = new TableBuilder('c_work_task');
    t.integer('system_removed').notNull(0);
    t.text('action_taken');
    const table = t.build();
    expect(table.columns.filter((c) => c.name === 'system_removed')).toHaveLength(1);
  });

  it('adds sync_seq and a primary key on the sync key for a synced table', () => {
    const t = new TableBuilder('c_work_task');
    t.real('wo_no');
    t.markSynced({ key: 'system_id', scope: ['wo_no'] });
    const table = t.build();
    expect(table.columns.map((c) => c.name)).toContain('sync_seq');
    expect(table.keys).toEqual([{ columns: ['system_id'], type: 'PRIMARY' }]);
    expect(table.synced).toEqual({ key: 'system_id', scope: ['wo_no'] });
  });

  it('keeps the primary key the app declared instead of adding one', () => {
    const t = new TableBuilder('c_work_task');
    t.key('system_id').primary();
    const table = t.build();
    expect(table.keys.filter((k) => k.type === 'PRIMARY')).toHaveLength(1);
  });

  it('names an index when the caller did not', () => {
    const t = new TableBuilder('outbox');
    t.text('status');
    t.text('changed_at');
    t.key('status', 'changed_at').index();
    expect(t.build().keys).toContainEqual({ columns: ['status', 'changed_at'], type: 'INDEX', name: 'idx_outbox_status_changed_at' });
  });

  it('rejects a scope column the table does not declare', () => {
    const t = new TableBuilder('c_work_task');
    t.markSynced({ key: 'system_id', scope: ['wo_no'] });
    expect(() => t.build()).toThrow(/c_work_task.*wo_no/);
  });

  it('rejects a duplicate column name', () => {
    const t = new TableBuilder('c_ncr');
    t.text('notes');
    expect(() => t.text('notes')).toThrow(/notes/);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/schema/table-builder.test.ts`
Expected: FAIL — `Failed to resolve import "./table-builder"`.

- [ ] **Step 3: Write `src/schema/table-builder.ts`**

```ts
import { ColumnBuilder } from './column-builder';
import { SchemaError, type ColumnDef, type KeyDef, type KeyType, type SyncedDef, type TableDef } from './types';

/** The row key every table carries: the server's `SYSTEM_ID` GUID, lowercase locally. */
export const SYSTEM_ID_COLUMN = 'system_id';
/** The server cursor stamped on every synced row by the IFS `SYNC_SEQ` sequence. */
export const SYNC_SEQ_COLUMN = 'sync_seq';
/** The tombstone flag; 1 means the server says the row is gone. */
export const SYSTEM_REMOVED_COLUMN = 'system_removed';

/** Declares what a set of columns means: the primary key, a unique constraint or a plain index. Returned by `t.key(...)` and used for its side effect. */
export class KeyBuilder {
  private _type: KeyType = 'INDEX';
  private _name: string | undefined;

  constructor(private readonly columns: string[]) {}

  primary(): void {
    this._type = 'PRIMARY';
  }

  unique(name?: string): void {
    this._type = 'UNIQUE';
    this._name = name;
  }

  index(name?: string): void {
    this._type = 'INDEX';
    this._name = name;
  }

  build(tableName: string): KeyDef {
    if (this._type === 'PRIMARY') return { columns: this.columns, type: 'PRIMARY' };
    const name = this._name ?? `idx_${tableName}_${this.columns.join('_')}`;
    return { columns: this.columns, type: this._type, name };
  }
}

/**
 * Declares one table. The builder owns the system columns: `system_id` and
 * `system_removed` on every table, plus `sync_seq` on a `.synced()` one, each
 * added only when the application did not declare it itself — the app's own
 * declaration always wins, so an existing `schema.ts` needs no edit. A synced
 * table with no declared primary key gets one on its sync key.
 */
export class TableBuilder {
  private readonly columns: ColumnBuilder[] = [];
  private readonly columnNames = new Set<string>();
  private readonly keys: KeyBuilder[] = [];
  private synced: SyncedDef | undefined;
  private library = false;

  constructor(public readonly name: string) {}

  text(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'TEXT', 'text'), name);
  }

  integer(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'INTEGER', 'integer'), name);
  }

  real(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'REAL', 'real'), name);
  }

  date(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'TEXT', 'date'), name);
  }

  guid(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'TEXT', 'guid'), name);
  }

  blob(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'BLOB', 'blob'), name);
  }

  key(...columns: string[]): KeyBuilder {
    const builder = new KeyBuilder(columns);
    this.keys.push(builder);
    return builder;
  }

  markSynced(def: SyncedDef): void {
    this.synced = def;
  }

  markLibrary(): void {
    this.library = true;
  }

  build(): TableDef {
    const columns: ColumnDef[] = [];
    if (!this.library) {
      if (!this.columnNames.has(SYSTEM_ID_COLUMN)) {
        columns.push({ name: SYSTEM_ID_COLUMN, type: 'TEXT', logical: 'guid', notNull: true, defaultValue: '' });
      }
      if (!this.columnNames.has(SYSTEM_REMOVED_COLUMN)) {
        columns.push({ name: SYSTEM_REMOVED_COLUMN, type: 'INTEGER', logical: 'integer', notNull: true, defaultValue: 0 });
      }
      if (this.synced && !this.columnNames.has(SYNC_SEQ_COLUMN)) {
        columns.push({ name: SYNC_SEQ_COLUMN, type: 'INTEGER', logical: 'integer', notNull: true, defaultValue: 0 });
      }
    }
    columns.push(...this.columns.map((c) => c.build()));

    const keys = this.keys.map((k) => k.build(this.name));
    if (!keys.some((k) => k.type === 'PRIMARY')) {
      const keyColumn = this.synced?.key ?? SYSTEM_ID_COLUMN;
      if (columns.some((c) => c.name === keyColumn)) {
        keys.unshift({ columns: [keyColumn], type: 'PRIMARY' });
      }
    }

    if (this.synced) {
      const present = new Set(columns.map((c) => c.name));
      if (!present.has(this.synced.key)) {
        throw new SchemaError(`Table ${this.name}: synced key column "${this.synced.key}" is not declared`);
      }
      for (const scopeColumn of this.synced.scope) {
        if (!present.has(scopeColumn)) {
          throw new SchemaError(`Table ${this.name}: synced scope column "${scopeColumn}" is not declared`);
        }
      }
    }

    const table: TableDef = { name: this.name, columns, keys, library: this.library };
    if (this.synced) table.synced = this.synced;
    return table;
  }

  private add(builder: ColumnBuilder, name: string): ColumnBuilder {
    if (this.columnNames.has(name)) {
      throw new SchemaError(`Table ${this.name}: column "${name}" is declared twice`);
    }
    this.columnNames.add(name);
    this.columns.push(builder);
    return builder;
  }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/schema/table-builder.test.ts`
Expected: PASS, 7 tests. If the system-column ordering assertion fails, keep the implementation order `system_id, system_removed, sync_seq` — the test encodes it deliberately so generated `CREATE TABLE` statements are stable across runs.

- [ ] **Step 5: Commit**

```bash
git add src/schema
git commit -m "$(cat <<'MSG'
feat(schema): table builder with system columns and .synced()

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: `SchemaBuilder`, the library tables and scope helpers

`schema.table(name, t => {...})` returns a handle carrying `.synced()`, so the spec's shape works verbatim. `build()` appends the two tables the library owns — `outbox` and `sync_cursor` — which is why the app never declares them.

**Files:**
- Create: `packages/core/src/schema/schema-builder.ts`
- Create: `packages/core/src/schema/library-tables.ts`
- Create: `packages/core/src/schema/scopes.ts`
- Test: `packages/core/src/schema/schema-builder.test.ts`
- Test: `packages/core/src/schema/scopes.test.ts`
- Modify: `packages/core/src/index.ts`

**Interfaces:**
- Consumes: `TableBuilder`, `SchemaError`, `Schema`, `TableDef`, `ScopeValues`.
- Produces:
  - `class SchemaBuilder { table(name: string, build: (t: TableBuilder) => void): TableHandle; build(): Schema }`
  - `interface TableHandle { synced(def: SyncedDef): void }`
  - `const OUTBOX_TABLE = 'outbox'`, `const SYNC_CURSOR_TABLE = 'sync_cursor'`
  - `function buildLibraryTables(): TableDef[]`
  - `function formatScope(scope?: ScopeValues): string | undefined`
  - `function parseScope(text: string): ScopeValues`
  - `function scopeKey(table: string, scope?: ScopeValues): string`
  - `function scopeMatches(rowScope: ScopeValues | null, queryScope: ScopeValues | undefined): boolean`
  - `class ScopeError extends Error`
  - `type ScopeAllowList = Record<string, string[]>`
  - `function validateScopes(schema: Schema, allowList: ScopeAllowList): void`

- [ ] **Step 1: Write the failing tests**

`src/schema/schema-builder.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { SchemaBuilder } from './schema-builder';

function appSchema() {
  const schema = new SchemaBuilder();
  schema.table('c_work_task', (t) => {
    t.text('system_id');
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate').maxLength(100);
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  schema.table('local_prefs', (t) => {
    t.text('key').notNull('');
    t.text('value');
  });
  return schema.build();
}

describe('SchemaBuilder', () => {
  it('builds the declared tables and appends the library tables', () => {
    const schema = appSchema();
    expect(schema.tables.map((t) => t.name)).toEqual(['c_work_task', 'local_prefs', 'outbox', 'sync_cursor']);
  });

  it('marks the library tables as library and never as synced', () => {
    const outbox = appSchema().tables.find((t) => t.name === 'outbox');
    expect(outbox?.library).toBe(true);
    expect(outbox?.synced).toBeUndefined();
  });

  it('carries the synced declaration through to the table', () => {
    const task = appSchema().tables.find((t) => t.name === 'c_work_task');
    expect(task?.synced).toEqual({ key: 'system_id', scope: ['wo_no'] });
  });

  it('refuses a table named like a library table', () => {
    const schema = new SchemaBuilder();
    expect(() => schema.table('outbox', (t) => t.text('id'))).toThrow(/outbox/);
  });

  it('refuses the same table declared twice', () => {
    const schema = new SchemaBuilder();
    schema.table('c_ncr', (t) => t.text('ncr_no'));
    expect(() => schema.table('c_ncr', (t) => t.text('ncr_no'))).toThrow(/c_ncr/);
  });
});
```

`src/schema/scopes.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { formatScope, parseScope, scopeKey, scopeMatches, validateScopes } from './scopes';
import { SchemaBuilder } from './schema-builder';

describe('scope helpers', () => {
  it('formats a scope the way the wire format spells it', () => {
    expect(formatScope({ wo_no: 3188 })).toBe('WO_NO:3188');
  });

  it('sorts several pairs so the cursor key is stable', () => {
    expect(formatScope({ lu_name: 'JtTask', key_ref: 'X' })).toBe('KEY_REF:X,LU_NAME:JtTask');
  });

  it('returns undefined for no scope', () => {
    expect(formatScope(undefined)).toBeUndefined();
  });

  it('rejects a value containing a comma', () => {
    expect(() => formatScope({ key_ref: 'A,B' })).toThrow(/comma/);
  });

  it('rejects an empty value and more than four pairs', () => {
    expect(() => formatScope({ key_ref: '  ' })).toThrow(/empty/);
    expect(() => formatScope({ a: 1, b: 2, c: 3, d: 4, e: 5 })).toThrow(/four/);
  });

  it('parses a scope back to lowercase columns', () => {
    expect(parseScope('WO_NO:3188')).toEqual({ wo_no: '3188' });
  });

  it('builds the cursor key', () => {
    expect(scopeKey('c_work_task', { wo_no: 3188 })).toBe('c_work_task|WO_NO:3188');
    expect(scopeKey('c_edm_file', undefined)).toBe('c_edm_file|*');
  });

  it('matches a written row against a query scope', () => {
    expect(scopeMatches({ wo_no: 3188 }, { wo_no: 3188 })).toBe(true);
    expect(scopeMatches({ wo_no: 4000 }, { wo_no: 3188 })).toBe(false);
    expect(scopeMatches(null, { wo_no: 3188 })).toBe(true); // unknown scope means "might match"
    expect(scopeMatches({ wo_no: 4000 }, undefined)).toBe(true); // query has no scope
  });
});

describe('validateScopes', () => {
  const schema = (() => {
    const s = new SchemaBuilder();
    s.table('c_work_task', (t) => {
      t.text('system_id');
      t.real('wo_no');
    }).synced({ key: 'system_id', scope: ['wo_no'] });
    return s.build();
  })();

  it('passes when every scope column is on the server allow-list', () => {
    expect(() => validateScopes(schema, { C_WORK_TASK: ['WO_NO'] })).not.toThrow();
  });

  it('throws naming the table and column when it is not', () => {
    expect(() => validateScopes(schema, { C_WORK_TASK: ['TASK_SEQ'] })).toThrow(/C_WORK_TASK.*WO_NO/);
  });
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `npm test -- src/schema`
Expected: FAIL — `Failed to resolve import "./schema-builder"` and `"./scopes"`.

- [ ] **Step 3: Write `src/schema/library-tables.ts`**

```ts
import { TableBuilder } from './table-builder';
import type { TableDef } from './types';

/** The queue of recorded, unconfirmed changes. Owned by the library; the app never declares or writes it directly. */
export const OUTBOX_TABLE = 'outbox';
/** One row per `(table, scope)` the device has pulled, holding that scope's high-water `SYNC_SEQ`. */
export const SYNC_CURSOR_TABLE = 'sync_cursor';

/**
 * Builds the two tables this package owns. They are appended to every schema by
 * `SchemaBuilder.build()`, so automatic migration creates them on first open and
 * the application's `schema.ts` never mentions them.
 */
export function buildLibraryTables(): TableDef[] {
  const outbox = new TableBuilder(OUTBOX_TABLE);
  outbox.markLibrary();
  outbox.text('id').notNull('');
  outbox.text('table_name').notNull('');
  outbox.text('system_id').notNull('');
  outbox.text('column_name').notNull('');
  outbox.text('old_value');
  outbox.text('new_value');
  outbox.text('changed_at').notNull('');
  outbox.text('status').notNull('pending');
  outbox.text('group_id').notNull('');
  outbox.text('batch_id');
  outbox.text('error_text');
  outbox.text('applied_at');
  outbox.key('id').primary();
  outbox.key('status', 'changed_at').index();
  outbox.key('table_name', 'system_id', 'status').index();

  const cursor = new TableBuilder(SYNC_CURSOR_TABLE);
  cursor.markLibrary();
  cursor.text('scope_key').notNull('');
  cursor.text('table_name').notNull('');
  cursor.text('scope');
  cursor.integer('last_sync_seq').notNull(0);
  cursor.text('synced_at').notNull('');
  cursor.key('scope_key').primary();

  return [outbox.build(), cursor.build()];
}
```

- [ ] **Step 4: Write `src/schema/schema-builder.ts`**

```ts
import { buildLibraryTables, OUTBOX_TABLE, SYNC_CURSOR_TABLE } from './library-tables';
import { TableBuilder } from './table-builder';
import { SchemaError, type Schema, type SyncedDef } from './types';

/** What `schema.table(...)` returns: the one thing you may still say about the table you just declared. */
export interface TableHandle {
  /** Marks the table as server truth: names the column holding the server row key and the columns a pull may filter on. A synced table is writable only through the sync runtime. */
  synced(def: SyncedDef): void;
}

/**
 * Declares a database. The fluent shape is the one v2 had, so an existing
 * `schema.ts` carries over unchanged apart from dropping `.lww()` and adding
 * `.synced()`. `build()` appends the library's own tables (`outbox`,
 * `sync_cursor`) and returns an immutable `Schema` that `Database.open`
 * migrates towards.
 */
export class SchemaBuilder {
  private readonly builders: TableBuilder[] = [];
  private readonly names = new Set<string>();

  table(name: string, build: (t: TableBuilder) => void): TableHandle {
    if (name === OUTBOX_TABLE || name === SYNC_CURSOR_TABLE) {
      throw new SchemaError(`Table "${name}" is owned by declarative-sqlite and must not be declared by the application`);
    }
    if (this.names.has(name)) {
      throw new SchemaError(`Table "${name}" is declared twice`);
    }
    this.names.add(name);
    const builder = new TableBuilder(name);
    build(builder);
    this.builders.push(builder);
    return {
      synced: (def: SyncedDef) => builder.markSynced(def),
    };
  }

  build(): Schema {
    return { tables: [...this.builders.map((b) => b.build()), ...buildLibraryTables()] };
  }
}
```

- [ ] **Step 5: Write `src/schema/scopes.ts`**

```ts
import type { ScopeValues } from '../types';
import type { Schema } from './types';

/** Thrown when a scope cannot be expressed on the wire: too many pairs, an empty value, or a comma the format has no escape for. */
export class ScopeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ScopeError';
  }
}

const MAX_SCOPE_PAIRS = 4;

/**
 * Renders scope values as the server spells them: `COLUMN:value[,COLUMN:value]`,
 * uppercase column names, at most four pairs, sorted by column so the same scope
 * always produces the same cursor key. Returns `undefined` for no scope, which
 * means a full-table pull. Throws `ScopeError` for anything the server would
 * reject with `CSCOPEFMT` / `CSCOPECNT`.
 */
export function formatScope(scope?: ScopeValues): string | undefined {
  if (!scope) return undefined;
  const entries = Object.entries(scope);
  if (entries.length === 0) return undefined;
  if (entries.length > MAX_SCOPE_PAIRS) {
    throw new ScopeError(`A scope may name at most four columns, got ${entries.length}`);
  }
  return entries
    .map(([column, value]) => {
      const text = String(value).trim();
      if (text.length === 0) throw new ScopeError(`Scope column ${column} has an empty value`);
      if (text.includes(',')) throw new ScopeError(`Scope column ${column} value contains a comma, which the wire format cannot escape`);
      return [column.toUpperCase(), text] as const;
    })
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([column, value]) => `${column}:${value}`)
    .join(',');
}

/** Parses a wire scope string back into lowercase column values. Values come back as strings; callers that need numbers coerce them. */
export function parseScope(text: string): ScopeValues {
  const scope: ScopeValues = {};
  for (const pair of text.split(',')) {
    const separator = pair.indexOf(':');
    if (separator <= 0) throw new ScopeError(`Scope element "${pair}" is not COLUMN:value`);
    scope[pair.slice(0, separator).trim().toLowerCase()] = pair.slice(separator + 1).trim();
  }
  return scope;
}

/** The key a cursor is stored under: the local table name, a pipe, and the wire scope (or `*` for a full-table pull). */
export function scopeKey(table: string, scope?: ScopeValues): string {
  return `${table}|${formatScope(scope) ?? '*'}`;
}

/**
 * Decides whether a written row is inside a live query's scope. A row whose
 * scope values are unknown (`null`, e.g. a raw `execute` that reported no scope)
 * matches everything, because the safe answer to "might this have changed my
 * rows" is yes. A query with no scope also matches everything on its table.
 */
export function scopeMatches(rowScope: ScopeValues | null, queryScope: ScopeValues | undefined): boolean {
  if (rowScope === null) return true;
  if (!queryScope) return true;
  for (const [column, value] of Object.entries(queryScope)) {
    if (String(rowScope[column] ?? '') !== String(value)) return false;
  }
  return true;
}

/** The server's `IS_SCOPE` registry, keyed by uppercase table name with uppercase column names. */
export type ScopeAllowList = Record<string, string[]>;

/**
 * Optional startup check (off by default, see the plan's Global Constraints):
 * confirms every `.synced()` scope column is one the server will actually accept,
 * so a typo surfaces as a thrown error at boot instead of as `CBADSCOPE` on the
 * first pull. Call it once with the list fetched from the API.
 */
export function validateScopes(schema: Schema, allowList: ScopeAllowList): void {
  for (const table of schema.tables) {
    if (!table.synced) continue;
    const wireTable = table.name.toUpperCase();
    const allowed = new Set((allowList[wireTable] ?? []).map((c) => c.toUpperCase()));
    for (const column of table.synced.scope) {
      if (!allowed.has(column.toUpperCase())) {
        throw new ScopeError(`${wireTable}: scope column ${column.toUpperCase()} is not flagged IS_SCOPE on the server`);
      }
    }
  }
}
```

- [ ] **Step 6: Run the tests and watch them pass**

Run: `npm test -- src/schema`
Expected: PASS, 25 tests across the three schema test files.

- [ ] **Step 7: Export the schema layer**

Append to `src/index.ts`:

```ts
export { SchemaBuilder } from './schema/schema-builder';
export type { TableHandle } from './schema/schema-builder';
export { TableBuilder, KeyBuilder, SYSTEM_ID_COLUMN, SYNC_SEQ_COLUMN, SYSTEM_REMOVED_COLUMN } from './schema/table-builder';
export { ColumnBuilder } from './schema/column-builder';
export { OUTBOX_TABLE, SYNC_CURSOR_TABLE } from './schema/library-tables';
export { formatScope, parseScope, scopeKey, scopeMatches, validateScopes, ScopeError } from './schema/scopes';
export type { ScopeAllowList } from './schema/scopes';
export { SchemaError } from './schema/types';
export type { Schema, TableDef, ColumnDef, KeyDef, KeyType, SyncedDef, StorageType, LogicalType } from './schema/types';
```

- [ ] **Step 8: Commit**

```bash
git add src/schema src/index.ts
git commit -m "$(cat <<'MSG'
feat(schema): SchemaBuilder, library tables and scope helpers

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---
### Task 6: Introspect the live schema

v2 introspected against hand-written mock adapters, which let bugs through that a real database would have caught. v3 introspects a real in-memory SQLite created by DDL in the test.

**Files:**
- Create: `packages/core/src/db/sql.ts`
- Create: `packages/core/src/migration/introspect.ts`
- Test: `packages/core/src/migration/introspect.test.ts`

**Interfaces:**
- Consumes: `SQLiteAdapter`, `MemoryAdapter`, `Schema`, `TableDef`, `ColumnDef`, `KeyDef`, `StorageType`.
- Produces:
  - `function quoteIdentifier(name: string): string`
  - `function introspect(adapter: SQLiteAdapter): Promise<Schema>`

- [ ] **Step 1: Write the failing test**

`src/migration/introspect.test.ts`:

```ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { introspect } from './introspect';

describe('introspect', () => {
  let adapter: MemoryAdapter;

  beforeEach(async () => {
    adapter = new MemoryAdapter();
    await adapter.open();
  });

  afterEach(async () => {
    await adapter.close();
  });

  it('returns an empty schema for an empty database', async () => {
    expect(await introspect(adapter)).toEqual({ tables: [] });
  });

  it('reads columns, types, notNull and defaults', async () => {
    await adapter.exec(`CREATE TABLE "c_work_task" (
      "system_id" TEXT NOT NULL DEFAULT '',
      "wo_no" REAL,
      "sync_seq" INTEGER NOT NULL DEFAULT 0
    )`);
    const schema = await introspect(adapter);
    expect(schema.tables).toHaveLength(1);
    expect(schema.tables[0]?.columns).toEqual([
      { name: 'system_id', type: 'TEXT', logical: 'text', notNull: true, defaultValue: '' },
      { name: 'wo_no', type: 'REAL', logical: 'real', notNull: false },
      { name: 'sync_seq', type: 'INTEGER', logical: 'integer', notNull: true, defaultValue: 0 },
    ]);
  });

  it('reads the primary key and named indexes', async () => {
    await adapter.exec(`CREATE TABLE "outbox" ("id" TEXT NOT NULL, "status" TEXT, "changed_at" TEXT, PRIMARY KEY ("id"))`);
    await adapter.exec(`CREATE INDEX "idx_outbox_status_changed_at" ON "outbox" ("status", "changed_at")`);
    const table = (await introspect(adapter)).tables[0];
    expect(table?.keys).toEqual([
      { columns: ['id'], type: 'PRIMARY' },
      { columns: ['status', 'changed_at'], type: 'INDEX', name: 'idx_outbox_status_changed_at' },
    ]);
  });

  it('ignores sqlite internal tables', async () => {
    await adapter.exec(`CREATE TABLE "t" ("id" INTEGER PRIMARY KEY AUTOINCREMENT)`);
    await adapter.run(`INSERT INTO "t" DEFAULT VALUES`);
    expect((await introspect(adapter)).tables.map((t) => t.name)).toEqual(['t']);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/migration/introspect.test.ts`
Expected: FAIL — `Failed to resolve import "./introspect"`.

- [ ] **Step 3: Write `src/db/sql.ts`**

```ts
/** Quotes an identifier for SQLite by doubling embedded quotes. Every table and column name the library puts into SQL goes through this. */
export function quoteIdentifier(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}
```

- [ ] **Step 4: Write `src/migration/introspect.ts`**

```ts
import type { SQLiteAdapter } from '../adapters/adapter';
import { quoteIdentifier } from '../db/sql';
import type { ColumnDef, KeyDef, LogicalType, Schema, StorageType, TableDef } from '../schema/types';

interface PragmaColumn {
  name: string;
  type: string;
  notnull: number;
  dflt_value: string | null;
  pk: number;
}

interface PragmaIndex {
  name: string;
  unique: number;
  origin: string;
}

interface PragmaIndexColumn {
  seqno: number;
  name: string;
}

function toStorageType(declared: string): StorageType {
  const type = declared.toUpperCase();
  if (type.includes('INT')) return 'INTEGER';
  if (type.includes('REAL') || type.includes('FLOA') || type.includes('DOUB')) return 'REAL';
  if (type.includes('BLOB')) return 'BLOB';
  return 'TEXT';
}

function toLogicalType(storage: StorageType): LogicalType {
  return storage === 'TEXT' ? 'text' : storage === 'INTEGER' ? 'integer' : storage === 'REAL' ? 'real' : 'blob';
}

function parseDefault(raw: string | null, storage: StorageType): string | number | undefined {
  if (raw === null) return undefined;
  if (storage === 'INTEGER' || storage === 'REAL') {
    const value = Number(raw);
    return Number.isNaN(value) ? undefined : value;
  }
  if (raw.startsWith("'") && raw.endsWith("'")) return raw.slice(1, -1).replace(/''/g, "'");
  return raw;
}

/**
 * Reads the database as it actually is — `sqlite_master` plus `PRAGMA
 * table_info` and `PRAGMA index_list`/`index_info` — into the same `Schema`
 * shape the builder produces, so the differ compares like with like. Logical
 * types are lost in the database (a date is TEXT), so introspected columns
 * carry the logical type their storage implies; the differ only ever compares
 * storage.
 */
export async function introspect(adapter: SQLiteAdapter): Promise<Schema> {
  const tableRows = await adapter.all<{ name: string }>(
    `SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name`,
  );

  const tables: TableDef[] = [];
  for (const { name } of tableRows) {
    const quoted = quoteIdentifier(name);
    const pragmaColumns = await adapter.all<PragmaColumn>(`PRAGMA table_info(${quoted})`);

    const columns: ColumnDef[] = pragmaColumns.map((row) => {
      const type = toStorageType(row.type);
      const column: ColumnDef = { name: row.name, type, logical: toLogicalType(type), notNull: row.notnull === 1 };
      const defaultValue = parseDefault(row.dflt_value, type);
      if (defaultValue !== undefined) column.defaultValue = defaultValue;
      return column;
    });

    const keys: KeyDef[] = [];
    const pkColumns = pragmaColumns
      .filter((row) => row.pk > 0)
      .sort((a, b) => a.pk - b.pk)
      .map((row) => row.name);
    if (pkColumns.length > 0) keys.push({ columns: pkColumns, type: 'PRIMARY' });

    const indexes = await adapter.all<PragmaIndex>(`PRAGMA index_list(${quoted})`);
    for (const index of indexes) {
      if (index.origin === 'pk') continue;
      const indexColumns = await adapter.all<PragmaIndexColumn>(`PRAGMA index_info(${quoteIdentifier(index.name)})`);
      keys.push({
        columns: indexColumns.sort((a, b) => a.seqno - b.seqno).map((c) => c.name),
        type: index.unique === 1 ? 'UNIQUE' : 'INDEX',
        name: index.name,
      });
    }

    tables.push({ name, columns, keys, library: false });
  }

  return { tables };
}
```

- [ ] **Step 5: Run the test and watch it pass**

Run: `npm test -- src/migration/introspect.test.ts`
Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add src/db/sql.ts src/migration
git commit -m "$(cat <<'MSG'
feat(migration): introspect the live schema from sqlite_master and PRAGMA

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 7: Diff declared against live

Additive by default is a hard rule: the differ *reports* tables and columns that exist only in the database, and never proposes dropping them. The only destructive operation it can propose is a guarded recreation, and only when a column's storage type changed or the primary key moved.

**Files:**
- Create: `packages/core/src/migration/diff.ts`
- Test: `packages/core/src/migration/diff.test.ts`

**Interfaces:**
- Consumes: `Schema`, `TableDef`, `ColumnDef`, `KeyDef`.
- Produces:
  - `interface ColumnRetype { from: ColumnDef; to: ColumnDef }`
  - `interface TableAlteration { table: string; columnsToAdd: ColumnDef[]; keysToAdd: KeyDef[]; columnsToRetype: ColumnRetype[]; requiresRecreate: boolean }`
  - `interface MigrationDiff { tablesToCreate: TableDef[]; tablesToAlter: TableAlteration[]; extraTables: string[]; extraColumns: Array<{ table: string; column: string }>; hasChanges: boolean }`
  - `function diffSchema(declared: Schema, live: Schema): MigrationDiff`

- [ ] **Step 1: Write the failing test**

`src/migration/diff.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { diffSchema } from './diff';
import type { Schema, TableDef } from '../schema/types';

const table = (name: string, columns: TableDef['columns'], keys: TableDef['keys'] = []): TableDef => ({ name, columns, keys, library: false });
const text = (name: string) => ({ name, type: 'TEXT' as const, logical: 'text' as const, notNull: false });
const real = (name: string) => ({ name, type: 'REAL' as const, logical: 'real' as const, notNull: false });
const schema = (...tables: TableDef[]): Schema => ({ tables });

describe('diffSchema', () => {
  it('reports no changes for identical schemas', () => {
    const s = schema(table('t', [text('a')]));
    expect(diffSchema(s, s).hasChanges).toBe(false);
  });

  it('creates a declared table the database does not have', () => {
    const diff = diffSchema(schema(table('t', [text('a')])), schema());
    expect(diff.tablesToCreate.map((t) => t.name)).toEqual(['t']);
    expect(diff.hasChanges).toBe(true);
  });

  it('adds a declared column the table is missing', () => {
    const diff = diffSchema(schema(table('t', [text('a'), text('b')])), schema(table('t', [text('a')])));
    expect(diff.tablesToAlter[0]?.columnsToAdd.map((c) => c.name)).toEqual(['b']);
    expect(diff.tablesToAlter[0]?.requiresRecreate).toBe(false);
  });

  it('adds a declared index the table is missing', () => {
    const declared = schema(table('t', [text('a')], [{ columns: ['a'], type: 'INDEX', name: 'idx_t_a' }]));
    const diff = diffSchema(declared, schema(table('t', [text('a')])));
    expect(diff.tablesToAlter[0]?.keysToAdd).toEqual([{ columns: ['a'], type: 'INDEX', name: 'idx_t_a' }]);
  });

  it('never drops a table or column the database has and the schema does not', () => {
    const diff = diffSchema(schema(table('t', [text('a')])), schema(table('t', [text('a'), text('legacy')]), table('old', [text('x')])));
    expect(diff.extraTables).toEqual(['old']);
    expect(diff.extraColumns).toEqual([{ table: 't', column: 'legacy' }]);
    expect(diff.tablesToAlter).toEqual([]);
    expect(diff.hasChanges).toBe(false);
  });

  it('requires a recreate when a storage type changed', () => {
    const diff = diffSchema(schema(table('t', [real('a')])), schema(table('t', [text('a')])));
    const alteration = diff.tablesToAlter[0];
    expect(alteration?.requiresRecreate).toBe(true);
    expect(alteration?.columnsToRetype).toEqual([
      { from: { name: 'a', type: 'TEXT', logical: 'text', notNull: false }, to: { name: 'a', type: 'REAL', logical: 'real', notNull: false } },
    ]);
  });

  it('does not require a recreate when only the logical type differs', () => {
    const declared = schema(table('t', [{ name: 'd', type: 'TEXT', logical: 'date', notNull: false }]));
    const live = schema(table('t', [text('d')]));
    expect(diffSchema(declared, live).hasChanges).toBe(false);
  });

  it('requires a recreate when the declared primary key differs', () => {
    const declared = schema(table('t', [text('a')], [{ columns: ['a'], type: 'PRIMARY' }]));
    const live = schema(table('t', [text('a')]));
    expect(diffSchema(declared, live).tablesToAlter[0]?.requiresRecreate).toBe(true);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/migration/diff.test.ts`
Expected: FAIL — `Failed to resolve import "./diff"`.

- [ ] **Step 3: Write `src/migration/diff.ts`**

```ts
import type { ColumnDef, KeyDef, Schema, TableDef } from '../schema/types';

/** A column whose storage type changed. The only reason this library ever rebuilds a table. */
export interface ColumnRetype {
  from: ColumnDef;
  to: ColumnDef;
}

/** Everything one existing table needs. `requiresRecreate` means ALTER TABLE cannot express it. */
export interface TableAlteration {
  table: string;
  columnsToAdd: ColumnDef[];
  keysToAdd: KeyDef[];
  columnsToRetype: ColumnRetype[];
  requiresRecreate: boolean;
}

/**
 * The difference between what the application declared and what the database
 * holds. `extraTables` and `extraColumns` exist so the plan can *report* what is
 * in the database and not in the schema; they are never turned into drops.
 */
export interface MigrationDiff {
  tablesToCreate: TableDef[];
  tablesToAlter: TableAlteration[];
  extraTables: string[];
  extraColumns: Array<{ table: string; column: string }>;
  hasChanges: boolean;
}

function samePrimaryKey(declared: TableDef, live: TableDef): boolean {
  const a = declared.keys.find((k) => k.type === 'PRIMARY');
  const b = live.keys.find((k) => k.type === 'PRIMARY');
  if (!a) return true;
  if (!b) return false;
  return a.columns.join(',') === b.columns.join(',');
}

/**
 * Compares the declared schema with an introspected one. Additive only: a table
 * or column that exists solely in the database is reported and left alone, so an
 * app rolling back to an older build never loses data. A storage-type change or
 * a changed primary key marks the table `requiresRecreate`, which the generator
 * refuses to act on unless `allowRecreate` is set.
 */
export function diffSchema(declared: Schema, live: Schema): MigrationDiff {
  const liveTables = new Map(live.tables.map((t) => [t.name, t]));
  const declaredNames = new Set(declared.tables.map((t) => t.name));

  const tablesToCreate: TableDef[] = [];
  const tablesToAlter: TableAlteration[] = [];
  const extraColumns: Array<{ table: string; column: string }> = [];

  for (const declaredTable of declared.tables) {
    const liveTable = liveTables.get(declaredTable.name);
    if (!liveTable) {
      tablesToCreate.push(declaredTable);
      continue;
    }

    const liveColumns = new Map(liveTable.columns.map((c) => [c.name, c]));
    const columnsToAdd: ColumnDef[] = [];
    const columnsToRetype: ColumnRetype[] = [];

    for (const column of declaredTable.columns) {
      const liveColumn = liveColumns.get(column.name);
      if (!liveColumn) {
        columnsToAdd.push(column);
      } else if (liveColumn.type !== column.type) {
        columnsToRetype.push({ from: liveColumn, to: column });
      }
    }

    const declaredColumnNames = new Set(declaredTable.columns.map((c) => c.name));
    for (const liveColumn of liveTable.columns) {
      if (!declaredColumnNames.has(liveColumn.name)) {
        extraColumns.push({ table: declaredTable.name, column: liveColumn.name });
      }
    }

    const liveKeyNames = new Set(liveTable.keys.filter((k) => k.name).map((k) => k.name));
    const keysToAdd = declaredTable.keys.filter((k) => k.type !== 'PRIMARY' && k.name !== undefined && !liveKeyNames.has(k.name));

    const requiresRecreate = columnsToRetype.length > 0 || !samePrimaryKey(declaredTable, liveTable);

    if (columnsToAdd.length > 0 || keysToAdd.length > 0 || requiresRecreate) {
      tablesToAlter.push({ table: declaredTable.name, columnsToAdd, keysToAdd, columnsToRetype, requiresRecreate });
    }
  }

  const extraTables = live.tables.filter((t) => !declaredNames.has(t.name)).map((t) => t.name);

  return {
    tablesToCreate,
    tablesToAlter,
    extraTables,
    extraColumns,
    hasChanges: tablesToCreate.length > 0 || tablesToAlter.length > 0,
  };
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/migration/diff.test.ts`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add src/migration
git commit -m "$(cat <<'MSG'
feat(migration): additive schema diff with guarded recreation

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 8: Generate migration SQL

**Files:**
- Create: `packages/core/src/migration/generate.ts`
- Test: `packages/core/src/migration/generate.test.ts`

**Interfaces:**
- Consumes: `MigrationDiff`, `TableAlteration`, `Schema`, `TableDef`, `ColumnDef`, `quoteIdentifier`.
- Produces:
  - `interface MigrationOperation { description: string; sql: string[] }`
  - `class MigrationBlockedError extends Error { readonly tables: string[] }`
  - `function generateMigration(diff: MigrationDiff, declared: Schema, options: { allowRecreate: boolean }): MigrationOperation[]`
  - `function createTableSql(table: TableDef, tableName?: string): string[]`

- [ ] **Step 1: Write the failing test**

`src/migration/generate.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { generateMigration, MigrationBlockedError } from './generate';
import { diffSchema } from './diff';
import type { Schema, TableDef } from '../schema/types';

const table = (name: string, columns: TableDef['columns'], keys: TableDef['keys'] = []): TableDef => ({ name, columns, keys, library: false });
const text = (name: string, notNull = false, defaultValue?: string) => ({
  name, type: 'TEXT' as const, logical: 'text' as const, notNull, ...(defaultValue === undefined ? {} : { defaultValue }),
});
const real = (name: string) => ({ name, type: 'REAL' as const, logical: 'real' as const, notNull: false });
const schema = (...tables: TableDef[]): Schema => ({ tables });

describe('generateMigration', () => {
  it('generates CREATE TABLE with the primary key inline', () => {
    const declared = schema(table('t', [text('id', true, ''), real('qty')], [{ columns: ['id'], type: 'PRIMARY' }]));
    const ops = generateMigration(diffSchema(declared, schema()), declared, { allowRecreate: false });
    expect(ops[0]?.sql[0]).toBe(
      'CREATE TABLE "t" (\n  "id" TEXT NOT NULL DEFAULT \'\',\n  "qty" REAL,\n  PRIMARY KEY ("id")\n)',
    );
  });

  it('generates ADD COLUMN with the default so existing rows stay valid', () => {
    const declared = schema(table('t', [text('a'), text('b', true, 'x')]));
    const ops = generateMigration(diffSchema(declared, schema(table('t', [text('a')]))), declared, { allowRecreate: false });
    expect(ops[0]?.sql).toEqual(['ALTER TABLE "t" ADD COLUMN "b" TEXT NOT NULL DEFAULT \'x\'']);
  });

  it('generates CREATE INDEX IF NOT EXISTS', () => {
    const declared = schema(table('t', [text('a')], [{ columns: ['a'], type: 'INDEX', name: 'idx_t_a' }]));
    const ops = generateMigration(diffSchema(declared, schema(table('t', [text('a')]))), declared, { allowRecreate: false });
    expect(ops[0]?.sql).toEqual(['CREATE INDEX IF NOT EXISTS "idx_t_a" ON "t" ("a")']);
  });

  it('refuses a recreate unless it is allowed, naming the table', () => {
    const declared = schema(table('t', [real('a')]));
    const diff = diffSchema(declared, schema(table('t', [text('a')])));
    expect(() => generateMigration(diff, declared, { allowRecreate: false })).toThrow(MigrationBlockedError);
    try {
      generateMigration(diff, declared, { allowRecreate: false });
    } catch (error) {
      expect((error as MigrationBlockedError).tables).toEqual(['t']);
    }
  });

  it('recreates via a temp table copying the columns both schemas share', () => {
    const declared = schema(table('t', [real('a'), text('b')]));
    const diff = diffSchema(declared, schema(table('t', [text('a'), text('gone')])));
    const ops = generateMigration(diff, declared, { allowRecreate: true });
    expect(ops[0]?.sql).toEqual([
      'CREATE TABLE "t__migrate_new" (\n  "a" REAL,\n  "b" TEXT\n)',
      'INSERT INTO "t__migrate_new" ("a") SELECT "a" FROM "t"',
      'DROP TABLE "t"',
      'ALTER TABLE "t__migrate_new" RENAME TO "t"',
    ]);
  });
});
```

Note on the last test: `b` is a column the live table does not have, so the diff reports it in `columnsToAdd` and the copy carries only `a`. Keep that behaviour — copying a column the old table does not have would fail.

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/migration/generate.test.ts`
Expected: FAIL — `Failed to resolve import "./generate"`.

- [ ] **Step 3: Write `src/migration/generate.ts`**

```ts
import { quoteIdentifier } from '../db/sql';
import type { ColumnDef, Schema, TableDef } from '../schema/types';
import type { MigrationDiff, TableAlteration } from './diff';

/** One step of a migration: a human-readable description and the statements that carry it out, in order. */
export interface MigrationOperation {
  description: string;
  sql: string[];
}

/** Thrown when the schema cannot be reached without rebuilding a table and `allowRecreate` was not set. Lists every table that would have to be rebuilt. */
export class MigrationBlockedError extends Error {
  constructor(public readonly tables: string[]) {
    super(
      `Migration needs to recreate ${tables.join(', ')} (a column type or the primary key changed). ` +
        `Open the database with allowRecreate: true to let it, after confirming the data can be copied.`,
    );
    this.name = 'MigrationBlockedError';
  }
}

function literal(value: string | number | null | Uint8Array): string {
  if (typeof value === 'number') return String(value);
  if (value === null) return 'NULL';
  if (value instanceof Uint8Array) throw new Error('A BLOB cannot be a column default');
  return `'${value.replace(/'/g, "''")}'`;
}

function columnSql(column: ColumnDef): string {
  let sql = `${quoteIdentifier(column.name)} ${column.type}`;
  if (column.notNull) {
    sql += ' NOT NULL';
    if (column.defaultValue !== undefined) sql += ` DEFAULT ${literal(column.defaultValue)}`;
  } else if (column.defaultValue !== undefined) {
    sql += ` DEFAULT ${literal(column.defaultValue)}`;
  }
  return sql;
}

/** Renders `CREATE TABLE` plus the table's indexes. `tableName` overrides the name, which the recreation flow uses for its temporary table. */
export function createTableSql(table: TableDef, tableName = table.name): string[] {
  const parts = table.columns.map(columnSql);
  for (const key of table.keys) {
    if (key.type === 'PRIMARY') parts.push(`PRIMARY KEY (${key.columns.map(quoteIdentifier).join(', ')})`);
    else if (key.type === 'UNIQUE') parts.push(`UNIQUE (${key.columns.map(quoteIdentifier).join(', ')})`);
  }
  const sql = [`CREATE TABLE ${quoteIdentifier(tableName)} (\n  ${parts.join(',\n  ')}\n)`];
  if (tableName === table.name) {
    for (const key of table.keys) {
      if (key.type !== 'INDEX' || !key.name) continue;
      sql.push(
        createIndexSql(key, table.name)  // UNIQUE keys must emit CREATE UNIQUE INDEX, not a plain index,
      );
    }
  }
  return sql;
}

function recreateSql(alteration: TableAlteration, declared: TableDef): MigrationOperation {
  const temp = `${declared.name}__migrate_new`;
  const carried = declared.columns
    .filter((column) => !alteration.columnsToAdd.some((added) => added.name === column.name))
    .map((column) => quoteIdentifier(column.name));

  const sql = [
    ...createTableSql(declared, temp),
    `INSERT INTO ${quoteIdentifier(temp)} (${carried.join(', ')}) SELECT ${carried.join(', ')} FROM ${quoteIdentifier(declared.name)}`,
    `DROP TABLE ${quoteIdentifier(declared.name)}`,
    `ALTER TABLE ${quoteIdentifier(temp)} RENAME TO ${quoteIdentifier(declared.name)}`,
  ];
  for (const key of declared.keys) {
    if (key.type !== 'INDEX' || !key.name) continue;
    sql.push(
      createIndexSql(key, declared.name)  // UNIQUE keys must emit CREATE UNIQUE INDEX, not a plain index,
    );
  }
  return { description: `Recreate table ${declared.name}`, sql };
}

/**
 * Turns a diff into ordered statements: recreations first, then column and index
 * additions, then new tables, so an index on a new table cannot run before the
 * table exists. Throws `MigrationBlockedError` rather than silently rebuilding a
 * table the caller did not agree to rebuild.
 */
export function generateMigration(
  diff: MigrationDiff,
  declared: Schema,
  options: { allowRecreate: boolean },
): MigrationOperation[] {
  const blocked = diff.tablesToAlter.filter((a) => a.requiresRecreate).map((a) => a.table);
  if (blocked.length > 0 && !options.allowRecreate) throw new MigrationBlockedError(blocked);

  const byName = new Map(declared.tables.map((t) => [t.name, t]));
  const operations: MigrationOperation[] = [];

  for (const alteration of diff.tablesToAlter) {
    const table = byName.get(alteration.table);
    if (!table) continue;
    if (alteration.requiresRecreate) {
      operations.push(recreateSql(alteration, table));
      continue;
    }
    for (const column of alteration.columnsToAdd) {
      operations.push({
        description: `Add column ${alteration.table}.${column.name}`,
        sql: [`ALTER TABLE ${quoteIdentifier(alteration.table)} ADD COLUMN ${columnSql(column)}`],
      });
    }
    for (const key of alteration.keysToAdd) {
      if (!key.name) continue;
      operations.push({
        description: `Create index ${key.name}`,
        sql: [
          `CREATE INDEX IF NOT EXISTS ${quoteIdentifier(key.name)} ON ${quoteIdentifier(alteration.table)} (${key.columns.map(quoteIdentifier).join(', ')})`,
        ],
      });
    }
  }

  for (const table of diff.tablesToCreate) {
    operations.push({ description: `Create table ${table.name}`, sql: createTableSql(table) });
  }

  return operations;
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/migration/generate.test.ts`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add src/migration
git commit -m "$(cat <<'MSG'
feat(migration): SQL generation for create, add column, index and recreate

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 9: Run the migration — plan, auto, off, and the full matrix

This is the task the spec's migration test matrix belongs to: add table, add column, plan mode, type change with and without `allowRecreate`, plus idempotence and the additive guarantee, all against a real database.

**Files:**
- Create: `packages/core/src/migration/migrate.ts`
- Test: `packages/core/src/migration/migrate.test.ts`
- Modify: `packages/core/src/index.ts`

**Interfaces:**
- Consumes: `SQLiteAdapter`, `introspect`, `diffSchema`, `generateMigration`, `Schema`.
- Produces:
  - `type MigrationMode = 'auto' | 'plan' | 'off'`
  - `interface MigrationPlan { diff: MigrationDiff; operations: MigrationOperation[]; hasOperations: boolean; applied: boolean }`
  - `function planMigration(adapter: SQLiteAdapter, declared: Schema, options?: { allowRecreate?: boolean }): Promise<MigrationPlan>`
  - `function runMigration(adapter: SQLiteAdapter, declared: Schema, options: { mode: MigrationMode; allowRecreate?: boolean; onPlan?: (plan: MigrationPlan) => void }): Promise<MigrationPlan>`

- [ ] **Step 1: Write the failing test**

`src/migration/migrate.test.ts`:

```ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { introspect } from './introspect';
import { MigrationBlockedError } from './generate';
import { planMigration, runMigration } from './migrate';
import type { Schema } from '../schema/types';

function schemaWith(build: (s: SchemaBuilder) => void): Schema {
  const s = new SchemaBuilder();
  build(s);
  return s.build();
}

const v1 = schemaWith((s) => {
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
});

const v2 = schemaWith((s) => {
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.text('rowstate');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  s.table('c_ncr', (t) => {
    t.text('ncr_no');
  }).synced({ key: 'system_id', scope: ['ncr_no'] });
});

describe('runMigration', () => {
  let adapter: MemoryAdapter;

  beforeEach(async () => {
    adapter = new MemoryAdapter();
    await adapter.open();
  });

  afterEach(async () => {
    await adapter.close();
  });

  it('creates every declared table including the library tables', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    const live = await introspect(adapter);
    expect(live.tables.map((t) => t.name).sort()).toEqual(['c_work_task', 'outbox', 'sync_cursor']);
  });

  it('is a no-op the second time', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    const second = await runMigration(adapter, v1, { mode: 'auto' });
    expect(second.hasOperations).toBe(false);
    expect(second.applied).toBe(false);
  });

  it('adds a new column and a new table without touching data', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    await adapter.run(`INSERT INTO "c_work_task" ("system_id", "wo_no", "rowstate") VALUES (?, ?, ?)`, ['A', 3188, 'RELEASED']);

    await runMigration(adapter, v2, { mode: 'auto' });

    const row = await adapter.get<{ system_id: string; c_qty_installed: number | null }>(`SELECT * FROM "c_work_task"`);
    expect(row?.system_id).toBe('A');
    expect(row?.c_qty_installed).toBeNull();
    expect((await introspect(adapter)).tables.map((t) => t.name)).toContain('c_ncr');
  });

  it('plan mode reports the operations and executes nothing', async () => {
    const plan = await runMigration(adapter, v1, { mode: 'plan' });
    expect(plan.hasOperations).toBe(true);
    expect(plan.applied).toBe(false);
    expect(plan.operations.map((o) => o.description)).toContain('Create table c_work_task');
    expect((await introspect(adapter)).tables).toEqual([]);
  });

  it('off mode does nothing at all', async () => {
    const plan = await runMigration(adapter, v1, { mode: 'off' });
    expect(plan.operations).toEqual([]);
    expect((await introspect(adapter)).tables).toEqual([]);
  });

  it('refuses a type change without allowRecreate', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    const retyped = schemaWith((s) => {
      s.table('c_work_task', (t) => {
        t.text('wo_no');
        t.text('rowstate');
      }).synced({ key: 'system_id', scope: ['wo_no'] });
    });
    await expect(runMigration(adapter, retyped, { mode: 'auto' })).rejects.toThrow(MigrationBlockedError);
  });

  it('recreates and preserves data with allowRecreate', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    await adapter.run(`INSERT INTO "c_work_task" ("system_id", "wo_no", "rowstate") VALUES (?, ?, ?)`, ['A', 3188, 'RELEASED']);
    const retyped = schemaWith((s) => {
      s.table('c_work_task', (t) => {
        t.text('wo_no');
        t.text('rowstate');
      }).synced({ key: 'system_id', scope: ['wo_no'] });
    });

    await runMigration(adapter, retyped, { mode: 'auto', allowRecreate: true });

    const row = await adapter.get<{ system_id: string; wo_no: string }>(`SELECT * FROM "c_work_task"`);
    expect(row).toMatchObject({ system_id: 'A', wo_no: '3188' });
    const column = (await introspect(adapter)).tables.find((t) => t.name === 'c_work_task')?.columns.find((c) => c.name === 'wo_no');
    expect(column?.type).toBe('TEXT');
  });

  it('leaves a table the schema no longer declares in place', async () => {
    await runMigration(adapter, v2, { mode: 'auto' });
    await runMigration(adapter, v1, { mode: 'auto' });
    expect((await introspect(adapter)).tables.map((t) => t.name)).toContain('c_ncr');
  });

  it('rolls the whole migration back when one statement fails', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    // c_ncr exists with system_id as INTEGER, so the diff wants a recreate it is not allowed to do.
    await adapter.exec(`CREATE TABLE "c_ncr" ("system_id" INTEGER)`);
    await expect(runMigration(adapter, v2, { mode: 'auto' })).rejects.toThrow();
    const task = (await introspect(adapter)).tables.find((t) => t.name === 'c_work_task');
    expect(task?.columns.map((c) => c.name)).not.toContain('c_qty_installed');
  });

  it('planMigration never executes', async () => {
    const plan = await planMigration(adapter, v1);
    expect(plan.hasOperations).toBe(true);
    expect((await introspect(adapter)).tables).toEqual([]);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/migration/migrate.test.ts`
Expected: FAIL — `Failed to resolve import "./migrate"`.

- [ ] **Step 3: Write `src/migration/migrate.ts`**

```ts
import type { SQLiteAdapter } from '../adapters/adapter';
import type { Schema } from '../schema/types';
import { diffSchema, type MigrationDiff } from './diff';
import { generateMigration, type MigrationOperation } from './generate';
import { introspect } from './introspect';

/** `auto` migrates, `plan` computes the operations and executes nothing, `off` skips the whole step. */
export type MigrationMode = 'auto' | 'plan' | 'off';

/** What a migration decided: the diff behind it, the statements it produced, and whether they were executed. */
export interface MigrationPlan {
  diff: MigrationDiff;
  operations: MigrationOperation[];
  hasOperations: boolean;
  applied: boolean;
}

/**
 * Computes what would happen without touching the database. Useful in a startup
 * log, in tests, and as the `plan` mode of `Database.open`.
 */
export async function planMigration(
  adapter: SQLiteAdapter,
  declared: Schema,
  options: { allowRecreate?: boolean } = {},
): Promise<MigrationPlan> {
  const live = await introspect(adapter);
  const diff = diffSchema(declared, live);
  const operations = generateMigration(diff, declared, { allowRecreate: options.allowRecreate ?? false });
  return { diff, operations, hasOperations: operations.length > 0, applied: false };
}

/**
 * Brings the database up to the declared schema. Every statement runs inside one
 * transaction, so a migration either lands whole or not at all — a half-migrated
 * database is the one failure mode an offline app cannot recover from on its
 * own. `onPlan` is called with the plan before anything executes, which is how
 * an app logs what its users' databases are doing.
 */
export async function runMigration(
  adapter: SQLiteAdapter,
  declared: Schema,
  options: { mode: MigrationMode; allowRecreate?: boolean; onPlan?: (plan: MigrationPlan) => void },
): Promise<MigrationPlan> {
  if (options.mode === 'off') {
    const live = await introspect(adapter);
    return { diff: diffSchema(declared, live), operations: [], hasOperations: false, applied: false };
  }

  const plan = await planMigration(adapter, declared, { allowRecreate: options.allowRecreate ?? false });
  options.onPlan?.(plan);

  if (options.mode === 'plan' || !plan.hasOperations) return plan;

  await adapter.exec('BEGIN IMMEDIATE');
  try {
    for (const operation of plan.operations) {
      for (const sql of operation.sql) await adapter.exec(sql);
    }
    await adapter.exec('COMMIT');
  } catch (error) {
    await adapter.exec('ROLLBACK');
    throw error;
  }

  return { ...plan, applied: true };
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/migration/migrate.test.ts`
Expected: PASS, 10 tests.

- [ ] **Step 5: Export the migration layer**

Append to `src/index.ts`:

```ts
export { introspect } from './migration/introspect';
export { diffSchema } from './migration/diff';
export { generateMigration, createTableSql, MigrationBlockedError } from './migration/generate';
export { planMigration, runMigration } from './migration/migrate';
export type { MigrationDiff, TableAlteration, ColumnRetype } from './migration/diff';
export type { MigrationOperation } from './migration/generate';
export type { MigrationMode, MigrationPlan } from './migration/migrate';
```

- [ ] **Step 6: Commit**

```bash
git add src/migration src/index.ts
git commit -m "$(cat <<'MSG'
feat(migration): plan/auto/off migration runner with the full test matrix

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---
### Task 10: The invalidation bus and `Database.open` / read path

**Files:**
- Create: `packages/core/src/db/invalidation-bus.ts`
- Create: `packages/core/src/db/database.ts`
- Test: `packages/core/src/db/invalidation-bus.test.ts`
- Test: `packages/core/src/db/database.test.ts`

**Interfaces:**
- Consumes: `SQLiteAdapter`, `Schema`, `runMigration`, `MigrationMode`, `MigrationPlan`, `ScopeValues`, `Row`.
- Produces:
  - `type TableInvalidation = ReadonlyMap<string, ScopeValues | null> | null` (`null` = the writer could not name rows; every query on the table re-runs)
  - `interface InvalidationEvent { tables: ReadonlyMap<string, TableInvalidation> }`
  - `class InvalidationBus { subscribe(listener: (event: InvalidationEvent) => void): () => void; emit(event: InvalidationEvent): void }`
  - `class WriteLog { markRow(table: string, rowKey: string, scope?: ScopeValues | null): void; markTable(table: string): void; isEmpty(): boolean; toEvent(): InvalidationEvent }`
  - `interface DatabaseOptions { schema: Schema; adapter: SQLiteAdapter; migrate?: MigrationMode; allowRecreate?: boolean; onMigrationPlan?: (plan: MigrationPlan) => void }`
  - `class Database { static open(options: DatabaseOptions): Promise<Database>; readonly schema: Schema; readonly invalidations: InvalidationBus; query<T>(sql: string, params?: SqlValue[]): Promise<T[]>; queryOne<T>(...): Promise<T | undefined>; execute(sql: string, params?: SqlValue[], options?: { invalidates?: string[] }): Promise<RunResult>; close(): Promise<void> }`

- [ ] **Step 1: Write the failing tests**

`src/db/invalidation-bus.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest';
import { InvalidationBus, WriteLog } from './invalidation-bus';

describe('WriteLog', () => {
  it('starts empty', () => {
    expect(new WriteLog().isEmpty()).toBe(true);
  });

  it('collects rows with their scope', () => {
    const log = new WriteLog();
    log.markRow('c_work_task', 'A', { wo_no: 3188 });
    log.markRow('c_work_task', 'B', { wo_no: 3188 });
    const event = log.toEvent();
    expect([...(event.tables.get('c_work_task') ?? new Map()).keys()]).toEqual(['A', 'B']);
  });

  it('a whole-table mark wins over row marks for that table', () => {
    const log = new WriteLog();
    log.markRow('c_work_task', 'A', { wo_no: 3188 });
    log.markTable('c_work_task');
    expect(log.toEvent().tables.get('c_work_task')).toBeNull();
  });
});

describe('InvalidationBus', () => {
  it('delivers events to every subscriber until it unsubscribes', () => {
    const bus = new InvalidationBus();
    const first = vi.fn();
    const second = vi.fn();
    const stop = bus.subscribe(first);
    bus.subscribe(second);

    const log = new WriteLog();
    log.markTable('t');
    bus.emit(log.toEvent());
    stop();
    bus.emit(log.toEvent());

    expect(first).toHaveBeenCalledTimes(1);
    expect(second).toHaveBeenCalledTimes(2);
  });

  it('one listener throwing does not stop the others', () => {
    const bus = new InvalidationBus();
    const good = vi.fn();
    bus.subscribe(() => {
      throw new Error('boom');
    });
    bus.subscribe(good);
    const log = new WriteLog();
    log.markTable('t');
    expect(() => bus.emit(log.toEvent())).not.toThrow();
    expect(good).toHaveBeenCalledTimes(1);
  });
});
```

`src/db/database.test.ts`:

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from './database';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.text('rowstate');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  s.table('local_prefs', (t) => {
    t.text('key').notNull('');
    t.text('value');
  });
  return s.build();
}

describe('Database', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('opens, migrates and exposes the schema', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    expect(db.schema.tables.map((t) => t.name)).toContain('outbox');
    expect(await db.query('SELECT name FROM sqlite_master WHERE name = ?', ['c_work_task'])).toHaveLength(1);
  });

  it('queries with parameters and returns typed rows', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    await db.execute(`INSERT INTO "local_prefs" ("system_id", "key", "value") VALUES (?, ?, ?)`, ['p1', 'theme', 'dark']);
    const rows = await db.query<{ key: string; value: string }>('SELECT key, value FROM local_prefs WHERE key = ?', ['theme']);
    expect(rows).toEqual([{ key: 'theme', value: 'dark' }]);
    expect(await db.queryOne('SELECT key FROM local_prefs WHERE key = ?', ['missing'])).toBeUndefined();
  });

  it('emits one invalidation for the tables an execute declares', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: string[][] = [];
    db.invalidations.subscribe((event) => events.push([...event.tables.keys()]));
    await db.execute(`INSERT INTO "local_prefs" ("system_id", "key") VALUES (?, ?)`, ['p1', 'a'], { invalidates: ['local_prefs'] });
    expect(events).toEqual([['local_prefs']]);
  });

  it('emits nothing for an execute that declares no tables', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: unknown[] = [];
    db.invalidations.subscribe((event) => events.push(event));
    await db.execute(`INSERT INTO "local_prefs" ("system_id", "key") VALUES (?, ?)`, ['p1', 'a']);
    expect(events).toEqual([]);
  });

  it('passes the migration plan to onMigrationPlan in plan mode and creates nothing', async () => {
    const plans: number[] = [];
    db = await Database.open({
      schema: testSchema(),
      adapter: new MemoryAdapter(),
      migrate: 'plan',
      onMigrationPlan: (plan) => plans.push(plan.operations.length),
    });
    expect(plans[0]).toBeGreaterThan(0);
    await expect(db.query('SELECT 1 FROM c_work_task')).rejects.toThrow();
  });

  it('refuses to be used after close', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    await db.close();
    await expect(db.query('SELECT 1')).rejects.toThrow(/closed/i);
    db = undefined;
  });
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `npm test -- src/db`
Expected: FAIL — `Failed to resolve import "./invalidation-bus"` and `"./database"`.

- [ ] **Step 3: Write `src/db/invalidation-bus.ts`**

```ts
import type { ScopeValues } from '../types';

/**
 * What changed in one table during one transaction: a map from row key to that
 * row's scope values, or `null` when the writer could not name the rows (a raw
 * `execute`, a bulk statement, a full refresh). `null` means every live query on
 * the table must re-run.
 */
export type TableInvalidation = ReadonlyMap<string, ScopeValues | null> | null;

/** One event per committed write transaction, naming every table it touched. There is deliberately no per-row event. */
export interface InvalidationEvent {
  tables: ReadonlyMap<string, TableInvalidation>;
}

/** Accumulates what a transaction wrote so that exactly one event can be emitted after it commits. */
export class WriteLog {
  private readonly rows = new Map<string, Map<string, ScopeValues | null>>();
  private readonly wholeTables = new Set<string>();

  markRow(table: string, rowKey: string, scope: ScopeValues | null = null): void {
    let forTable = this.rows.get(table);
    if (!forTable) {
      forTable = new Map();
      this.rows.set(table, forTable);
    }
    forTable.set(rowKey, scope);
  }

  markTable(table: string): void {
    this.wholeTables.add(table);
  }

  isEmpty(): boolean {
    return this.rows.size === 0 && this.wholeTables.size === 0;
  }

  toEvent(): InvalidationEvent {
    const tables = new Map<string, TableInvalidation>();
    for (const [table, rows] of this.rows) tables.set(table, rows);
    for (const table of this.wholeTables) tables.set(table, null);
    return { tables };
  }
}

/**
 * Delivers one invalidation event per committed transaction to everything that
 * cares (live queries, the outbox counters, the app). A listener that throws is
 * reported to the console and skipped: one broken subscriber must not stop the
 * rest of the UI from refreshing.
 */
export class InvalidationBus {
  private readonly listeners = new Set<(event: InvalidationEvent) => void>();

  subscribe(listener: (event: InvalidationEvent) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  emit(event: InvalidationEvent): void {
    for (const listener of [...this.listeners]) {
      try {
        listener(event);
      } catch (error) {
        console.error('[declarative-sqlite] invalidation listener failed', error);
      }
    }
  }
}
```

- [ ] **Step 4: Write `src/db/database.ts` (read path only; Tasks 11–13 extend it)**

```ts
import type { RunResult, SQLiteAdapter } from '../adapters/adapter';
import { runMigration, type MigrationMode, type MigrationPlan } from '../migration/migrate';
import type { Schema } from '../schema/types';
import type { SqlValue } from '../types';
import { InvalidationBus, WriteLog } from './invalidation-bus';

/** Everything `Database.open` needs: the declared schema, an adapter to run it on, and how much freedom the migration has. */
export interface DatabaseOptions {
  schema: Schema;
  adapter: SQLiteAdapter;
  /** `auto` (default) migrates on open, `plan` only reports, `off` assumes the database already matches. */
  migrate?: MigrationMode;
  /** Allows the guarded table rebuild a storage-type change needs. Default false. */
  allowRecreate?: boolean;
  onMigrationPlan?: (plan: MigrationPlan) => void;
}

/**
 * The database handle: opens an adapter, migrates it to the declared schema and
 * owns the single write path. Reads are SQL strings with positional parameters;
 * writes go through `db.tables` or a transaction, so that every commit produces
 * exactly one invalidation event. Nothing above this class executes SQL.
 */
export class Database {
  readonly invalidations = new InvalidationBus();
  private closed = false;

  protected constructor(
    readonly schema: Schema,
    protected readonly adapter: SQLiteAdapter,
  ) {}

  static async open(options: DatabaseOptions): Promise<Database> {
    await options.adapter.open();
    const db = new Database(options.schema, options.adapter);
    await runMigration(options.adapter, options.schema, {
      mode: options.migrate ?? 'auto',
      allowRecreate: options.allowRecreate ?? false,
      ...(options.onMigrationPlan ? { onPlan: options.onMigrationPlan } : {}),
    });
    return db;
  }

  async query<T>(sql: string, params: SqlValue[] = []): Promise<T[]> {
    this.ensureOpen();
    return this.adapter.all<T>(sql, params);
  }

  async queryOne<T>(sql: string, params: SqlValue[] = []): Promise<T | undefined> {
    this.ensureOpen();
    return this.adapter.get<T>(sql, params);
  }

  /**
   * Runs one statement that returns no rows. `invalidates` names the tables the
   * statement wrote so live queries on them re-run; leave it out for a statement
   * that writes nothing (a PRAGMA, an ANALYZE). Prefer `db.tables` or a
   * transaction for ordinary writes — they report row keys and scopes, so only
   * the queries that actually care re-run.
   */
  async execute(sql: string, params: SqlValue[] = [], options: { invalidates?: string[] } = {}): Promise<RunResult> {
    this.ensureOpen();
    const result = await this.adapter.run(sql, params);
    const invalidates = options.invalidates ?? [];
    if (invalidates.length > 0) {
      const log = new WriteLog();
      for (const table of invalidates) log.markTable(table);
      this.invalidations.emit(log.toEvent());
    }
    return result;
  }

  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    await this.adapter.close();
  }

  protected ensureOpen(): void {
    if (this.closed) throw new Error('Database is closed');
  }
}
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `npm test -- src/db`
Expected: PASS, 11 tests.

- [ ] **Step 6: Commit**

```bash
git add src/db
git commit -m "$(cat <<'MSG'
feat(db): invalidation bus and the Database read path

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 11: Transactions and the single write path

One adapter is one connection, so two overlapping `transaction()` calls would interleave their `BEGIN`s. The database serialises them through a promise queue; everything that writes — outbox, pull applier, draft commits — goes through it, which is what makes "one emission per transaction" true rather than aspirational.

**Files:**
- Create: `packages/core/src/db/transaction.ts`
- Modify: `packages/core/src/db/database.ts`
- Test: `packages/core/src/db/transaction.test.ts`

**Interfaces:**
- Consumes: `SQLiteAdapter`, `WriteLog`, `SqlValue`, `ScopeValues`.
- Produces:
  - `class Transaction { query<T>(sql, params?): Promise<T[]>; queryOne<T>(sql, params?): Promise<T | undefined>; execute(sql, params?, options?: { invalidates?: string[] }): Promise<RunResult>; markWritten(table: string, rowKey: string, scope?: ScopeValues | null): void; markTableWritten(table: string): void }`
  - On `Database`: `transaction<T>(work: (tx: Transaction) => Promise<T>): Promise<T>`

- [ ] **Step 1: Write the failing test**

`src/db/transaction.test.ts`:

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from './database';
import type { InvalidationEvent } from './invalidation-bus';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

describe('Database.transaction', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('commits and emits exactly one event for many writes', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: InvalidationEvent[] = [];
    db.invalidations.subscribe((event) => events.push(event));

    await db.transaction(async (tx) => {
      for (const id of ['A', 'B', 'C']) {
        await tx.execute(`INSERT INTO "c_work_task" ("system_id", "wo_no") VALUES (?, ?)`, [id, 3188]);
        tx.markWritten('c_work_task', id, { wo_no: 3188 });
      }
    });

    expect(events).toHaveLength(1);
    expect([...(events[0]?.tables.get('c_work_task') ?? new Map()).keys()]).toEqual(['A', 'B', 'C']);
  });

  it('rolls back and emits nothing when the work throws', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: InvalidationEvent[] = [];
    db.invalidations.subscribe((event) => events.push(event));

    await expect(
      db.transaction(async (tx) => {
        await tx.execute(`INSERT INTO "c_work_task" ("system_id", "wo_no") VALUES (?, ?)`, ['A', 3188]);
        tx.markWritten('c_work_task', 'A', { wo_no: 3188 });
        throw new Error('nope');
      }),
    ).rejects.toThrow('nope');

    expect(await db.query('SELECT system_id FROM c_work_task')).toEqual([]);
    expect(events).toEqual([]);
  });

  it('emits nothing when a transaction wrote nothing', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: InvalidationEvent[] = [];
    db.invalidations.subscribe((event) => events.push(event));
    await db.transaction(async (tx) => {
      await tx.query('SELECT 1');
    });
    expect(events).toEqual([]);
  });

  it('serialises overlapping transactions instead of interleaving BEGIN', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const order: string[] = [];

    const first = db.transaction(async (tx) => {
      order.push('first-start');
      await tx.execute(`INSERT INTO "c_work_task" ("system_id", "wo_no") VALUES (?, ?)`, ['A', 1]);
      await new Promise((resolve) => setTimeout(resolve, 10));
      order.push('first-end');
    });
    const second = db.transaction(async (tx) => {
      order.push('second-start');
      await tx.execute(`INSERT INTO "c_work_task" ("system_id", "wo_no") VALUES (?, ?)`, ['B', 1]);
      order.push('second-end');
    });

    await Promise.all([first, second]);
    expect(order).toEqual(['first-start', 'first-end', 'second-start', 'second-end']);
    expect(await db.query('SELECT system_id FROM c_work_task ORDER BY system_id')).toHaveLength(2);
  });

  it('returns the work function result', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    expect(await db.transaction(async () => 42)).toBe(42);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/db/transaction.test.ts`
Expected: FAIL — `db.transaction is not a function`.

- [ ] **Step 3: Write `src/db/transaction.ts`**

```ts
import type { RunResult, SQLiteAdapter } from '../adapters/adapter';
import type { ScopeValues, SqlValue } from '../types';
import type { WriteLog } from './invalidation-bus';

/**
 * The handle a transaction body works through. It reads and writes like the
 * database does, but every write must say which rows it touched — either by
 * calling `markWritten` with the row key and its scope values, or by declaring
 * the tables it could not be precise about. What is marked here becomes the one
 * invalidation event emitted after the transaction commits.
 */
export class Transaction {
  constructor(
    private readonly adapter: SQLiteAdapter,
    private readonly log: WriteLog,
  ) {}

  async query<T>(sql: string, params: SqlValue[] = []): Promise<T[]> {
    return this.adapter.all<T>(sql, params);
  }

  async queryOne<T>(sql: string, params: SqlValue[] = []): Promise<T | undefined> {
    return this.adapter.get<T>(sql, params);
  }

  async execute(sql: string, params: SqlValue[] = [], options: { invalidates?: string[] } = {}): Promise<RunResult> {
    const result = await this.adapter.run(sql, params);
    for (const table of options.invalidates ?? []) this.log.markTable(table);
    return result;
  }

  markWritten(table: string, rowKey: string, scope: ScopeValues | null = null): void {
    this.log.markRow(table, rowKey, scope);
  }

  markTableWritten(table: string): void {
    this.log.markTable(table);
  }
}
```

- [ ] **Step 4: Add `transaction` to `src/db/database.ts`**

Add the import and two members:

```ts
import { Transaction } from './transaction';

// inside class Database:
  private writeQueue: Promise<unknown> = Promise.resolve();

  /**
   * Runs `work` inside one SQLite transaction. Transactions are serialised —
   * one adapter is one connection — so overlapping callers queue rather than
   * interleave their BEGINs. On success the transaction's write log becomes
   * exactly one invalidation event; on failure everything rolls back and no
   * event is emitted, so a live query can never show a row that was undone.
   */
  async transaction<T>(work: (tx: Transaction) => Promise<T>): Promise<T> {
    this.ensureOpen();
    const run = this.writeQueue.then(() => this.runTransaction(work));
    this.writeQueue = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  private async runTransaction<T>(work: (tx: Transaction) => Promise<T>): Promise<T> {
    const log = new WriteLog();
    const tx = new Transaction(this.adapter, log);
    await this.adapter.exec('BEGIN IMMEDIATE');
    let result: T;
    try {
      result = await work(tx);
      await this.adapter.exec('COMMIT');
    } catch (error) {
      await this.adapter.exec('ROLLBACK');
      throw error;
    }
    if (!log.isEmpty()) this.invalidations.emit(log.toEvent());
    return result;
  }
```

- [ ] **Step 5: Run the test and watch it pass**

Run: `npm test -- src/db/transaction.test.ts`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add src/db
git commit -m "$(cat <<'MSG'
feat(db): serialised transactions with one invalidation per commit

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 12: Typed `db.tables`, the server-truth guard and the write capability

A synced table has no write methods on `db.tables` — not a method that throws, no method at all, so a cast cannot rescue the caller. The sync layer writes server truth through a `ServerWriter` obtained with a capability object minted in `sync/` and never exported from the package entry.

**Files:**
- Create: `packages/core/src/db/tables.ts`
- Create: `packages/core/src/db/server-truth.ts`
- Modify: `packages/core/src/db/database.ts`
- Modify: `packages/core/src/index.ts`
- Test: `packages/core/src/db/tables.test.ts`

**Interfaces:**
- Consumes: `Database`, `Transaction`, `TableDef`, `Row`, `quoteIdentifier`.
- Produces:
  - `type RowMap = Record<string, Record<string, unknown>>`
  - `interface TableApi<TRow> { get(key: string): Promise<TRow | undefined>; insert(row: TRow): Promise<void>; update(key: string, patch: Partial<TRow>): Promise<number>; upsert(row: TRow): Promise<void>; delete(key: string): Promise<number> }`
  - `interface SyncedTableApi<TRow> { get(key: string): Promise<TRow | undefined> }`
  - `type TableApis<TRows extends RowMap, TSynced extends keyof TRows> = { [K in keyof TRows]: K extends TSynced ? SyncedTableApi<TRows[K]> : TableApi<TRows[K]> }`
  - `function buildTableApis(db: Database): Record<string, TableApi<Row> | SyncedTableApi<Row>>`
  - `function rowScope(table: TableDef, values: Record<string, unknown>): ScopeValues | null`
  - `interface ServerWriteCapability`, `function createServerWriteCapability(): ServerWriteCapability` (internal; not exported from `src/index.ts`)
  - `interface ServerWriter { upsert(tx: Transaction, table: string, row: Row): Promise<void>; setColumns(tx: Transaction, table: string, key: string, values: Row): Promise<void>; delete(tx: Transaction, table: string, key: string): Promise<number> }`
  - `function serverWriter(db: Database, capability: ServerWriteCapability): ServerWriter`
  - On `Database`: `readonly tables: Record<string, TableApi<Row> | SyncedTableApi<Row>>`, `tableDef(name: string): TableDef`, `keyColumn(name: string): string`, and a generic `Database.open<TRows, TSynced>` overload typing `tables`.

- [ ] **Step 1: Write the failing test**

`src/db/tables.test.ts`:

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from './database';
import { createServerWriteCapability, serverWriter } from './server-truth';
import type { InvalidationEvent } from './invalidation-bus';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  s.table('local_prefs', (t) => {
    t.text('key').notNull('');
    t.text('value');
  });
  return s.build();
}

describe('db.tables', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('inserts, reads, updates and deletes a local table', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const prefs = db.tables['local_prefs'];
    if (!prefs || !('insert' in prefs)) throw new Error('local_prefs should be writable');

    await prefs.insert({ system_id: 'p1', key: 'theme', value: 'dark' });
    expect(await prefs.get('p1')).toMatchObject({ key: 'theme', value: 'dark' });

    expect(await prefs.update('p1', { value: 'light' })).toBe(1);
    expect(await prefs.get('p1')).toMatchObject({ value: 'light' });

    await prefs.upsert({ system_id: 'p2', key: 'lang', value: 'nb' });
    expect(await prefs.get('p2')).toBeDefined();

    expect(await prefs.delete('p1')).toBe(1);
    expect(await prefs.get('p1')).toBeUndefined();
  });

  it('exposes no write methods at all on a synced table', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const task = db.tables['c_work_task'];
    expect(task && 'get' in task).toBe(true);
    expect(task && 'insert' in task).toBe(false);
    expect(task && 'update' in task).toBe(false);
    expect(task && 'delete' in task).toBe(false);
  });

  it('reports the row key and scope of every write', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: InvalidationEvent[] = [];
    db.invalidations.subscribe((event) => events.push(event));

    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, system_removed: 0, sync_seq: 10 });
    });

    expect(events).toHaveLength(1);
    expect(events[0]?.tables.get('c_work_task')?.get('A')).toEqual({ wo_no: 3188 });
  });

  it('server writer upsert replaces only the columns it is given', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, system_removed: 0, sync_seq: 10 });
    });
    await db.transaction(async (tx) => {
      await writer.setColumns(tx, 'c_work_task', 'A', { c_qty_installed: 9 });
    });
    expect(await db.queryOne('SELECT wo_no, c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      wo_no: 3188,
      c_qty_installed: 9,
    });
  });

  it('refuses a forged capability', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    expect(() => serverWriter(db, {} as ReturnType<typeof createServerWriteCapability>)).toThrow(/capability/i);
  });

  it('looks up a row scope even when the patch does not carry the scope columns', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, system_removed: 0, sync_seq: 10 });
    });

    const events: InvalidationEvent[] = [];
    db.invalidations.subscribe((event) => events.push(event));
    await db.transaction(async (tx) => {
      await writer.setColumns(tx, 'c_work_task', 'A', { c_qty_installed: 6 });
    });
    expect(events[0]?.tables.get('c_work_task')?.get('A')).toEqual({ wo_no: 3188 });
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/db/tables.test.ts`
Expected: FAIL — `Failed to resolve import "./server-truth"`.

- [ ] **Step 3: Write `src/db/tables.ts`**

```ts
import type { Row, ScopeValues, SqlValue } from '../types';
import type { TableDef } from '../schema/types';
import type { Transaction } from './transaction';
import { quoteIdentifier } from './sql';

/** The application's row types, keyed by table name. Supplied as a type argument to `Database.open`; the library never infers row shapes from the fluent builder. */
export type RowMap = Record<string, Record<string, unknown>>;

/** Typed CRUD for a table the application owns. Reads beyond `get` are SQL strings through `db.query`. */
export interface TableApi<TRow> {
  get(key: string): Promise<TRow | undefined>;
  insert(row: TRow): Promise<void>;
  update(key: string, patch: Partial<TRow>): Promise<number>;
  upsert(row: TRow): Promise<void>;
  delete(key: string): Promise<number>;
}

/** What a `.synced()` table exposes: reads only. Its writes belong to the pull applier and the outbox committer. */
export interface SyncedTableApi<TRow> {
  get(key: string): Promise<TRow | undefined>;
}

/** `db.tables` as the application sees it: synced tables read-only, everything else full CRUD. */
export type TableApis<TRows extends RowMap, TSynced extends keyof TRows> = {
  [K in keyof TRows]: K extends TSynced ? SyncedTableApi<TRows[K]> : TableApi<TRows[K]>;
};

/** Coerces a JavaScript value to something SQLite can bind: booleans become 1/0, `undefined` becomes null. */
export function toSqlValue(value: unknown): SqlValue {
  if (value === undefined || value === null) return null;
  if (typeof value === 'boolean') return value ? 1 : 0;
  if (typeof value === 'number' || typeof value === 'string') return value;
  if (value instanceof Uint8Array) return value;
  return String(value);
}

/** Reads a row's scope values out of the values being written, or returns null when the table has no scope. */
export function rowScope(table: TableDef, values: Record<string, unknown>): ScopeValues | null {
  const scopeColumns = table.synced?.scope ?? [];
  if (scopeColumns.length === 0) return null;
  const scope: ScopeValues = {};
  for (const column of scopeColumns) {
    const value = values[column];
    if (value === undefined || value === null) return null;
    scope[column] = typeof value === 'number' ? value : String(value);
  }
  return scope;
}

/** Builds the `INSERT ... ON CONFLICT DO UPDATE` statement used by both `upsert` and the server writer. */
export function upsertSql(table: TableDef, columns: string[], keyColumn: string): string {
  const names = columns.map(quoteIdentifier).join(', ');
  const placeholders = columns.map(() => '?').join(', ');
  const assignments = columns
    .filter((c) => c !== keyColumn)
    .map((c) => `${quoteIdentifier(c)} = excluded.${quoteIdentifier(c)}`)
    .join(', ');
  const update = assignments.length > 0 ? `DO UPDATE SET ${assignments}` : 'DO NOTHING';
  return `INSERT INTO ${quoteIdentifier(table.name)} (${names}) VALUES (${placeholders}) ON CONFLICT(${quoteIdentifier(keyColumn)}) ${update}`;
}

/** Writes one row's columns inside an open transaction and marks it on the write log. Shared by `db.tables` and the server writer. */
export async function writeRow(
  tx: Transaction,
  table: TableDef,
  keyColumn: string,
  key: string,
  values: Record<string, unknown>,
  mode: 'insert' | 'upsert' | 'update',
): Promise<number> {
  const payload: Record<string, unknown> = { ...values, [keyColumn]: key };
  const columns = Object.keys(payload).filter((c) => table.columns.some((col) => col.name === c));
  const params = columns.map((c) => toSqlValue(payload[c]));

  let changes: number;
  if (mode === 'update') {
    const assignments = columns.filter((c) => c !== keyColumn);
    if (assignments.length === 0) return 0;
    const sql = `UPDATE ${quoteIdentifier(table.name)} SET ${assignments.map((c) => `${quoteIdentifier(c)} = ?`).join(', ')} WHERE ${quoteIdentifier(keyColumn)} = ?`;
    const result = await tx.execute(sql, [...assignments.map((c) => toSqlValue(payload[c])), key]);
    changes = result.changes;
  } else if (mode === 'insert') {
    const sql = `INSERT INTO ${quoteIdentifier(table.name)} (${columns.map(quoteIdentifier).join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`;
    const result = await tx.execute(sql, params);
    changes = result.changes;
  } else {
    const result = await tx.execute(upsertSql(table, columns, keyColumn), params);
    changes = result.changes;
  }

  let scope = rowScope(table, payload);
  if (scope === null && (table.synced?.scope.length ?? 0) > 0) {
    const scopeColumns = table.synced?.scope ?? [];
    const existing = await tx.queryOne<Record<string, SqlValue>>(
      `SELECT ${scopeColumns.map(quoteIdentifier).join(', ')} FROM ${quoteIdentifier(table.name)} WHERE ${quoteIdentifier(keyColumn)} = ?`,
      [key],
    );
    if (existing) scope = rowScope(table, existing);
  }
  tx.markWritten(table.name, key, scope);
  return changes;
}
```

- [ ] **Step 4: Write `src/db/server-truth.ts`**

```ts
import { quoteIdentifier } from './sql';
import type { Database } from './database';
import type { Transaction } from './transaction';
import { rowScope, writeRow } from './tables';
import type { Row } from '../types';

const SERVER_WRITE = Symbol('declarative-sqlite:server-write');

/**
 * The token that unlocks writing to `.synced()` tables. It is minted inside the
 * sync runtime and is not exported from the package entry point, so application
 * code cannot obtain one — server truth changes only when the pull applier or
 * the outbox committer says so.
 */
export interface ServerWriteCapability {
  readonly [SERVER_WRITE]: true;
}

export function createServerWriteCapability(): ServerWriteCapability {
  return { [SERVER_WRITE]: true };
}

/** The write methods `db.tables` withholds from synced tables. Every method takes an open transaction, so a pull page is one commit and one invalidation. */
export interface ServerWriter {
  upsert(tx: Transaction, table: string, row: Row): Promise<void>;
  setColumns(tx: Transaction, table: string, key: string, values: Row): Promise<void>;
  delete(tx: Transaction, table: string, key: string): Promise<number>;
}

/**
 * Hands out the server-truth write path for a database, in exchange for a
 * capability only the sync runtime holds. Throws if the capability is forged.
 */
export function serverWriter(db: Database, capability: ServerWriteCapability): ServerWriter {
  if (!capability || capability[SERVER_WRITE] !== true) {
    throw new Error('serverWriter requires the sync runtime capability object');
  }

  return {
    async upsert(tx, table, row) {
      const def = db.tableDef(table);
      const keyColumn = db.keyColumn(table);
      const key = String(row[keyColumn] ?? '');
      if (!key) throw new Error(`${table}: cannot upsert a row without ${keyColumn}`);
      await writeRow(tx, def, keyColumn, key, row, 'upsert');
    },

    async setColumns(tx, table, key, values) {
      const def = db.tableDef(table);
      await writeRow(tx, def, db.keyColumn(table), key, values, 'update');
    },

    async delete(tx, table, key) {
      const def = db.tableDef(table);
      const keyColumn = db.keyColumn(table);
      const scopeColumns = def.synced?.scope ?? [];
      const existing =
        scopeColumns.length > 0
          ? await tx.queryOne<Row>(
              `SELECT ${scopeColumns.map(quoteIdentifier).join(', ')} FROM ${quoteIdentifier(table)} WHERE ${quoteIdentifier(keyColumn)} = ?`,
              [key],
            )
          : undefined;
      const result = await tx.execute(`DELETE FROM ${quoteIdentifier(table)} WHERE ${quoteIdentifier(keyColumn)} = ?`, [key]);
      tx.markWritten(table, key, existing ? rowScope(def, existing) : null);
      return result.changes;
    },
  };
}
```

- [ ] **Step 5: Extend `src/db/database.ts` with `tables`, `tableDef`, `keyColumn` and the typed `open`**

```ts
import { SYSTEM_ID_COLUMN } from '../schema/table-builder';
import { writeRow, type RowMap, type SyncedTableApi, type TableApi, type TableApis } from './tables';
import { quoteIdentifier } from './sql';
import type { Row } from '../types';
import type { TableDef } from '../schema/types';

// inside class Database, after the constructor:

  /**
   * Typed CRUD per table, generated from the schema. A `.synced()` table appears
   * here with `get` only: its write methods do not exist, so the server-truth
   * rule is enforced by the object, not by a runtime check a cast could dodge.
   */
  readonly tables: Record<string, TableApi<Row> | SyncedTableApi<Row>> = {};

  /** The declared definition of one table. Throws if the schema does not declare it. */
  tableDef(name: string): TableDef {
    const table = this.schema.tables.find((t) => t.name === name);
    if (!table) throw new Error(`Table ${name} is not in the schema`);
    return table;
  }

  /** The column holding a table's row key: the `.synced()` key, or `system_id`. */
  keyColumn(name: string): string {
    return this.tableDef(name).synced?.key ?? SYSTEM_ID_COLUMN;
  }

  private buildTableApis(): void {
    for (const table of this.schema.tables) {
      const keyColumn = table.synced?.key ?? SYSTEM_ID_COLUMN;
      const get = async (key: string): Promise<Row | undefined> =>
        this.queryOne<Row>(`SELECT * FROM ${quoteIdentifier(table.name)} WHERE ${quoteIdentifier(keyColumn)} = ?`, [key]);

      if (table.synced) {
        this.tables[table.name] = { get };
        continue;
      }

      this.tables[table.name] = {
        get,
        insert: async (row: Row) => {
          await this.transaction(async (tx) => writeRow(tx, table, keyColumn, String(row[keyColumn] ?? ''), row, 'insert'));
        },
        update: async (key: string, patch: Partial<Row>) =>
          this.transaction(async (tx) => writeRow(tx, table, keyColumn, key, patch as Row, 'update')),
        upsert: async (row: Row) => {
          await this.transaction(async (tx) => writeRow(tx, table, keyColumn, String(row[keyColumn] ?? ''), row, 'upsert'));
        },
        delete: async (key: string) =>
          this.transaction(async (tx) => {
            const result = await tx.execute(
              `DELETE FROM ${quoteIdentifier(table.name)} WHERE ${quoteIdentifier(keyColumn)} = ?`,
              [key],
            );
            tx.markWritten(table.name, key, null);
            return result.changes;
          }),
      };
    }
  }
```

Call `db.buildTableApis()` at the end of `Database.open`, after the migration has run. Add the typed overload so the app gets its row types:

```ts
  /**
   * Opens and migrates a database. Supply the application's row types and the
   * names of its synced tables to get a typed `db.tables`:
   * `Database.open<AppRows, 'c_work_task' | 'c_work_order'>({ ... })`.
   */
  static async open<TRows extends RowMap = RowMap, TSynced extends keyof TRows = never>(
    options: DatabaseOptions,
  ): Promise<Database & { tables: TableApis<TRows, TSynced> }> {
    // existing body, with the final return cast:
    // return db as Database & { tables: TableApis<TRows, TSynced> };
  }
```

- [ ] **Step 6: Run the test and watch it pass**

Run: `npm test -- src/db/tables.test.ts`
Expected: PASS, 6 tests.

- [ ] **Step 7: Export the db layer (but NOT the capability)**

Append to `src/index.ts`:

```ts
export { Database } from './db/database';
export { Transaction } from './db/transaction';
export { InvalidationBus } from './db/invalidation-bus';
export { quoteIdentifier } from './db/sql';
export { toSqlValue } from './db/tables';
export type { DatabaseOptions } from './db/database';
export type { InvalidationEvent, TableInvalidation } from './db/invalidation-bus';
export type { RowMap, TableApi, SyncedTableApi, TableApis } from './db/tables';
export type { ServerWriter } from './db/server-truth';
```

`createServerWriteCapability` is deliberately absent: only `src/sync/runtime.ts` imports it.

- [ ] **Step 8: Commit**

```bash
git add src/db src/index.ts
git commit -m "$(cat <<'MSG'
feat(db): typed db.tables, server-truth guard and the write capability

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---
### Task 13: Snapshot diffing with row identity preservation

The rule that keeps React cheap: a row object that did not change keeps its identity across emissions, so `React.memo` and `useMemo` skip it. The same function answers "did anything change at all", which is what stops identical results from being emitted.

**Files:**
- Create: `packages/core/src/live/diff-rows.ts`
- Test: `packages/core/src/live/diff-rows.test.ts`

**Interfaces:**
- Consumes: `Row`.
- Produces: `function diffRows<T extends Record<string, unknown>>(previous: T[], next: T[], key: string): { rows: T[]; changed: boolean }`

- [ ] **Step 1: Write the failing test**

`src/live/diff-rows.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { diffRows } from './diff-rows';

describe('diffRows', () => {
  it('reports no change and returns the previous array for an identical result', () => {
    const previous = [{ system_id: 'A', qty: 1 }];
    const next = [{ system_id: 'A', qty: 1 }];
    const result = diffRows(previous, next, 'system_id');
    expect(result.changed).toBe(false);
    expect(result.rows).toBe(previous);
  });

  it('keeps the identity of rows that did not change', () => {
    const a = { system_id: 'A', qty: 1 };
    const b = { system_id: 'B', qty: 2 };
    const result = diffRows([a, b], [{ system_id: 'A', qty: 1 }, { system_id: 'B', qty: 3 }], 'system_id');
    expect(result.changed).toBe(true);
    expect(result.rows[0]).toBe(a);
    expect(result.rows[1]).not.toBe(b);
    expect(result.rows[1]).toEqual({ system_id: 'B', qty: 3 });
  });

  it('detects a new row, a removed row and a reorder', () => {
    const a = { system_id: 'A' };
    const b = { system_id: 'B' };
    expect(diffRows([a], [a, b], 'system_id').changed).toBe(true);
    expect(diffRows([a, b], [a], 'system_id').changed).toBe(true);
    expect(diffRows([a, b], [{ system_id: 'B' }, { system_id: 'A' }], 'system_id').changed).toBe(true);
  });

  it('treats a null and a missing column as different values', () => {
    expect(diffRows([{ system_id: 'A', qty: null }], [{ system_id: 'A' }], 'system_id').changed).toBe(true);
  });

  it('handles duplicate keys by position', () => {
    const rows = [{ system_id: 'A', n: 1 }, { system_id: 'A', n: 2 }];
    expect(diffRows(rows, [{ system_id: 'A', n: 1 }, { system_id: 'A', n: 2 }], 'system_id').changed).toBe(false);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/live/diff-rows.test.ts`
Expected: FAIL — `Failed to resolve import "./diff-rows"`.

- [ ] **Step 3: Write `src/live/diff-rows.ts`**

```ts
function sameValues(a: Record<string, unknown>, b: Record<string, unknown>): boolean {
  const aKeys = Object.keys(a);
  const bKeys = Object.keys(b);
  if (aKeys.length !== bKeys.length) return false;
  for (const key of aKeys) {
    if (!(key in b)) return false;
    if (!Object.is(a[key], b[key])) return false;
  }
  return true;
}

/**
 * Compares a fresh query result with the previous snapshot. Rows that are
 * unchanged — same key, same columns, same values — are carried over by
 * reference, so a React list re-renders only the rows that actually moved.
 * `changed` is false when the whole result is identical in order and content,
 * which is what lets a live query stay silent after a pull that wrote nothing
 * it cares about. Rows are matched by position first and by key second, so a
 * result with duplicate keys still diffs sensibly.
 */
export function diffRows<T extends Record<string, unknown>>(
  previous: T[],
  next: T[],
  key: string,
): { rows: T[]; changed: boolean } {
  if (previous.length === next.length) {
    let identical = true;
    const rows: T[] = new Array(next.length);
    for (let i = 0; i < next.length; i++) {
      const before = previous[i] as T;
      const after = next[i] as T;
      if (before !== undefined && before[key] === after[key] && sameValues(before, after)) {
        rows[i] = before;
      } else {
        rows[i] = after;
        identical = false;
      }
    }
    if (identical) return { rows: previous, changed: false };
    return { rows, changed: true };
  }

  const byKey = new Map<string, T[]>();
  for (const row of previous) {
    const id = String(row[key]);
    const bucket = byKey.get(id);
    if (bucket) bucket.push(row);
    else byKey.set(id, [row]);
  }

  const rows = next.map((row) => {
    const candidates = byKey.get(String(row[key]));
    const match = candidates?.find((candidate) => sameValues(candidate, row));
    return match ?? row;
  });

  return { rows, changed: true };
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/live/diff-rows.test.ts`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add src/live
git commit -m "$(cat <<'MSG'
feat(live): snapshot diffing that preserves row identity

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 14: `LiveQuery` and scope-aware invalidation

**Files:**
- Create: `packages/core/src/live/live-query.ts`
- Create: `packages/core/src/live/registry.ts`
- Modify: `packages/core/src/db/database.ts`
- Test: `packages/core/src/live/live-query.test.ts`

**Interfaces:**
- Consumes: `Database`, `InvalidationEvent`, `scopeMatches`, `diffRows`, `ScopeValues`, `SqlValue`, `Row`.
- Produces:
  - `interface ReadDependency { table: string; scope?: ScopeValues }`
  - `interface LiveQuerySpec { sql: string; params?: SqlValue[]; reads: ReadDependency[]; key: string; minInterval?: number; overlayTable?: string }`
  - `type RowTransform = (table: string, rows: Row[]) => Row[]`
  - `class LiveQuery<T> { readonly spec: LiveQuerySpec; subscribe(listener: (rows: T[]) => void): () => void; snapshot(): T[]; refresh(): Promise<void>; close(): void; matches(event: InvalidationEvent): boolean }`
  - `class LiveRegistry { constructor(db: Database); create<T>(spec: LiveQuerySpec): LiveQuery<T>; setRowTransform(transform: RowTransform | undefined): void; closeAll(): void }`
  - On `Database`: `live<T>(spec: LiveQuerySpec): LiveQuery<T>`, `setRowTransform(transform: RowTransform | undefined): void`

- [ ] **Step 1: Write the failing test**

`src/live/live-query.test.ts`:

```ts
import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('description');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function openDb() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const put = (id: string, wo: number, qty: number, description = '') =>
    db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: id, wo_no: wo, c_qty_installed: qty, description, sync_seq: 1, system_removed: 0 });
    });
  return { db, put };
}

/** Waits for the microtask + query round-trip a live query needs to deliver. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('LiveQuery', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('delivers the first result to a subscriber', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1);

    const query = db.live<{ system_id: string; c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const seen: unknown[][] = [];
    query.subscribe((rows) => seen.push(rows));
    await settle();

    expect(seen).toEqual([[{ system_id: 'A', c_qty_installed: 1 }]]);
    query.close();
  });

  it('re-runs when a row in its scope is written', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1);

    const query = db.live<{ system_id: string; c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const seen: unknown[][] = [];
    query.subscribe((rows) => seen.push(rows));
    await settle();

    await opened.put('A', 3188, 5);
    await settle();

    expect(seen).toHaveLength(2);
    expect(seen[1]).toEqual([{ system_id: 'A', c_qty_installed: 5 }]);
    query.close();
  });

  it('does not re-run for a write in a foreign scope', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1);

    const query = db.live({
      sql: 'SELECT system_id FROM c_work_task WHERE wo_no = ?',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const listener = vi.fn();
    query.subscribe(listener);
    await settle();
    listener.mockClear();

    await opened.put('Z', 4000, 1);
    await settle();

    expect(listener).not.toHaveBeenCalled();
    query.close();
  });

  it('re-runs when the writer could not name the rows', async () => {
    const opened = await openDb();
    db = opened.db;
    const query = db.live({
      sql: 'SELECT system_id FROM c_work_task WHERE wo_no = ?',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const listener = vi.fn();
    query.subscribe(listener);
    await settle();
    listener.mockClear();

    await db.execute('DELETE FROM c_work_task', [], { invalidates: ['c_work_task'] });
    await settle();

    expect(listener).toHaveBeenCalledTimes(1);
    query.close();
  });

  it('stops delivering after close and after unsubscribe', async () => {
    const opened = await openDb();
    db = opened.db;
    const query = db.live({
      sql: 'SELECT system_id FROM c_work_task',
      reads: [{ table: 'c_work_task' }],
      key: 'system_id',
    });
    const listener = vi.fn();
    const stop = query.subscribe(listener);
    await settle();
    stop();

    await opened.put('A', 3188, 1);
    await settle();
    expect(listener).toHaveBeenCalledTimes(1);

    query.close();
    await opened.put('B', 3188, 1);
    await settle();
    expect(listener).toHaveBeenCalledTimes(1);
  });

  it('exposes the latest rows through snapshot()', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1);
    const query = db.live<{ system_id: string }>({
      sql: 'SELECT system_id FROM c_work_task',
      reads: [{ table: 'c_work_task' }],
      key: 'system_id',
    });
    expect(query.snapshot()).toEqual([]);
    await query.refresh();
    expect(query.snapshot()).toEqual([{ system_id: 'A' }]);
    query.close();
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/live/live-query.test.ts`
Expected: FAIL — `db.live is not a function`.

- [ ] **Step 3: Write `src/live/live-query.ts`**

```ts
import type { InvalidationEvent } from '../db/invalidation-bus';
import { scopeMatches } from '../schema/scopes';
import type { Row, ScopeValues, SqlValue } from '../types';
import { diffRows } from './diff-rows';

/** One table a live query reads, and the scope of the rows it cares about. A dependency without a scope means the whole table. */
export interface ReadDependency {
  table: string;
  scope?: ScopeValues;
}

/** Everything a live query needs: the SQL to run, what it reads, and the column that identifies a row. */
export interface LiveQuerySpec {
  sql: string;
  params?: SqlValue[];
  reads: ReadDependency[];
  /** The column that identifies a row across emissions, almost always `system_id`. */
  key: string;
  /** Floor between emissions in milliseconds, for pathological writers. Coalescing per transaction usually makes this unnecessary. */
  minInterval?: number;
  /** The table whose overlay and draft holds apply to these rows. Defaults to the first read's table. */
  overlayTable?: string;
}

/** Applies the pending outbox overlay and the draft holds to rows before they are emitted. Installed by the sync runtime. */
export type RowTransform = (table: string, rows: Row[]) => Row[];

/**
 * A query that stays current. It re-runs only when a committed transaction wrote
 * a row of one of its `reads` tables inside its scope, passes the result through
 * the overlay and draft holds, and emits only when the result actually differs
 * from the last one — with unchanged rows keeping their object identity. A live
 * query is created by `db.live(...)` and must be closed when the view goes away.
 */
export class LiveQuery<T extends Record<string, unknown> = Row> {
  private rows: T[] = [];
  private listeners = new Set<(rows: T[]) => void>();
  private closed = false;
  private running = false;
  private rerunRequested = false;
  private lastEmit = 0;
  private trailing: ReturnType<typeof setTimeout> | undefined;

  constructor(
    readonly spec: LiveQuerySpec,
    private readonly runQuery: (sql: string, params: SqlValue[]) => Promise<Row[]>,
    private readonly getTransform: () => RowTransform | undefined,
    private readonly onClose: (query: LiveQuery<never>) => void,
  ) {}

  subscribe(listener: (rows: T[]) => void): () => void {
    this.listeners.add(listener);
    if (this.rows.length > 0) listener(this.rows);
    return () => {
      this.listeners.delete(listener);
    };
  }

  snapshot(): T[] {
    return this.rows;
  }

  /** Re-runs the query now and emits if the result changed. Called by the registry on a matching invalidation, and by the app for a manual refresh. */
  async refresh(): Promise<void> {
    if (this.closed) return;
    if (this.running) {
      this.rerunRequested = true;
      return;
    }
    this.running = true;
    try {
      const raw = await this.runQuery(this.spec.sql, this.spec.params ?? []);
      const transform = this.getTransform();
      const table = this.spec.overlayTable ?? this.spec.reads[0]?.table;
      const transformed = transform && table ? transform(table, raw) : raw;
      const { rows, changed } = diffRows(this.rows as unknown as Row[], transformed, this.spec.key);
      if (changed && !this.closed) {
        this.rows = rows as unknown as T[];
        this.emit();
      }
    } finally {
      this.running = false;
      if (this.rerunRequested) {
        this.rerunRequested = false;
        void this.refresh();
      }
    }
  }

  /** True when this event wrote a row this query reads, inside this query's scope. An event with unnamed rows always matches. */
  matches(event: InvalidationEvent): boolean {
    for (const read of this.spec.reads) {
      if (!event.tables.has(read.table)) continue;
      const invalidation = event.tables.get(read.table);
      if (invalidation === null || invalidation === undefined) return true;
      for (const scope of invalidation.values()) {
        if (scopeMatches(scope, read.scope)) return true;
      }
    }
    return false;
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    if (this.trailing) clearTimeout(this.trailing);
    this.listeners.clear();
    this.onClose(this as unknown as LiveQuery<never>);
  }

  private emit(): void {
    const minInterval = this.spec.minInterval ?? 0;
    const now = Date.now();
    if (minInterval > 0 && now - this.lastEmit < minInterval) {
      if (this.trailing) return;
      this.trailing = setTimeout(() => {
        this.trailing = undefined;
        this.lastEmit = Date.now();
        this.deliver();
      }, minInterval - (now - this.lastEmit));
      return;
    }
    this.lastEmit = now;
    this.deliver();
  }

  private deliver(): void {
    for (const listener of [...this.listeners]) {
      try {
        listener(this.rows);
      } catch (error) {
        console.error('[declarative-sqlite] live query listener failed', error);
      }
    }
  }
}
```

- [ ] **Step 4: Write `src/live/registry.ts`**

```ts
import type { InvalidationEvent } from '../db/invalidation-bus';
import type { Row, SqlValue } from '../types';
import { LiveQuery, type LiveQuerySpec, type RowTransform } from './live-query';

/**
 * Owns every open live query for one database and routes invalidation events to
 * the ones that care. One committed transaction produces one event, so a
 * 200-row pull page re-runs each affected query exactly once.
 */
export class LiveRegistry {
  private readonly queries = new Set<LiveQuery<never>>();
  private transform: RowTransform | undefined;

  constructor(
    private readonly runQuery: (sql: string, params: SqlValue[]) => Promise<Row[]>,
    subscribeToInvalidations: (listener: (event: InvalidationEvent) => void) => () => void,
  ) {
    subscribeToInvalidations((event) => this.onInvalidation(event));
  }

  create<T extends Record<string, unknown>>(spec: LiveQuerySpec): LiveQuery<T> {
    const query = new LiveQuery<T>(
      spec,
      this.runQuery,
      () => this.transform,
      (closed) => this.queries.delete(closed),
    );
    this.queries.add(query as unknown as LiveQuery<never>);
    void query.refresh();
    return query;
  }

  /** Installs the overlay + draft-hold transform. Called once by the sync runtime; passing `undefined` removes it. */
  setRowTransform(transform: RowTransform | undefined): void {
    this.transform = transform;
    for (const query of this.queries) void query.refresh();
  }

  closeAll(): void {
    for (const query of [...this.queries]) query.close();
  }

  private onInvalidation(event: InvalidationEvent): void {
    for (const query of [...this.queries]) {
      if (query.matches(event)) void query.refresh();
    }
  }
}
```

- [ ] **Step 5: Wire `live` into `src/db/database.ts`**

```ts
import { LiveRegistry } from '../live/registry';
import type { LiveQuery, LiveQuerySpec, RowTransform } from '../live/live-query';

// inside class Database:
  private readonly live_ = new LiveRegistry(
    (sql, params) => this.query<Row>(sql, params),
    (listener) => this.invalidations.subscribe(listener),
  );

  /**
   * Creates a query that stays current. Declare the tables and scopes it reads
   * so that it re-runs only for writes that can affect it, and the key column so
   * unchanged rows keep their identity. Close it when the view unmounts.
   */
  live<T extends Record<string, unknown> = Row>(spec: LiveQuerySpec): LiveQuery<T> {
    this.ensureOpen();
    return this.live_.create<T>(spec);
  }

  /** Installs the transform every live query's rows pass through before emission. The sync runtime calls this with overlay + draft holds. */
  setRowTransform(transform: RowTransform | undefined): void {
    this.live_.setRowTransform(transform);
  }
```

Close every live query in `close()`, before closing the adapter: `this.live_.closeAll();`.

- [ ] **Step 6: Run the test and watch it pass**

Run: `npm test -- src/live/live-query.test.ts`
Expected: PASS, 6 tests.

- [ ] **Step 7: Commit**

```bash
git add src/live src/db/database.ts
git commit -m "$(cat <<'MSG'
feat(live): live queries with scope-aware invalidation

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 15: One emission per transaction, emit-on-change and the transform hook

Task 14 built the machinery; this task pins the three guarantees the spec makes about it with tests that would fail if someone later "optimised" the diff away, plus the `minInterval` escape hatch.

**Files:**
- Test: `packages/core/src/live/live-emission.test.ts`
- Modify: `packages/core/src/index.ts`

**Interfaces:**
- Consumes: everything from Task 14.
- Produces: no new API — exports `LiveQuery`, `LiveRegistry` and their types from the package entry.

- [ ] **Step 1: Write the failing test**

`src/live/live-emission.test.ts`:

```ts
import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('live query emissions', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('emits once for a transaction that wrote 200 rows', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    const query = db.live({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const listener = vi.fn();
    query.subscribe(listener);
    await settle();
    listener.mockClear();

    await db.transaction(async (tx) => {
      for (let i = 0; i < 200; i++) {
        await writer.upsert(tx, 'c_work_task', {
          system_id: `row-${i}`, wo_no: 3188, c_qty_installed: i, sync_seq: i + 1, system_removed: 0,
        });
      }
    });
    await settle();

    expect(listener).toHaveBeenCalledTimes(1);
    expect(listener.mock.calls[0]?.[0]).toHaveLength(200);
    query.close();
  });

  it('does not emit when a write leaves the result identical', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, sync_seq: 1, system_removed: 0 });
    });

    const query = db.live({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ?',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const listener = vi.fn();
    query.subscribe(listener);
    await settle();
    listener.mockClear();

    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, sync_seq: 2, system_removed: 0 });
    });
    await settle();

    expect(listener).not.toHaveBeenCalled();
    query.close();
  });

  it('keeps the identity of rows that did not change between emissions', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      for (const id of ['A', 'B']) {
        await writer.upsert(tx, 'c_work_task', { system_id: id, wo_no: 3188, c_qty_installed: 1, sync_seq: 1, system_removed: 0 });
      }
    });

    const query = db.live<{ system_id: string; c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const emissions: Array<Array<{ system_id: string }>> = [];
    query.subscribe((rows) => emissions.push(rows));
    await settle();

    await db.transaction(async (tx) => {
      await writer.setColumns(tx, 'c_work_task', 'B', { c_qty_installed: 9 });
    });
    await settle();

    expect(emissions).toHaveLength(2);
    expect(emissions[1]?.[0]).toBe(emissions[0]?.[0]); // A untouched, same object
    expect(emissions[1]?.[1]).not.toBe(emissions[0]?.[1]);
    query.close();
  });

  it('applies the installed row transform before emitting', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, sync_seq: 1, system_removed: 0 });
    });

    db.setRowTransform((table, rows) => (table === 'c_work_task' ? rows.map((row) => ({ ...row, c_qty_installed: 99 })) : rows));

    const query = db.live<{ c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task',
      reads: [{ table: 'c_work_task' }],
      key: 'system_id',
    });
    const emissions: Array<Array<{ c_qty_installed: number }>> = [];
    query.subscribe((rows) => emissions.push(rows));
    await settle();

    expect(emissions[0]?.[0]?.c_qty_installed).toBe(99);
    query.close();
  });

  it('respects minInterval by delaying the second emission', async () => {
    vi.useFakeTimers();
    try {
      db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
      const writer = serverWriter(db, createServerWriteCapability());
      const query = db.live({
        sql: 'SELECT system_id, c_qty_installed FROM c_work_task',
        reads: [{ table: 'c_work_task' }],
        key: 'system_id',
        minInterval: 200,
      });
      const listener = vi.fn();
      query.subscribe(listener);
      await vi.advanceTimersByTimeAsync(1);

      await db.transaction(async (tx) => {
        await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 1, c_qty_installed: 1, sync_seq: 1, system_removed: 0 });
      });
      await vi.advanceTimersByTimeAsync(1);
      const afterFirst = listener.mock.calls.length;

      await db.transaction(async (tx) => {
        await writer.setColumns(tx, 'c_work_task', 'A', { c_qty_installed: 2 });
      });
      await vi.advanceTimersByTimeAsync(1);
      expect(listener.mock.calls.length).toBe(afterFirst);

      await vi.advanceTimersByTimeAsync(300);
      expect(listener.mock.calls.length).toBe(afterFirst + 1);
      query.close();
    } finally {
      vi.useRealTimers();
    }
  });
});
```

- [ ] **Step 2: Run it**

Run: `npm test -- src/live/live-emission.test.ts`
Expected: the first four pass on Task 14's implementation; the `minInterval` test fails if the trailing-emission path was not implemented. Fix `LiveQuery.emit` until all five pass — do not weaken the test.

- [ ] **Step 3: Export the live layer**

Append to `src/index.ts`:

```ts
export { LiveQuery } from './live/live-query';
export { LiveRegistry } from './live/registry';
export { diffRows } from './live/diff-rows';
export type { LiveQuerySpec, ReadDependency, RowTransform } from './live/live-query';
```

- [ ] **Step 4: Run the whole suite**

Run: `npm test && npm run typecheck`
Expected: everything green.

- [ ] **Step 5: Commit**

```bash
git add src
git commit -m "$(cat <<'MSG'
test(live): pin one emission per transaction, emit-on-change and identity

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---
### Task 16: Wire types, name mapping and the limits the server enforces

The library talks to `apply-work-api`, whose `/sync/rows` and `/sync/push` bodies are Part A §A3 of the consumer spec; those in turn mirror `GetRowsV2`/`PushBatch` in `wire-format.md`. Column names are uppercase IFS names on the wire and lowercase locally, and the limits the database will enforce (36-character batch id, 4000-character scalar, 500 changes) are checked here so a doomed request never leaves the device.

**Files:**
- Create: `packages/core/src/sync/wire.ts`
- Test: `packages/core/src/sync/wire.test.ts`

**Interfaces:**
- Consumes: `Row`, `SqlValue`, `TableDef`.
- Produces:
  - `interface RowDoc { id: string; seq: number; removed: boolean; data: Record<string, unknown> }`
  - `interface RowsPage { table: string; rows: RowDoc[]; next: number; hasMore: boolean }`
  - `interface PullRequest { table: string; scope?: string; after: number; limit?: number }`
  - `interface PushChange { table: string; id: string; column: string; old: unknown; new: unknown; changedAt: string }`
  - `interface PushBatch { batchId: string; deviceId: string; changes: PushChange[] }`
  - `type PushResultCode = 'applied' | 'noop' | 'rejected'`
  - `interface PushChangeResult { index: number; result: PushResultCode; error?: string | null }`
  - `interface PushResult { batchId: string; results: PushChangeResult[]; rows: RowDoc[] }`
  - `const MAX_VALUE_CHARS = 4000`, `MAX_BATCH_CHANGES = 500`, `MAX_BATCH_ID_CHARS = 36`, `PULL_WINDOW = 1000`, `DEFAULT_PAGE_LIMIT = 500`
  - `class ValueTooLongError extends Error`
  - `function encodeScalar(value: unknown): string`
  - `function decodeScalar(text: string | null): unknown`
  - `function assertScalarFits(table: string, column: string, encoded: string): void`
  - `function newBatchId(): string`
  - `function toWireTable(table: string): string`, `function toWireColumn(column: string): string`
  - `function fromWireData(table: TableDef, data: Record<string, unknown>): Row`

- [ ] **Step 1: Write the failing test**

`src/sync/wire.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { SchemaBuilder } from '../schema/schema-builder';
import {
  assertScalarFits, decodeScalar, encodeScalar, fromWireData, MAX_BATCH_ID_CHARS,
  newBatchId, toWireColumn, toWireTable, ValueTooLongError,
} from './wire';

const taskTable = (() => {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
    t.date('planned_start');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build().tables[0]!;
})();

describe('wire helpers', () => {
  it('encodes scalars as JSON and decodes them back', () => {
    expect(encodeScalar(10)).toBe('10');
    expect(encodeScalar('WORKSTARTED')).toBe('"WORKSTARTED"');
    expect(encodeScalar(null)).toBe('null');
    expect(encodeScalar(undefined)).toBe('null');
    expect(encodeScalar(true)).toBe('true');
    expect(decodeScalar('10')).toBe(10);
    expect(decodeScalar('"WORKSTARTED"')).toBe('WORKSTARTED');
    expect(decodeScalar(null)).toBeNull();
  });

  it('refuses a scalar the server column cannot hold', () => {
    const long = encodeScalar('x'.repeat(4100));
    expect(() => assertScalarFits('c_work_task', 'internal_remark', long)).toThrow(ValueTooLongError);
    expect(() => assertScalarFits('c_work_task', 'internal_remark', encodeScalar('ok'))).not.toThrow();
  });

  it('mints a batch id that fits the server column', () => {
    const id = newBatchId();
    expect(id.length).toBeLessThanOrEqual(MAX_BATCH_ID_CHARS);
    expect(newBatchId()).not.toBe(id);
  });

  it('uppercases table and column names for the wire', () => {
    expect(toWireTable('c_work_task')).toBe('C_WORK_TASK');
    expect(toWireColumn('c_qty_installed')).toBe('C_QTY_INSTALLED');
  });

  it('lowercases wire data and drops columns the schema does not declare', () => {
    const row = fromWireData(taskTable, { WO_NO: 3188, C_QTY_INSTALLED: 10, ROWSTATE: 'WORKSTARTED', UNKNOWN_COL: 'x' });
    expect(row).toEqual({ wo_no: 3188, c_qty_installed: 10, rowstate: 'WORKSTARTED' });
  });

  it('coerces booleans and keeps ISO date strings as text', () => {
    const row = fromWireData(taskTable, { PLANNED_START: '2026-09-17T06:00:00Z', ROWSTATE: null });
    expect(row).toEqual({ planned_start: '2026-09-17T06:00:00Z', rowstate: null });
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/sync/wire.test.ts`
Expected: FAIL — `Failed to resolve import "./wire"`.

- [ ] **Step 3: Write `src/sync/wire.ts`**

```ts
import { toSqlValue } from '../db/tables';
import type { TableDef } from '../schema/types';
import type { Row } from '../types';

/** One row as the server sends it: system values beside a `data` object of business columns. */
export interface RowDoc {
  id: string;
  seq: number;
  removed: boolean;
  data: Record<string, unknown>;
}

/** One page of `GET /sync/rows`. `next` is the highest `seq` in the page (or the requested cursor when the page is empty). */
export interface RowsPage {
  table: string;
  rows: RowDoc[];
  next: number;
  hasMore: boolean;
}

/** What the transport needs to fetch a page: the wire table name, the formatted scope, the cursor and a page size. */
export interface PullRequest {
  table: string;
  scope?: string;
  after: number;
  limit?: number;
}

/** One column change as `POST /sync/push` carries it. `old` and `new` are JSON scalars, not strings; `changedAt` is informational. */
export interface PushChange {
  table: string;
  id: string;
  column: string;
  old: unknown;
  new: unknown;
  changedAt: string;
}

/** One push. The server stores the answer under `batchId`, so re-sending the same id returns the stored answer and applies nothing. */
export interface PushBatch {
  batchId: string;
  deviceId: string;
  changes: PushChange[];
}

export type PushResultCode = 'applied' | 'noop' | 'rejected';

/** The verdict on one change, by its zero-based position in the batch. */
export interface PushChangeResult {
  index: number;
  result: PushResultCode;
  error?: string | null;
}

/** The push answer: one result per change plus the current server state of every row the batch touched. The rows are a receipt, not a read — see `PullApplier`'s seq guard. */
export interface PushResult {
  batchId: string;
  results: PushChangeResult[];
  rows: RowDoc[];
}

/** `C_WORK_SYNC_LOG.OLD_VALUE`/`NEW_VALUE` are VARCHAR2(4000); a longer JSON scalar fails the call before the implementation runs. */
export const MAX_VALUE_CHARS = 4000;
/** The push cap. A change group larger than this cannot be pushed atomically and is a programming error. */
export const MAX_BATCH_CHANGES = 500;
/** `C_WORK_SYNC_BATCH.BATCH_ID` is VARCHAR2(36); a longer id fails the whole call and stores nothing, so the call is not even idempotent. */
export const MAX_BATCH_ID_CHARS = 36;
/** How far a tick-driven pull rewinds behind its cursor, because sequence order is not commit order. */
export const PULL_WINDOW = 1000;
/** The server's default page size; its maximum is 1000. */
export const DEFAULT_PAGE_LIMIT = 500;

/** Thrown before a push when a value is wider than the server column can hold. Terminal for that value; a shorter one may be recorded as a new change. */
export class ValueTooLongError extends Error {
  constructor(
    readonly table: string,
    readonly column: string,
    readonly length: number,
  ) {
    super(`${table}.${column}: value is ${length} characters, the server accepts at most ${MAX_VALUE_CHARS}`);
    this.name = 'ValueTooLongError';
  }
}

/** JSON-encodes a scalar for the outbox and the log. `undefined` becomes `null`, which is how a column is cleared. */
export function encodeScalar(value: unknown): string {
  return JSON.stringify(value ?? null);
}

/** Reverses `encodeScalar`. A stored value that is not valid JSON comes back as the raw string, so one corrupt row cannot break the queue. */
export function decodeScalar(text: string | null): unknown {
  if (text === null || text === undefined) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

export function assertScalarFits(table: string, column: string, encoded: string): void {
  if (encoded.length > MAX_VALUE_CHARS) throw new ValueTooLongError(table, column, encoded.length);
}

/** A batch id that fits `VARCHAR2(36)`: a v4 UUID is exactly 36 characters. */
export function newBatchId(): string {
  return crypto.randomUUID();
}

export function toWireTable(table: string): string {
  return table.toUpperCase();
}

export function toWireColumn(column: string): string {
  return column.toUpperCase();
}

/**
 * Turns a server `data` object into a local row: uppercase keys become
 * lowercase, values are coerced to something SQLite can bind, and columns the
 * schema does not declare are dropped — the server may know columns this client
 * does not, and that must never fail a pull.
 */
export function fromWireData(table: TableDef, data: Record<string, unknown>): Row {
  const declared = new Set(table.columns.map((c) => c.name));
  const row: Row = {};
  for (const [key, value] of Object.entries(data)) {
    const column = key.toLowerCase();
    if (!declared.has(column)) continue;
    row[column] = toSqlValue(value);
  }
  return row;
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/sync/wire.test.ts`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
feat(sync): wire types, name mapping and the server's hard limits

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 17: `SyncTransport` and the scripted `FakeTransport`

The library never speaks HTTP. Everything above it is tested against a fake server that behaves the way `wire-format.md` says the real one does: last arrival wins per column, idempotent on batch id, answer rows are the state inside the batch's own transaction.

**Files:**
- Create: `packages/core/src/sync/transport.ts`
- Create: `packages/core/src/testing/fake-transport.ts`
- Test: `packages/core/src/testing/fake-transport.test.ts`

**Interfaces:**
- Consumes: the wire types from Task 16.
- Produces:
  - `interface SyncTransport { pullRows(req: PullRequest): Promise<RowsPage>; push(batch: PushBatch): Promise<PushResult> }`
  - `class FakeTransport implements SyncTransport { constructor(options?: { pageSize?: number }); seed(table: string, rows: Array<{ id: string; data: Record<string, unknown>; removed?: boolean }>): void; serverEdit(table: string, id: string, data: Record<string, unknown>): void; tombstone(table: string, id: string): void; reject(table: string, column: string, error: string): void; failNextPush(error?: Error): void; readonly pushes: PushBatch[]; readonly pulls: PullRequest[] }`

- [ ] **Step 1: Write the failing test**

`src/testing/fake-transport.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { FakeTransport } from './fake-transport';

describe('FakeTransport', () => {
  it('pages rows by cursor in seq order', async () => {
    const server = new FakeTransport({ pageSize: 2 });
    server.seed('C_WORK_TASK', [
      { id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } },
      { id: 'B', data: { WO_NO: 3188, C_QTY_INSTALLED: 2 } },
      { id: 'C', data: { WO_NO: 3188, C_QTY_INSTALLED: 3 } },
    ]);

    const first = await server.pullRows({ table: 'C_WORK_TASK', scope: 'WO_NO:3188', after: 0 });
    expect(first.rows.map((r) => r.id)).toEqual(['A', 'B']);
    expect(first.hasMore).toBe(true);

    const second = await server.pullRows({ table: 'C_WORK_TASK', scope: 'WO_NO:3188', after: first.next });
    expect(second.rows.map((r) => r.id)).toEqual(['C']);
    expect(second.hasMore).toBe(false);
  });

  it('filters by scope and reports tombstones with empty data', async () => {
    const server = new FakeTransport();
    server.seed('C_WORK_TASK', [
      { id: 'A', data: { WO_NO: 3188 } },
      { id: 'Z', data: { WO_NO: 4000 } },
    ]);
    server.tombstone('C_WORK_TASK', 'A');

    const page = await server.pullRows({ table: 'C_WORK_TASK', scope: 'WO_NO:3188', after: 0 });
    expect(page.rows).toHaveLength(1);
    expect(page.rows[0]).toMatchObject({ id: 'A', removed: true, data: {} });
  });

  it('applies a push in order and answers with the row as the batch left it', async () => {
    const server = new FakeTransport();
    server.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } }]);

    const answer = await server.push({
      batchId: 'b1',
      deviceId: 'ipad',
      changes: [
        { table: 'C_WORK_TASK', id: 'A', column: 'C_QTY_INSTALLED', old: 1, new: 10, changedAt: '2026-09-17T09:00:00Z' },
        { table: 'C_WORK_TASK', id: 'A', column: 'ROWSTATE', old: 'RELEASED', new: 'WORKSTARTED', changedAt: '2026-09-17T09:00:01Z' },
      ],
    });

    expect(answer.results).toEqual([
      { index: 0, result: 'applied', error: null },
      { index: 1, result: 'applied', error: null },
    ]);
    expect(answer.rows[0]?.data).toMatchObject({ C_QTY_INSTALLED: 10, ROWSTATE: 'WORKSTARTED' });
  });

  it('is idempotent on batch id', async () => {
    const server = new FakeTransport();
    server.seed('C_WORK_TASK', [{ id: 'A', data: { C_QTY_INSTALLED: 1 } }]);
    const batch = {
      batchId: 'b1', deviceId: 'ipad',
      changes: [{ table: 'C_WORK_TASK', id: 'A', column: 'C_QTY_INSTALLED', old: 1, new: 2, changedAt: 'x' }],
    };
    const first = await server.push(batch);
    server.serverEdit('C_WORK_TASK', 'A', { C_QTY_INSTALLED: 99 });
    const replay = await server.push(batch);
    expect(replay).toEqual(first);
    expect(server.pushes).toHaveLength(2);
  });

  it('answers CNOROW for an unknown row and rejects a configured column', async () => {
    const server = new FakeTransport();
    server.seed('C_WORK_TASK', [{ id: 'A', data: { C_QTY_INSTALLED: 1 } }]);
    server.reject('C_WORK_TASK', 'ROWSTATE', 'WTCERR2: Qty Installed can only be modified when the Work Task status is Work Started.');

    const answer = await server.push({
      batchId: 'b2', deviceId: 'ipad',
      changes: [
        { table: 'C_WORK_TASK', id: 'GONE', column: 'C_QTY_INSTALLED', old: 1, new: 2, changedAt: 'x' },
        { table: 'C_WORK_TASK', id: 'A', column: 'ROWSTATE', old: null, new: 'WORKSTARTED', changedAt: 'x' },
      ],
    });

    expect(answer.results[0]).toMatchObject({ result: 'rejected' });
    expect(answer.results[0]?.error).toContain('CNOROW');
    expect(answer.results[1]).toMatchObject({ result: 'rejected' });
  });

  it('answers noop when the value is already what the server holds', async () => {
    const server = new FakeTransport();
    server.seed('C_WORK_TASK', [{ id: 'A', data: { C_QTY_INSTALLED: 5 } }]);
    const answer = await server.push({
      batchId: 'b3', deviceId: 'ipad',
      changes: [{ table: 'C_WORK_TASK', id: 'A', column: 'C_QTY_INSTALLED', old: 5, new: 5, changedAt: 'x' }],
    });
    expect(answer.results[0]?.result).toBe('noop');
  });

  it('fails the next push when told to', async () => {
    const server = new FakeTransport();
    server.failNextPush();
    await expect(server.push({ batchId: 'b4', deviceId: 'ipad', changes: [] })).rejects.toThrow();
    await expect(server.push({ batchId: 'b4', deviceId: 'ipad', changes: [] })).resolves.toBeDefined();
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/testing/fake-transport.test.ts`
Expected: FAIL — `Failed to resolve import "./fake-transport"`.

- [ ] **Step 3: Write `src/sync/transport.ts`**

```ts
import type { PullRequest, PushBatch, PushResult, RowsPage } from './wire';

/**
 * The only thing the library needs from the network, supplied by the
 * application: fetch a page of rows after a cursor, and push a batch of column
 * changes. Implementations mirror `apply-work-api`'s `/sync/rows` and
 * `/sync/push`; the library never knows about HTTP, auth or retries at this
 * level — a rejected promise is a network error and triggers the push service's
 * backoff.
 */
export interface SyncTransport {
  pullRows(req: PullRequest): Promise<RowsPage>;
  push(batch: PushBatch): Promise<PushResult>;
}
```

- [ ] **Step 4: Write `src/testing/fake-transport.ts`**

```ts
import type { SyncTransport } from '../sync/transport';
import { DEFAULT_PAGE_LIMIT, type PullRequest, type PushBatch, type PushChangeResult, type PushResult, type RowDoc, type RowsPage } from '../sync/wire';

interface ServerRow {
  id: string;
  seq: number;
  removed: boolean;
  data: Record<string, unknown>;
}

/**
 * A scripted server for tests. It behaves the way `wire-format.md` says the real
 * one does: rows carry a monotonic `seq`, a push applies its changes in order
 * with last arrival winning per column, the answer rows are the state as that
 * batch left them, and a replayed `batchId` returns the stored answer without
 * applying anything. `serverEdit` and `tombstone` simulate the other device.
 */
export class FakeTransport implements SyncTransport {
  private readonly tables = new Map<string, Map<string, ServerRow>>();
  private readonly answers = new Map<string, PushResult>();
  private readonly rejections = new Map<string, string>();
  private seq = 0;
  private failPush: Error | undefined;

  readonly pushes: PushBatch[] = [];
  readonly pulls: PullRequest[] = [];

  constructor(private readonly options: { pageSize?: number } = {}) {}

  seed(table: string, rows: Array<{ id: string; data: Record<string, unknown>; removed?: boolean }>): void {
    for (const row of rows) {
      this.rowsOf(table).set(row.id, { id: row.id, seq: ++this.seq, removed: row.removed ?? false, data: { ...row.data } });
    }
  }

  /** Another device changed the row on the server: bumps its seq the way a real `Update___` would. */
  serverEdit(table: string, id: string, data: Record<string, unknown>): void {
    const row = this.rowsOf(table).get(id);
    if (!row) throw new Error(`FakeTransport: no row ${table}/${id}`);
    row.data = { ...row.data, ...data };
    row.seq = ++this.seq;
  }

  tombstone(table: string, id: string): void {
    const row = this.rowsOf(table).get(id);
    if (!row) throw new Error(`FakeTransport: no row ${table}/${id}`);
    row.removed = true;
    row.seq = ++this.seq;
  }

  /** Makes every push of this column come back `rejected` with the given error, like an IFS validation failure. */
  reject(table: string, column: string, error: string): void {
    this.rejections.set(`${table}.${column}`, error);
  }

  failNextPush(error: Error = new Error('network')): void {
    this.failPush = error;
  }

  async pullRows(req: PullRequest): Promise<RowsPage> {
    this.pulls.push(req);
    const limit = req.limit ?? this.options.pageSize ?? DEFAULT_PAGE_LIMIT;
    const scope = req.scope ? parseWireScope(req.scope) : undefined;

    const all = [...this.rowsOf(req.table).values()]
      .filter((row) => row.seq > req.after)
      .filter((row) => matchesScope(row, scope))
      .sort((a, b) => a.seq - b.seq);

    const page = all.slice(0, limit);
    return {
      table: req.table,
      rows: page.map(toRowDoc),
      next: page.length > 0 ? (page[page.length - 1]?.seq ?? req.after) : req.after,
      hasMore: all.length > page.length,
    };
  }

  async push(batch: PushBatch): Promise<PushResult> {
    this.pushes.push(batch);
    if (this.failPush) {
      const error = this.failPush;
      this.failPush = undefined;
      throw error;
    }
    const stored = this.answers.get(batch.batchId);
    if (stored) return stored;

    const results: PushChangeResult[] = [];
    const touched = new Set<string>();

    for (const [index, change] of batch.changes.entries()) {
      const row = this.rowsOf(change.table).get(change.id);
      if (!row || row.removed) {
        results.push({ index, result: 'rejected', error: `CNOROW: row ${change.id} does not exist on the server` });
        continue;
      }
      const rejection = this.rejections.get(`${change.table}.${change.column}`);
      if (rejection) {
        results.push({ index, result: 'rejected', error: rejection });
        continue;
      }
      touched.add(`${change.table}|${change.id}`);
      if (Object.is(row.data[change.column] ?? null, change.new ?? null)) {
        results.push({ index, result: 'noop', error: null });
        continue;
      }
      row.data[change.column] = change.new;
      row.seq = ++this.seq;
      results.push({ index, result: 'applied', error: null });
    }

    const rows = [...touched].map((key) => {
      const [table, id] = key.split('|');
      return toRowDoc(this.rowsOf(table ?? '').get(id ?? '') as ServerRow);
    });

    const answer: PushResult = { batchId: batch.batchId, results, rows };
    this.answers.set(batch.batchId, answer);
    return answer;
  }

  private rowsOf(table: string): Map<string, ServerRow> {
    let rows = this.tables.get(table);
    if (!rows) {
      rows = new Map();
      this.tables.set(table, rows);
    }
    return rows;
  }
}

function toRowDoc(row: ServerRow): RowDoc {
  return { id: row.id, seq: row.seq, removed: row.removed, data: row.removed ? {} : { ...row.data } };
}

function parseWireScope(scope: string): Record<string, string> {
  const parsed: Record<string, string> = {};
  for (const pair of scope.split(',')) {
    const at = pair.indexOf(':');
    parsed[pair.slice(0, at)] = pair.slice(at + 1);
  }
  return parsed;
}

function matchesScope(row: ServerRow, scope?: Record<string, string>): boolean {
  if (!scope) return true;
  return Object.entries(scope).every(([column, value]) => String(row.data[column] ?? '') === value);
}
```

- [ ] **Step 5: Run the test and watch it pass**

Run: `npm test -- src/testing/fake-transport.test.ts`
Expected: PASS, 7 tests.

- [ ] **Step 6: Export the transport and the fake**

Append to `src/index.ts`:

```ts
export type { SyncTransport } from './sync/transport';
export type { RowDoc, RowsPage, PullRequest, PushBatch, PushChange, PushChangeResult, PushResult, PushResultCode } from './sync/wire';
export { encodeScalar, decodeScalar, newBatchId, toWireTable, toWireColumn, fromWireData, ValueTooLongError, MAX_VALUE_CHARS, MAX_BATCH_CHANGES, MAX_BATCH_ID_CHARS, PULL_WINDOW, DEFAULT_PAGE_LIMIT } from './sync/wire';
export { FakeTransport } from './testing/fake-transport';
```

- [ ] **Step 7: Commit**

```bash
git add src/sync src/testing src/index.ts
git commit -m "$(cat <<'MSG'
feat(sync): SyncTransport interface and a scripted FakeTransport

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 18: The outbox — recording a change group

`record` is the only way an application changes a synced row. It writes the local columns *and* the outbox rows in one transaction, so a crash can never leave a value on screen that nothing will ever send. Several columns of one row are one change group with one `group_id`, and the push never splits a group — that is what makes IFS validate the row's final state.

**Files:**
- Create: `packages/core/src/sync/outbox.ts`
- Test: `packages/core/src/sync/outbox-record.test.ts`

**Interfaces:**
- Consumes: `Database`, `ServerWriter`, `encodeScalar`, `assertScalarFits`, `MAX_BATCH_CHANGES`, `OUTBOX_TABLE`.
- Produces:
  - `type OutboxStatus = 'pending' | 'sending' | 'applied' | 'noop' | 'rejected'`
  - `interface OutboxEntry { id: string; tableName: string; systemId: string; columnName: string; oldValue: unknown; newValue: unknown; changedAt: string; status: OutboxStatus; groupId: string; batchId?: string; errorText?: string; appliedAt?: string }`
  - `interface RecordRequest { table: string; systemId: string; changes: Record<string, unknown> }`
  - `class Outbox { constructor(db: Database, writer: ServerWriter, options?: { clock?: () => Date }); record(request: RecordRequest): Promise<string>; subscribe(listener: () => void): () => void }`
  - `class OutboxError extends Error`

- [ ] **Step 1: Write the failing test**

`src/sync/outbox-record.test.ts`:

```ts
import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox, OutboxError } from './outbox';
import { ValueTooLongError } from './wire';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
    t.text('internal_remark');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  s.table('local_prefs', (t) => t.text('value'));
  return s.build();
}

async function setup() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer, { clock: () => new Date('2026-09-17T09:12:31Z') });
  await db.transaction(async (tx) => {
    await writer.upsert(tx, 'c_work_task', {
      system_id: 'A', wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', internal_remark: null, sync_seq: 5, system_removed: 0,
    });
  });
  return { db, outbox };
}

describe('Outbox.record', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('writes the local columns and the outbox rows in one transaction', async () => {
    const s = await setup();
    db = s.db;
    const groupId = await s.outbox.record({
      table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' },
    });

    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 10, rowstate: 'WORKSTARTED',
    });
    const entries = await db.query<{ column_name: string; old_value: string; new_value: string; status: string; group_id: string }>(
      'SELECT column_name, old_value, new_value, status, group_id FROM outbox ORDER BY column_name',
    );
    expect(entries).toEqual([
      { column_name: 'c_qty_installed', old_value: '1', new_value: '10', status: 'pending', group_id: groupId },
      { column_name: 'rowstate', old_value: '"RELEASED"', new_value: '"WORKSTARTED"', status: 'pending', group_id: groupId },
    ]);
  });

  it('records the old value it saw, including null', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { internal_remark: 'sjekket' } });
    expect(await db.queryOne('SELECT old_value FROM outbox')).toEqual({ old_value: 'null' });
  });

  it('gives every recorded change the same group id and a fresh one per call', async () => {
    const s = await setup();
    db = s.db;
    const first = await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 2 } });
    const second = await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 3 } });
    expect(first).not.toBe(second);
    expect(await db.query('SELECT id FROM outbox')).toHaveLength(2);
  });

  it('emits one invalidation carrying the row and its scope', async () => {
    const s = await setup();
    db = s.db;
    const events: Array<Map<string, unknown>> = [];
    db.invalidations.subscribe((event) => events.push(new Map(event.tables)));
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    expect(events).toHaveLength(1);
    expect(events[0]?.get('c_work_task')).toBeDefined();
    expect(events[0]?.get('outbox')).toBeDefined();
  });

  it('notifies subscribers that the outbox changed', async () => {
    const s = await setup();
    db = s.db;
    const listener = vi.fn();
    s.outbox.subscribe(listener);
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    expect(listener).toHaveBeenCalled();
  });

  it('refuses a table that is not synced', async () => {
    const s = await setup();
    db = s.db;
    await expect(s.outbox.record({ table: 'local_prefs', systemId: 'x', changes: { value: '1' } })).rejects.toThrow(OutboxError);
  });

  it('refuses a row that does not exist locally', async () => {
    const s = await setup();
    db = s.db;
    await expect(s.outbox.record({ table: 'c_work_task', systemId: 'GONE', changes: { c_qty_installed: 1 } })).rejects.toThrow(/GONE/);
  });

  it('refuses a column the schema does not declare and an empty change set', async () => {
    const s = await setup();
    db = s.db;
    await expect(s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { nope: 1 } })).rejects.toThrow(/nope/);
    await expect(s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: {} })).rejects.toThrow(/no changes/i);
  });

  it('refuses a value wider than the server accepts, leaving nothing behind', async () => {
    const s = await setup();
    db = s.db;
    await expect(
      s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { internal_remark: 'x'.repeat(4100) } }),
    ).rejects.toThrow(ValueTooLongError);
    expect(await db.query('SELECT id FROM outbox')).toEqual([]);
  });

  it('refuses a change group larger than one batch can carry', async () => {
    const s = await setup();
    db = s.db;
    const changes: Record<string, unknown> = {};
    for (let i = 0; i < 501; i++) changes[`col_${i}`] = i;
    await expect(s.outbox.record({ table: 'c_work_task', systemId: 'A', changes })).rejects.toThrow(/group/i);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/sync/outbox-record.test.ts`
Expected: FAIL — `Failed to resolve import "./outbox"`.

- [ ] **Step 3: Write `src/sync/outbox.ts` (the recording half; Task 19 adds the status half)**

```ts
import type { Database } from '../db/database';
import type { ServerWriter } from '../db/server-truth';
import { quoteIdentifier } from '../db/sql';
import { OUTBOX_TABLE } from '../schema/library-tables';
import type { Row } from '../types';
import { assertScalarFits, encodeScalar, MAX_BATCH_CHANGES } from './wire';

/** Where a recorded change stands. `applied`, `noop` and `rejected` are terminal; `rejected` stays visible until the user retries or discards it. */
export type OutboxStatus = 'pending' | 'sending' | 'applied' | 'noop' | 'rejected';

/** One recorded column change. `oldValue` is what the device saw and is informational; the server logs it and decides by arrival order. */
export interface OutboxEntry {
  id: string;
  tableName: string;
  systemId: string;
  columnName: string;
  oldValue: unknown;
  newValue: unknown;
  changedAt: string;
  status: OutboxStatus;
  groupId: string;
  batchId?: string;
  errorText?: string;
  appliedAt?: string;
}

/** One change group: every column of one row that must reach the server in the same batch. */
export interface RecordRequest {
  table: string;
  systemId: string;
  changes: Record<string, unknown>;
}

/** Thrown for a change the library refuses to record: a non-synced table, a missing row, an unknown column, an empty or oversized group. */
export class OutboxError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OutboxError';
  }
}

/**
 * The queue of recorded, unconfirmed changes — the second of the three owners of
 * state, between server truth in the tables and the draft being typed. Recording
 * writes the local row and the queue rows in one transaction, so what the user
 * sees and what will be sent can never disagree. Reads of a synced table are
 * overlaid with the pending values (see `Overlay`), so a column stays at the
 * user's value until the server answers.
 */
export class Outbox {
  private readonly listeners = new Set<() => void>();
  /** Bumped on every write so the overlay knows its cache is stale. */
  version = 0;

  constructor(
    private readonly db: Database,
    private readonly writer: ServerWriter,
    private readonly options: { clock?: () => Date } = {},
  ) {}

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  async record(request: RecordRequest): Promise<string> {
    const table = this.db.tableDef(request.table);
    if (!table.synced) throw new OutboxError(`Table ${request.table} is not synced; write it through db.tables instead`);

    const columns = Object.keys(request.changes);
    if (columns.length === 0) throw new OutboxError(`${request.table}/${request.systemId}: no changes to record`);
    if (columns.length > MAX_BATCH_CHANGES) {
      throw new OutboxError(
        `${request.table}/${request.systemId}: a change group of ${columns.length} columns cannot be pushed atomically (the cap is ${MAX_BATCH_CHANGES})`,
      );
    }
    for (const column of columns) {
      if (!table.columns.some((c) => c.name === column)) {
        throw new OutboxError(`${request.table}: column "${column}" is not in the schema`);
      }
    }

    const keyColumn = table.synced.key;
    const current = await this.db.queryOne<Row>(
      `SELECT * FROM ${quoteIdentifier(table.name)} WHERE ${quoteIdentifier(keyColumn)} = ?`,
      [request.systemId],
    );
    if (!current) throw new OutboxError(`${request.table}/${request.systemId}: row does not exist locally`);

    const changedAt = (this.options.clock?.() ?? new Date()).toISOString();
    const groupId = crypto.randomUUID();

    const entries = columns.map((column) => {
      const newValue = encodeScalar(request.changes[column]);
      assertScalarFits(table.name, column, newValue);
      return {
        id: crypto.randomUUID(),
        column,
        oldValue: encodeScalar(current[column] ?? null),
        newValue,
      };
    });

    await this.db.transaction(async (tx) => {
      const values: Row = {};
      for (const column of columns) {
        values[column] = request.changes[column] as Row[string];
      }
      await this.writer.setColumns(tx, table.name, request.systemId, values);

      for (const entry of entries) {
        await tx.execute(
          `INSERT INTO ${quoteIdentifier(OUTBOX_TABLE)} (id, table_name, system_id, column_name, old_value, new_value, changed_at, status, group_id)
           VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)`,
          [entry.id, table.name, request.systemId, entry.column, entry.oldValue, entry.newValue, changedAt, groupId],
        );
      }
      tx.markTableWritten(OUTBOX_TABLE);
    });

    this.notify();
    return groupId;
  }

  /** Bumps the version and tells subscribers (the overlay, the badge) that the queue changed. */
  protected notify(): void {
    this.version++;
    for (const listener of [...this.listeners]) {
      try {
        listener();
      } catch (error) {
        console.error('[declarative-sqlite] outbox listener failed', error);
      }
    }
  }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/sync/outbox-record.test.ts`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
feat(sync): outbox recording with change groups in one transaction

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---
### Task 19: The outbox — statuses, batches and the pending index

The overlay has to answer "which columns of this row are pending" synchronously, thousands of times per emission, so the outbox keeps an in-memory index of its own `pending`/`sending` rows. The index is loaded once at startup and maintained by every mutation — the table stays the durable truth, the index is the fast read of it.

**Files:**
- Modify: `packages/core/src/sync/outbox.ts`
- Test: `packages/core/src/sync/outbox-status.test.ts`

**Interfaces:**
- Consumes: Task 18's `Outbox`, `PushChangeResult`.
- Produces on `Outbox`:
  - `load(): Promise<void>` — reads `pending`/`sending` rows into the index; called once by the runtime
  - `pending(): Promise<OutboxEntry[]>` — status `pending`, oldest first
  - `pendingColumns(table: string, systemId: string): ReadonlySet<string>` — synchronous, from the index
  - `pendingValue(table: string, systemId: string, column: string): { value: unknown } | undefined` — synchronous
  - `markSending(ids: string[], batchId: string): Promise<void>`
  - `applyResults(batchId: string, results: PushChangeResult[], order: string[]): Promise<void>`
  - `resetSending(batchId: string): Promise<void>`
  - `discard(id: string): Promise<void>`
  - `retry(id: string): Promise<void>`
  - `counts(): Promise<{ pending: number; sending: number; rejected: number }>`
  - `entries(filter?: { status?: OutboxStatus }): Promise<OutboxEntry[]>`
  - `purgeOlderThan(days: number, now?: Date): Promise<number>`

- [ ] **Step 1: Write the failing test**

`src/sync/outbox-status.test.ts`:

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox } from './outbox';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  await db.transaction(async (tx) => {
    await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', sync_seq: 5, system_removed: 0 });
  });
  return { db, outbox };
}

describe('Outbox statuses', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('lists pending entries oldest first and indexes their columns', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' } });

    const pending = await s.outbox.pending();
    expect(pending.map((e) => e.columnName).sort()).toEqual(['c_qty_installed', 'rowstate']);
    expect([...s.outbox.pendingColumns('c_work_task', 'A')].sort()).toEqual(['c_qty_installed', 'rowstate']);
    expect(s.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 10 });
  });

  it('marks entries sending with a batch id and keeps them in the index', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const [entry] = await s.outbox.pending();
    await s.outbox.markSending([entry!.id], 'batch-1');

    expect(await s.outbox.pending()).toEqual([]);
    expect(s.outbox.pendingColumns('c_work_task', 'A').has('c_qty_installed')).toBe(true);
    expect((await s.outbox.counts()).sending).toBe(1);
  });

  it('applies results by order index and leaves the index clean', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' } });
    const entries = await s.outbox.pending();
    const order = entries.map((e) => e.id);
    await s.outbox.markSending(order, 'batch-1');

    await s.outbox.applyResults(
      'batch-1',
      [
        { index: 0, result: 'applied', error: null },
        { index: 1, result: 'rejected', error: 'WTCERR2: not allowed' },
      ],
      order,
    );

    const all = await s.outbox.entries();
    expect(all.find((e) => e.id === order[0])?.status).toBe('applied');
    expect(all.find((e) => e.id === order[1])).toMatchObject({ status: 'rejected', errorText: 'WTCERR2: not allowed' });
    expect(s.outbox.pendingColumns('c_work_task', 'A').size).toBe(0);
    expect(await s.outbox.counts()).toMatchObject({ pending: 0, sending: 0, rejected: 1 });
  });

  it('returns a sending batch to pending after a network error', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'batch-1');

    await s.outbox.resetSending('batch-1');

    expect((await s.outbox.pending()).map((e) => e.id)).toEqual(order);
    expect(s.outbox.pendingColumns('c_work_task', 'A').has('c_qty_installed')).toBe(true);
  });

  it('retries a rejected entry and discards another', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'batch-1');
    await s.outbox.applyResults('batch-1', order.map((_, index) => ({ index, result: 'rejected' as const, error: 'no' })), order);

    await s.outbox.retry(order[0]!);
    await s.outbox.discard(order[1]!);

    expect((await s.outbox.pending()).map((e) => e.id)).toEqual([order[0]]);
    expect((await s.outbox.entries()).map((e) => e.id)).toEqual([order[0]]);
    expect(s.outbox.pendingColumns('c_work_task', 'A').has('c_qty_installed')).toBe(true);
    expect(s.outbox.pendingColumns('c_work_task', 'A').has('rowstate')).toBe(false);
  });

  it('leaves entries with no result in the batch back at pending', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'batch-1');
    await s.outbox.applyResults('batch-1', [{ index: 0, result: 'applied', error: null }], order);
    expect((await s.outbox.pending()).map((e) => e.id)).toEqual([order[1]]);
  });

  it('purges settled entries older than the retention window and keeps the rest', async () => {
    const s = await setup();
    db = s.db;
    await db.execute(
      `INSERT INTO outbox (id, table_name, system_id, column_name, old_value, new_value, changed_at, status, group_id)
       VALUES ('old', 'c_work_task', 'A', 'rowstate', 'null', '"X"', '2026-08-01T00:00:00.000Z', 'applied', 'g'),
              ('recent', 'c_work_task', 'A', 'rowstate', 'null', '"Y"', '2026-09-16T00:00:00.000Z', 'applied', 'g'),
              ('open', 'c_work_task', 'A', 'rowstate', 'null', '"Z"', '2026-08-01T00:00:00.000Z', 'rejected', 'g')`,
    );
    const purged = await s.outbox.purgeOlderThan(30, new Date('2026-09-17T00:00:00Z'));
    expect(purged).toBe(1);
    expect((await s.outbox.entries()).map((e) => e.id).sort()).toEqual(['open', 'recent']);
  });

  it('rebuilds the index from the table on load', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });

    const reloaded = new Outbox(s.db, serverWriter(s.db, createServerWriteCapability()));
    await reloaded.load();
    expect(reloaded.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 10 });
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/sync/outbox-status.test.ts`
Expected: FAIL — `outbox.load is not a function`.

- [ ] **Step 3: Add the index and the status methods to `src/sync/outbox.ts`**

```ts
import { decodeScalar, type PushChangeResult } from './wire';

// inside class Outbox:
  private readonly index = new Map<string, Map<string, { entryId: string; value: unknown }>>();

  private static indexKey(table: string, systemId: string): string {
    return `${table}|${systemId}`;
  }

  /** Loads the unconfirmed entries into the in-memory index. Call once after opening the database, before the first read. */
  async load(): Promise<void> {
    this.index.clear();
    const rows = await this.db.query<{ id: string; table_name: string; system_id: string; column_name: string; new_value: string | null }>(
      `SELECT id, table_name, system_id, column_name, new_value FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE status IN ('pending','sending') ORDER BY changed_at`,
    );
    for (const row of rows) this.indexPut(row.table_name, row.system_id, row.column_name, row.id, decodeScalar(row.new_value));
    this.notify();
  }

  private indexPut(table: string, systemId: string, column: string, entryId: string, value: unknown): void {
    const key = Outbox.indexKey(table, systemId);
    let columns = this.index.get(key);
    if (!columns) {
      columns = new Map();
      this.index.set(key, columns);
    }
    columns.set(column, { entryId, value });
  }

  private indexRemove(table: string, systemId: string, column: string, entryId: string): void {
    const key = Outbox.indexKey(table, systemId);
    const columns = this.index.get(key);
    const current = columns?.get(column);
    if (!columns || !current || current.entryId !== entryId) return;
    columns.delete(column);
    if (columns.size === 0) this.index.delete(key);
  }

  /** The columns of this row that are recorded but unconfirmed. Synchronous: the overlay calls it for every row of every emission. */
  pendingColumns(table: string, systemId: string): ReadonlySet<string> {
    return new Set(this.index.get(Outbox.indexKey(table, systemId))?.keys() ?? []);
  }

  /** The value the outbox holds for one column, or `undefined` when nothing is pending for it. */
  pendingValue(table: string, systemId: string, column: string): { value: unknown } | undefined {
    const entry = this.index.get(Outbox.indexKey(table, systemId))?.get(column);
    return entry ? { value: entry.value } : undefined;
  }

  /** Whether any column of this row is unconfirmed. */
  hasPending(table: string, systemId: string): boolean {
    return this.index.has(Outbox.indexKey(table, systemId));
  }

  async pending(): Promise<OutboxEntry[]> {
    return this.entries({ status: 'pending' });
  }

  async entries(filter: { status?: OutboxStatus } = {}): Promise<OutboxEntry[]> {
    const where = filter.status ? ' WHERE status = ?' : '';
    const params = filter.status ? [filter.status] : [];
    const rows = await this.db.query<Record<string, string | null>>(
      `SELECT * FROM ${quoteIdentifier(OUTBOX_TABLE)}${where} ORDER BY changed_at, id`,
      params,
    );
    return rows.map(toEntry);
  }

  async markSending(ids: string[], batchId: string): Promise<void> {
    if (ids.length === 0) return;
    await this.db.transaction(async (tx) => {
      for (const id of ids) {
        await tx.execute(
          `UPDATE ${quoteIdentifier(OUTBOX_TABLE)} SET status = 'sending', batch_id = ? WHERE id = ? AND status = 'pending'`,
          [batchId, id],
        );
      }
      tx.markTableWritten(OUTBOX_TABLE);
    });
    this.notify();
  }

  /**
   * Writes the server's verdict on one batch. `order` is the entry ids in the
   * order the batch listed them, so `results[i].index` names an entry. An entry
   * the answer says nothing about goes back to `pending` and is sent again —
   * the server answers every change it received, so a gap means it never got it.
   */
  async applyResults(batchId: string, results: PushChangeResult[], order: string[]): Promise<void> {
    const appliedAt = (this.options.clock?.() ?? new Date()).toISOString();
    const answered = new Set<string>();

    await this.db.transaction(async (tx) => {
      for (const result of results) {
        const id = order[result.index];
        if (!id) continue;
        answered.add(id);
        const status: OutboxStatus = result.result === 'rejected' ? 'rejected' : result.result;
        await tx.execute(
          `UPDATE ${quoteIdentifier(OUTBOX_TABLE)} SET status = ?, error_text = ?, applied_at = ? WHERE id = ?`,
          [status, result.error ?? null, appliedAt, id],
        );
      }
      for (const id of order) {
        if (answered.has(id)) continue;
        await tx.execute(`UPDATE ${quoteIdentifier(OUTBOX_TABLE)} SET status = 'pending', batch_id = NULL WHERE id = ?`, [id]);
      }
      tx.markTableWritten(OUTBOX_TABLE);
    });

    for (const id of answered) {
      const row = await this.db.queryOne<{ table_name: string; system_id: string; column_name: string }>(
        `SELECT table_name, system_id, column_name FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE id = ?`,
        [id],
      );
      if (row) this.indexRemove(row.table_name, row.system_id, row.column_name, id);
    }
    this.notify();
  }

  /** A network error: the batch never reached a verdict, so its entries queue again. The push service re-sends them under the same batch id. */
  async resetSending(batchId: string): Promise<void> {
    await this.db.transaction(async (tx) => {
      await tx.execute(`UPDATE ${quoteIdentifier(OUTBOX_TABLE)} SET status = 'pending' WHERE batch_id = ? AND status = 'sending'`, [batchId]);
      tx.markTableWritten(OUTBOX_TABLE);
    });
    this.notify();
  }

  /** The user drops a rejected change. The local column keeps the user's value until the next pull overwrites it with server truth. */
  async discard(id: string): Promise<void> {
    const row = await this.db.queryOne<{ table_name: string; system_id: string; column_name: string }>(
      `SELECT table_name, system_id, column_name FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE id = ?`,
      [id],
    );
    await this.db.transaction(async (tx) => {
      await tx.execute(`DELETE FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE id = ?`, [id]);
      tx.markTableWritten(OUTBOX_TABLE);
    });
    if (row) this.indexRemove(row.table_name, row.system_id, row.column_name, id);
    this.notify();
  }

  /** The user retries a rejected change: back to `pending`, error cleared, index restored. */
  async retry(id: string): Promise<void> {
    const row = await this.db.queryOne<{ table_name: string; system_id: string; column_name: string; new_value: string | null }>(
      `SELECT table_name, system_id, column_name, new_value FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE id = ?`,
      [id],
    );
    if (!row) return;
    await this.db.transaction(async (tx) => {
      await tx.execute(
        `UPDATE ${quoteIdentifier(OUTBOX_TABLE)} SET status = 'pending', error_text = NULL, batch_id = NULL, applied_at = NULL WHERE id = ?`,
        [id],
      );
      tx.markTableWritten(OUTBOX_TABLE);
    });
    this.indexPut(row.table_name, row.system_id, row.column_name, id, decodeScalar(row.new_value));
    this.notify();
  }

  async counts(): Promise<{ pending: number; sending: number; rejected: number }> {
    const rows = await this.db.query<{ status: OutboxStatus; n: number }>(
      `SELECT status, COUNT(*) AS n FROM ${quoteIdentifier(OUTBOX_TABLE)} GROUP BY status`,
    );
    const counts = { pending: 0, sending: 0, rejected: 0 };
    for (const row of rows) {
      if (row.status === 'pending') counts.pending = row.n;
      else if (row.status === 'sending') counts.sending = row.n;
      else if (row.status === 'rejected') counts.rejected = row.n;
    }
    return counts;
  }

  /** Deletes settled history (`applied`/`noop`) older than `days`. Rejected entries are never purged: they are waiting for the user. */
  async purgeOlderThan(days: number, now: Date = this.options.clock?.() ?? new Date()): Promise<number> {
    const cutoff = new Date(now.getTime() - days * 24 * 60 * 60 * 1000).toISOString();
    const result = await this.db.execute(
      `DELETE FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE status IN ('applied','noop') AND changed_at < ?`,
      [cutoff],
      { invalidates: [OUTBOX_TABLE] },
    );
    this.notify();
    return result.changes;
  }
```

Add the module-level mapper and make `record` maintain the index (insert `this.indexPut(table.name, request.systemId, entry.column, entry.id, request.changes[entry.column])` for each entry right before `this.notify()`):

```ts
function toEntry(row: Record<string, string | null>): OutboxEntry {
  return {
    id: row['id'] ?? '',
    tableName: row['table_name'] ?? '',
    systemId: row['system_id'] ?? '',
    columnName: row['column_name'] ?? '',
    oldValue: decodeScalar(row['old_value'] ?? null),
    newValue: decodeScalar(row['new_value'] ?? null),
    changedAt: row['changed_at'] ?? '',
    status: (row['status'] ?? 'pending') as OutboxStatus,
    groupId: row['group_id'] ?? '',
    ...(row['batch_id'] ? { batchId: row['batch_id'] } : {}),
    ...(row['error_text'] ? { errorText: row['error_text'] } : {}),
    ...(row['applied_at'] ? { appliedAt: row['applied_at'] } : {}),
  };
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/sync/outbox-status.test.ts`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
feat(sync): outbox statuses, batches and the in-memory pending index

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 20: The overlay

**Files:**
- Create: `packages/core/src/sync/overlay.ts`
- Test: `packages/core/src/sync/overlay.test.ts`

**Interfaces:**
- Consumes: `Outbox`, `Database`, `Row`.
- Produces: `class Overlay { constructor(db: Database, outbox: Outbox); apply(table: string, rows: Row[]): Row[] }`

- [ ] **Step 1: Write the failing test**

`src/sync/overlay.test.ts`:

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox } from './outbox';
import { Overlay } from './overlay';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  s.table('local_prefs', (t) => t.text('value'));
  return s.build();
}

async function setup() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  await db.transaction(async (tx) => {
    await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', sync_seq: 5, system_removed: 0 });
  });
  return { db, outbox, overlay: new Overlay(db, outbox) };
}

describe('Overlay', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('returns the same array when nothing is pending', async () => {
    const s = await setup();
    db = s.db;
    const rows = [{ system_id: 'A', c_qty_installed: 1 }];
    expect(s.overlay.apply('c_work_task', rows)).toBe(rows);
  });

  it('replaces pending columns with the recorded value', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const overlaid = s.overlay.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 1, rowstate: 'RELEASED' }]);
    expect(overlaid[0]).toEqual({ system_id: 'A', c_qty_installed: 10, rowstate: 'RELEASED' });
  });

  it('keeps the identity of rows with nothing pending', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const untouched = { system_id: 'B', c_qty_installed: 2 };
    const result = s.overlay.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 1 }, untouched]);
    expect(result[1]).toBe(untouched);
  });

  it('stops overlaying once the change is applied', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'b1');
    expect(s.overlay.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 1 }])[0]?.c_qty_installed).toBe(10);

    await s.outbox.applyResults('b1', [{ index: 0, result: 'applied', error: null }], order);
    expect(s.overlay.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 1 }])[0]?.c_qty_installed).toBe(1);
  });

  it('keeps overlaying a rejected change until the user resolves it', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'b1');
    await s.outbox.applyResults('b1', [{ index: 0, result: 'rejected', error: 'no' }], order);
    // A rejected change is no longer pending, so server truth shows through and
    // the rejection is visible in the outbox instead of silently winning.
    expect(s.overlay.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 1 }])[0]?.c_qty_installed).toBe(1);
  });

  it('leaves a table with no synced declaration alone', async () => {
    const s = await setup();
    db = s.db;
    const rows = [{ system_id: 'p1', value: 'x' }];
    expect(s.overlay.apply('local_prefs', rows)).toBe(rows);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/sync/overlay.test.ts`
Expected: FAIL — `Failed to resolve import "./overlay"`.

- [ ] **Step 3: Write `src/sync/overlay.ts`**

```ts
import type { Database } from '../db/database';
import { toSqlValue } from '../db/tables';
import type { Row } from '../types';
import type { Outbox } from './outbox';

/**
 * Makes reads of a synced table show what the user did, not what the server last
 * said: every column with a `pending` or `sending` outbox entry is replaced by
 * the recorded value. Applied inside the live layer before emission, so no
 * consumer can observe raw server truth for a column the outbox owns. A column
 * whose change was answered — applied, noop or rejected — is no longer pending,
 * so server truth shows through again and a rejection becomes visible.
 */
export class Overlay {
  constructor(
    private readonly db: Database,
    private readonly outbox: Outbox,
  ) {}

  apply(table: string, rows: Row[]): Row[] {
    const def = this.db.schema.tables.find((t) => t.name === table);
    if (!def?.synced) return rows;
    const keyColumn = def.synced.key;

    let changed = false;
    const result = rows.map((row) => {
      const systemId = String(row[keyColumn] ?? '');
      if (!systemId || !this.outbox.hasPending(table, systemId)) return row;
      const columns = this.outbox.pendingColumns(table, systemId);
      if (columns.size === 0) return row;
      const overlaid: Row = { ...row };
      for (const column of columns) {
        if (!(column in row)) continue;
        const pending = this.outbox.pendingValue(table, systemId, column);
        if (!pending) continue;
        overlaid[column] = toSqlValue(pending.value);
      }
      changed = true;
      return overlaid;
    });

    return changed ? result : rows;
  }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/sync/overlay.test.ts`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
feat(sync): pending overlay so reads show what the user did

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 21: The draft store — focus lifecycle and column holds

A `(row, column)` enters draft when its input takes focus, not when the view opens: lists stay live. While a draft exists, that column holds the value it last showed, and the row's other columns keep updating. The store lives in the library, keyed `(table, systemId, column)`, so a virtualised list unmounting a row cannot lose keystrokes.

**Files:**
- Create: `packages/core/src/sync/drafts.ts`
- Test: `packages/core/src/sync/drafts.test.ts`

**Interfaces:**
- Consumes: `Outbox`, `Database`, `Row`.
- Produces:
  - `interface DraftState { value: unknown; seed: unknown; heldServerValue?: { value: unknown }; heldTombstone?: boolean }`
  - `class Drafts { constructor(db: Database, outbox: Outbox); begin(table: string, systemId: string, column: string, seedValue: unknown): void; set(table: string, systemId: string, column: string, value: unknown): void; get(table: string, systemId: string, column: string): unknown; isActive(table: string, systemId: string, column: string): boolean; activeColumns(table: string, systemId: string): ReadonlySet<string>; apply(table: string, rows: Row[]): Row[]; subscribe(listener: () => void): () => void }`

- [ ] **Step 1: Write the failing test**

`src/sync/drafts.test.ts`:

```ts
import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox } from './outbox';
import { Drafts } from './drafts';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  await db.transaction(async (tx) => {
    await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', sync_seq: 5, system_removed: 0 });
  });
  return { db, outbox, writer, drafts: new Drafts(db, outbox) };
}

describe('Drafts', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('is inactive until a field takes focus', async () => {
    const s = await setup();
    db = s.db;
    expect(s.drafts.isActive('c_work_task', 'A', 'c_qty_installed')).toBe(false);
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    expect(s.drafts.isActive('c_work_task', 'A', 'c_qty_installed')).toBe(true);
    expect(s.drafts.get('c_work_task', 'A', 'c_qty_installed')).toBe(1);
  });

  it('keeps keystrokes and notifies subscribers', async () => {
    const s = await setup();
    db = s.db;
    const listener = vi.fn();
    s.drafts.subscribe(listener);
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);
    expect(s.drafts.get('c_work_task', 'A', 'c_qty_installed')).toBe(12);
    expect(listener).toHaveBeenCalled();
  });

  it('holds the drafted column at its last emitted value and lets siblings update', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);

    const held = s.drafts.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 7, rowstate: 'WORKSTARTED' }]);
    expect(held[0]).toEqual({ system_id: 'A', c_qty_installed: 1, rowstate: 'WORKSTARTED' });
  });

  it('shows the typed value, not the seed, while typing', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);
    expect(s.drafts.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 7 }])[0]?.c_qty_installed).toBe(12);
  });

  it('only holds the focused column of the focused row', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    const rows = [{ system_id: 'B', c_qty_installed: 9 }];
    expect(s.drafts.apply('c_work_task', rows)).toBe(rows);
    expect([...s.drafts.activeColumns('c_work_task', 'A')]).toEqual(['c_qty_installed']);
    expect(s.drafts.activeColumns('c_work_task', 'B').size).toBe(0);
  });

  it('returns the same array when no draft touches the rows', async () => {
    const s = await setup();
    db = s.db;
    const rows = [{ system_id: 'A', c_qty_installed: 1 }];
    expect(s.drafts.apply('c_work_task', rows)).toBe(rows);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/sync/drafts.test.ts`
Expected: FAIL — `Failed to resolve import "./drafts"`.

- [ ] **Step 3: Write `src/sync/drafts.ts` (lifecycle and holds; Task 22 adds `end`)**

```ts
import type { Database } from '../db/database';
import { toSqlValue } from '../db/tables';
import type { Row } from '../types';
import type { Outbox } from './outbox';

/** One drafted column: what is in the input now, what it was seeded with, and anything the server said while the user was typing. */
export interface DraftState {
  value: unknown;
  seed: unknown;
  heldServerValue?: { value: unknown };
  heldTombstone?: boolean;
}

/**
 * The third owner of state: what is being typed right now. A `(table, systemId,
 * column)` becomes a draft on focus and stops being one on blur, Enter, save,
 * Sync, a route change or `pagehide`. While it is a draft the column is held at
 * the drafted value no matter what a pull writes underneath, and a tombstone for
 * the row is held too — the rest of the row keeps updating live. Drafts live
 * here, never in a component, so a virtualised list can unmount the row without
 * losing a keystroke.
 */
export class Drafts {
  protected readonly drafts = new Map<string, Map<string, DraftState>>();
  private readonly listeners = new Set<() => void>();

  constructor(
    protected readonly db: Database,
    protected readonly outbox: Outbox,
  ) {}

  protected static rowKey(table: string, systemId: string): string {
    return `${table}|${systemId}`;
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  begin(table: string, systemId: string, column: string, seedValue: unknown): void {
    const key = Drafts.rowKey(table, systemId);
    let columns = this.drafts.get(key);
    if (!columns) {
      columns = new Map();
      this.drafts.set(key, columns);
    }
    if (!columns.has(column)) columns.set(column, { value: seedValue, seed: seedValue });
    this.notify();
  }

  set(table: string, systemId: string, column: string, value: unknown): void {
    const state = this.drafts.get(Drafts.rowKey(table, systemId))?.get(column);
    if (!state) return;
    state.value = value;
    this.notify();
  }

  get(table: string, systemId: string, column: string): unknown {
    return this.drafts.get(Drafts.rowKey(table, systemId))?.get(column)?.value;
  }

  isActive(table: string, systemId: string, column: string): boolean {
    return this.drafts.get(Drafts.rowKey(table, systemId))?.has(column) ?? false;
  }

  activeColumns(table: string, systemId: string): ReadonlySet<string> {
    return new Set(this.drafts.get(Drafts.rowKey(table, systemId))?.keys() ?? []);
  }

  /** Applies the holds to rows on their way to a subscriber: drafted columns keep the drafted value; everything else passes through. */
  apply(table: string, rows: Row[]): Row[] {
    if (this.drafts.size === 0) return rows;
    const def = this.db.schema.tables.find((t) => t.name === table);
    const keyColumn = def?.synced?.key ?? 'system_id';

    let changed = false;
    const result = rows.map((row) => {
      const columns = this.drafts.get(Drafts.rowKey(table, String(row[keyColumn] ?? '')));
      if (!columns || columns.size === 0) return row;
      const held: Row = { ...row };
      for (const [column, state] of columns) {
        if (!(column in row)) continue;
        held[column] = toSqlValue(state.value);
      }
      changed = true;
      return held;
    });

    return changed ? result : rows;
  }

  protected notify(): void {
    for (const listener of [...this.listeners]) {
      try {
        listener();
      } catch (error) {
        console.error('[declarative-sqlite] draft listener failed', error);
      }
    }
  }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/sync/drafts.test.ts`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
feat(sync): draft store with focus lifecycle and per-column holds

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 22: Draft exits — held server values, held tombstones, and `endAll`

Ending a draft is where the three owners hand over. Changed: the value goes to the outbox and the overlay takes over the column, and any server value held for it is dropped — superseded, and visible in `C_WORK_SYNC_LOG`. Unchanged: the held server value applies now. Either way a held tombstone applies at the end, after which the push answers `CNOROW` and the outbox shows the change as rejected.

**Files:**
- Modify: `packages/core/src/sync/drafts.ts`
- Test: `packages/core/src/sync/drafts-exit.test.ts`

**Interfaces:**
- Consumes: Task 21's `Drafts`, `Outbox`, `ServerWriter`.
- Produces on `Drafts`:
  - `constructor(db: Database, outbox: Outbox, writer: ServerWriter)` (the writer is new in this task)
  - `holdServerValue(table: string, systemId: string, column: string, value: unknown): boolean` — true when the value was held instead of written
  - `holdTombstone(table: string, systemId: string): boolean`
  - `hasHolds(table: string, systemId: string): boolean`
  - `end(table: string, systemId: string, column: string): Promise<'committed' | 'released'>`
  - `endRow(table: string, systemId: string): Promise<void>`
  - `endAll(): Promise<void>`

- [ ] **Step 1: Write the failing test**

`src/sync/drafts-exit.test.ts`:

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox } from './outbox';
import { Drafts } from './drafts';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  await db.transaction(async (tx) => {
    await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', sync_seq: 5, system_removed: 0 });
  });
  return { db, outbox, writer, drafts: new Drafts(db, outbox, writer) };
}

describe('Drafts.end', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('commits a changed value to the outbox and clears the draft', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);

    expect(await s.drafts.end('c_work_task', 'A', 'c_qty_installed')).toBe('committed');
    expect(s.drafts.isActive('c_work_task', 'A', 'c_qty_installed')).toBe(false);
    expect(s.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 12 });
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 12 });
  });

  it('records nothing when the value did not change', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    expect(await s.drafts.end('c_work_task', 'A', 'c_qty_installed')).toBe('released');
    expect(await db.query('SELECT id FROM outbox')).toEqual([]);
  });

  it('holds a server value for a drafted column and applies it on an unchanged end', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);

    expect(s.drafts.holdServerValue('c_work_task', 'A', 'c_qty_installed', 7)).toBe(true);
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 1 });

    await s.drafts.end('c_work_task', 'A', 'c_qty_installed');
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 7 });
  });

  it('drops the held server value when the user changed the column', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.holdServerValue('c_work_task', 'A', 'c_qty_installed', 7);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);

    await s.drafts.end('c_work_task', 'A', 'c_qty_installed');
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 12 });
    expect(s.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 12 });
  });

  it('does not hold a server value for a column that is not drafted', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    expect(s.drafts.holdServerValue('c_work_task', 'A', 'rowstate', 'WORKSTARTED')).toBe(false);
  });

  it('holds a tombstone while a draft is open and deletes the row at the end, after recording', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);

    expect(s.drafts.holdTombstone('c_work_task', 'A')).toBe(true);
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeDefined();

    await s.drafts.end('c_work_task', 'A', 'c_qty_installed');

    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeUndefined();
    expect((await s.outbox.pending()).map((e) => e.columnName)).toEqual(['c_qty_installed']);
  });

  it('does not hold a tombstone for a row with no draft', async () => {
    const s = await setup();
    db = s.db;
    expect(s.drafts.holdTombstone('c_work_task', 'A')).toBe(false);
  });

  it('endAll commits every open draft', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 3);
    s.drafts.begin('c_work_task', 'A', 'rowstate', 'RELEASED');
    s.drafts.set('c_work_task', 'A', 'rowstate', 'WORKSTARTED');

    await s.drafts.endAll();

    expect(s.drafts.activeColumns('c_work_task', 'A').size).toBe(0);
    expect((await s.outbox.pending()).map((e) => e.columnName).sort()).toEqual(['c_qty_installed', 'rowstate']);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/sync/drafts-exit.test.ts`
Expected: FAIL — `drafts.holdServerValue is not a function`.

- [ ] **Step 3: Extend `src/sync/drafts.ts`**

Add `private readonly writer: ServerWriter` as the third constructor argument, then:

```ts
  /**
   * Offers a server value for a column. If that column is being typed, the value
   * is held until the draft ends and `true` is returned, so the pull applier
   * knows not to write it; otherwise nothing happens and `false` is returned.
   */
  holdServerValue(table: string, systemId: string, column: string, value: unknown): boolean {
    const state = this.drafts.get(Drafts.rowKey(table, systemId))?.get(column);
    if (!state) return false;
    state.heldServerValue = { value };
    return true;
  }

  /** Offers a tombstone for a row. Held while any column of the row is being typed, so the row cannot vanish under the user's fingers. */
  holdTombstone(table: string, systemId: string): boolean {
    const columns = this.drafts.get(Drafts.rowKey(table, systemId));
    if (!columns || columns.size === 0) return false;
    for (const state of columns.values()) state.heldTombstone = true;
    return true;
  }

  hasHolds(table: string, systemId: string): boolean {
    const columns = this.drafts.get(Drafts.rowKey(table, systemId));
    return columns !== undefined && columns.size > 0;
  }

  /**
   * Ends one draft — blur, Enter, save, Sync, route change or `pagehide`. A
   * changed value is committed to SQLite and the outbox in one transaction and
   * the overlay takes the column over, which supersedes any server value held
   * for it. An unchanged value releases the column and applies the held server
   * value, if there is one. A held tombstone applies last, after the commit, so
   * the change is in the queue when the push answers `CNOROW` for it.
   */
  async end(table: string, systemId: string, column: string): Promise<'committed' | 'released'> {
    const key = Drafts.rowKey(table, systemId);
    const columns = this.drafts.get(key);
    const state = columns?.get(column);
    if (!columns || !state) return 'released';

    columns.delete(column);
    if (columns.size === 0) this.drafts.delete(key);

    const changed = !Object.is(state.value, state.seed);
    if (changed) {
      await this.outbox.record({ table, systemId, changes: { [column]: state.value } });
    } else if (state.heldServerValue) {
      await this.db.transaction(async (tx) => {
        await this.writer.setColumns(tx, table, systemId, { [column]: toSqlValue(state.heldServerValue?.value) });
      });
    }

    if (state.heldTombstone && !this.hasHolds(table, systemId)) {
      await this.db.transaction(async (tx) => {
        await this.writer.delete(tx, table, systemId);
      });
    }

    this.notify();
    return changed ? 'committed' : 'released';
  }

  /** Ends every draft on one row, in column order. */
  async endRow(table: string, systemId: string): Promise<void> {
    for (const column of [...this.activeColumns(table, systemId)]) {
      await this.end(table, systemId, column);
    }
  }

  /** Ends every open draft. The exit paths — Sync button, route change, `pagehide`, `visibilitychange` — call this. */
  async endAll(): Promise<void> {
    for (const key of [...this.drafts.keys()]) {
      const [table, systemId] = key.split('|');
      if (table === undefined || systemId === undefined) continue;
      await this.endRow(table, systemId);
    }
  }
```

- [ ] **Step 4: Run both draft test files and watch them pass**

Run: `npm test -- src/sync/drafts.test.ts src/sync/drafts-exit.test.ts`
Expected: PASS, 14 tests. Update Task 21's `setup()` in `drafts.test.ts` to pass the writer as the third constructor argument.

- [ ] **Step 5: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
feat(sync): draft exits with held server values and held tombstones

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 23: The cursor store

**Files:**
- Create: `packages/core/src/sync/cursor-store.ts`
- Test: `packages/core/src/sync/cursor-store.test.ts`

**Interfaces:**
- Consumes: `Database`, `scopeKey`, `formatScope`, `parseScope`, `SYNC_CURSOR_TABLE`, `ScopeValues`.
- Produces:
  - `interface CursorRow { scopeKey: string; table: string; scope?: ScopeValues; lastSyncSeq: number; syncedAt: string }`
  - `class CursorStore { constructor(db: Database, options?: { clock?: () => Date }); get(table: string, scope?: ScopeValues): Promise<number>; set(table: string, scope: ScopeValues | undefined, seq: number): Promise<void>; all(): Promise<CursorRow[]>; forTable(table: string): Promise<CursorRow[]>; reset(table: string, scope?: ScopeValues): Promise<void> }`

- [ ] **Step 1: Write the failing test**

`src/sync/cursor-store.test.ts`:

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { CursorStore } from './cursor-store';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => t.real('wo_no')).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

describe('CursorStore', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('starts at zero for an unknown scope', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    expect(await new CursorStore(db).get('c_work_task', { wo_no: 3188 })).toBe(0);
  });

  it('stores a cursor per scope', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const cursors = new CursorStore(db);
    await cursors.set('c_work_task', { wo_no: 3188 }, 184240);
    await cursors.set('c_work_task', { wo_no: 4000 }, 12);

    expect(await cursors.get('c_work_task', { wo_no: 3188 })).toBe(184240);
    expect(await cursors.get('c_work_task', { wo_no: 4000 })).toBe(12);
  });

  it('never moves a cursor backwards', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const cursors = new CursorStore(db);
    await cursors.set('c_work_task', { wo_no: 3188 }, 500);
    await cursors.set('c_work_task', { wo_no: 3188 }, 100);
    expect(await cursors.get('c_work_task', { wo_no: 3188 })).toBe(500);
  });

  it('keeps a full-table cursor apart from a scoped one', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const cursors = new CursorStore(db);
    await cursors.set('c_work_task', undefined, 9);
    await cursors.set('c_work_task', { wo_no: 3188 }, 20);
    expect(await cursors.get('c_work_task', undefined)).toBe(9);
    const rows = await cursors.forTable('c_work_task');
    expect(rows.map((r) => r.scopeKey).sort()).toEqual(['c_work_task|*', 'c_work_task|WO_NO:3188']);
  });

  it('reads the scope back out of a stored cursor', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const cursors = new CursorStore(db);
    await cursors.set('c_work_task', { wo_no: 3188 }, 20);
    expect((await cursors.all())[0]?.scope).toEqual({ wo_no: '3188' });
  });

  it('resets a cursor to zero', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const cursors = new CursorStore(db);
    await cursors.set('c_work_task', { wo_no: 3188 }, 20);
    await cursors.reset('c_work_task', { wo_no: 3188 });
    expect(await cursors.get('c_work_task', { wo_no: 3188 })).toBe(0);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/sync/cursor-store.test.ts`
Expected: FAIL — `Failed to resolve import "./cursor-store"`.

- [ ] **Step 3: Write `src/sync/cursor-store.ts`**

```ts
import type { Database } from '../db/database';
import { quoteIdentifier } from '../db/sql';
import { SYNC_CURSOR_TABLE } from '../schema/library-tables';
import { formatScope, parseScope, scopeKey } from '../schema/scopes';
import type { ScopeValues } from '../types';

/** One stored cursor: the high-water `SYNC_SEQ` this device has pulled for one `(table, scope)`. */
export interface CursorRow {
  scopeKey: string;
  table: string;
  scope?: ScopeValues;
  lastSyncSeq: number;
  syncedAt: string;
}

/**
 * Remembers how far this device has pulled each `(table, scope)`. A cursor is a
 * high-water mark and only ever moves forward, so a page that arrives out of
 * order cannot rewind it; the rewind that catches rows behind the cursor is the
 * pull service's window rule, not a cursor edit.
 */
export class CursorStore {
  constructor(
    private readonly db: Database,
    private readonly options: { clock?: () => Date } = {},
  ) {}

  async get(table: string, scope?: ScopeValues): Promise<number> {
    const row = await this.db.queryOne<{ last_sync_seq: number }>(
      `SELECT last_sync_seq FROM ${quoteIdentifier(SYNC_CURSOR_TABLE)} WHERE scope_key = ?`,
      [scopeKey(table, scope)],
    );
    return row?.last_sync_seq ?? 0;
  }

  async set(table: string, scope: ScopeValues | undefined, seq: number): Promise<void> {
    const key = scopeKey(table, scope);
    const syncedAt = (this.options.clock?.() ?? new Date()).toISOString();
    await this.db.transaction(async (tx) => {
      await tx.execute(
        `INSERT INTO ${quoteIdentifier(SYNC_CURSOR_TABLE)} (scope_key, table_name, scope, last_sync_seq, synced_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(scope_key) DO UPDATE SET
           last_sync_seq = MAX(excluded.last_sync_seq, ${quoteIdentifier(SYNC_CURSOR_TABLE)}.last_sync_seq),
           synced_at = excluded.synced_at`,
        [key, table, formatScope(scope) ?? null, seq, syncedAt],
      );
      tx.markTableWritten(SYNC_CURSOR_TABLE);
    });
  }

  async all(): Promise<CursorRow[]> {
    const rows = await this.db.query<{ scope_key: string; table_name: string; scope: string | null; last_sync_seq: number; synced_at: string }>(
      `SELECT scope_key, table_name, scope, last_sync_seq, synced_at FROM ${quoteIdentifier(SYNC_CURSOR_TABLE)} ORDER BY scope_key`,
    );
    return rows.map((row) => ({
      scopeKey: row.scope_key,
      table: row.table_name,
      ...(row.scope ? { scope: parseScope(row.scope) } : {}),
      lastSyncSeq: row.last_sync_seq,
      syncedAt: row.synced_at,
    }));
  }

  async forTable(table: string): Promise<CursorRow[]> {
    return (await this.all()).filter((row) => row.table === table);
  }

  /** Forgets a cursor so the next pull reads the scope whole. The manual refresh path uses `from: 0` instead and leaves the cursor alone. */
  async reset(table: string, scope?: ScopeValues): Promise<void> {
    await this.db.transaction(async (tx) => {
      await tx.execute(`DELETE FROM ${quoteIdentifier(SYNC_CURSOR_TABLE)} WHERE scope_key = ?`, [scopeKey(table, scope)]);
      tx.markTableWritten(SYNC_CURSOR_TABLE);
    });
  }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/sync/cursor-store.test.ts`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
feat(sync): per (table, scope) cursor store that only moves forward

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---
### Task 24: The pull applier

One page is one transaction and therefore one invalidation event. The applier is the only place server truth enters the tables, and it is where the two hand-over rules live: a column with a `pending`/`sending` outbox entry is not overwritten, and a column being typed is held for the draft instead.

**Files:**
- Create: `packages/core/src/sync/pull-applier.ts`
- Test: `packages/core/src/sync/pull-applier.test.ts`

**Interfaces:**
- Consumes: `Database`, `ServerWriter`, `Outbox`, `Drafts`, `CursorStore`, `RowsPage`, `RowDoc`, `fromWireData`, `SYNC_SEQ_COLUMN`.
- Produces:
  - `interface ApplyOptions { scope?: ScopeValues; advanceCursor?: boolean; seqGuard?: boolean }`
  - `interface ApplyReport { upserted: number; deleted: number; skippedBySeq: number; heldColumns: number; heldTombstones: number; keptPendingColumns: number }`
  - `class PullApplier { constructor(db: Database, writer: ServerWriter, outbox: Outbox, drafts: Drafts, cursors: CursorStore); applyPage(table: string, page: RowsPage, options?: ApplyOptions): Promise<ApplyReport>; applyRows(table: string, rows: RowDoc[], options?: ApplyOptions): Promise<ApplyReport> }`

- [ ] **Step 1: Write the failing test**

`src/sync/pull-applier.test.ts`:

```ts
import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox } from './outbox';
import { Drafts } from './drafts';
import { CursorStore } from './cursor-store';
import { PullApplier } from './pull-applier';
import type { RowsPage } from './wire';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  const drafts = new Drafts(db, outbox, writer);
  const cursors = new CursorStore(db);
  const applier = new PullApplier(db, writer, outbox, drafts, cursors);
  return { db, writer, outbox, drafts, cursors, applier };
}

const page = (rows: RowsPage['rows'], next: number): RowsPage => ({ table: 'C_WORK_TASK', rows, next, hasMore: false });

describe('PullApplier', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('upserts rows, stamps sync_seq and advances the cursor', async () => {
    const s = await setup();
    db = s.db;
    const report = await s.applier.applyPage(
      'c_work_task',
      page([{ id: 'A', seq: 100, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 5, ROWSTATE: 'RELEASED' } }], 100),
      { scope: { wo_no: 3188 } },
    );

    expect(report.upserted).toBe(1);
    expect(await db.queryOne('SELECT wo_no, c_qty_installed, rowstate, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      wo_no: 3188, c_qty_installed: 5, rowstate: 'RELEASED', sync_seq: 100,
    });
    expect(await s.cursors.get('c_work_task', { wo_no: 3188 })).toBe(100);
  });

  it('commits a 200-row page as one transaction and one invalidation', async () => {
    const s = await setup();
    db = s.db;
    const listener = vi.fn();
    db.invalidations.subscribe(listener);

    const rows = Array.from({ length: 200 }, (_, i) => ({ id: `row-${i}`, seq: i + 1, removed: false, data: { WO_NO: 3188 } }));
    await s.applier.applyPage('c_work_task', page(rows, 200), { scope: { wo_no: 3188 } });

    expect(listener).toHaveBeenCalledTimes(1);
    expect(await db.query('SELECT system_id FROM c_work_task')).toHaveLength(200);
  });

  it('deletes a tombstoned row', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 1, removed: false, data: { WO_NO: 3188 } }], 1));
    const report = await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 2, removed: true, data: {} }], 2));
    expect(report.deleted).toBe(1);
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeUndefined();
  });

  it('never overwrites a column with a pending outbox entry, but writes the rest of the row', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 1, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } }], 1));
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });

    const report = await s.applier.applyPage(
      'c_work_task',
      page([{ id: 'A', seq: 2, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 99, ROWSTATE: 'WORKSTARTED' } }], 2),
    );

    expect(report.keptPendingColumns).toBe(1);
    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 10, rowstate: 'WORKSTARTED',
    });
  });

  it('holds a column that is being typed and applies it when the draft ends unchanged', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 1, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }], 1));
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);

    const report = await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 2, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 7 } }], 2));
    expect(report.heldColumns).toBe(1);
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 1 });

    await s.drafts.end('c_work_task', 'A', 'c_qty_installed');
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 7 });
  });

  it('holds a tombstone while the row is being typed', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 1, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }], 1));
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);

    const report = await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 2, removed: true, data: {} }], 2));
    expect(report.heldTombstones).toBe(1);
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeDefined();
  });

  it('skips a row whose seq is not above the local one when the guard is on', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 10, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }], 10));

    const report = await s.applier.applyRows(
      'c_work_task',
      [{ id: 'A', seq: 10, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 42 } }],
      { seqGuard: true, advanceCursor: false },
    );

    expect(report.skippedBySeq).toBe(1);
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 1 });
  });

  it('applies answer rows whose seq is above the local one', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 10, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }], 10));
    await s.applier.applyRows('c_work_task', [{ id: 'A', seq: 11, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 42 } }], {
      seqGuard: true, advanceCursor: false,
    });
    expect(await db.queryOne('SELECT c_qty_installed, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 42, sync_seq: 11,
    });
  });

  it('does not advance the cursor when told not to', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyRows('c_work_task', [{ id: 'A', seq: 10, removed: false, data: { WO_NO: 3188 } }], {
      scope: { wo_no: 3188 }, advanceCursor: false,
    });
    expect(await s.cursors.get('c_work_task', { wo_no: 3188 })).toBe(0);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/sync/pull-applier.test.ts`
Expected: FAIL — `Failed to resolve import "./pull-applier"`.

- [ ] **Step 3: Write `src/sync/pull-applier.ts`**

```ts
import type { Database } from '../db/database';
import type { ServerWriter } from '../db/server-truth';
import { quoteIdentifier } from '../db/sql';
import { SYNC_SEQ_COLUMN, SYSTEM_REMOVED_COLUMN } from '../schema/table-builder';
import type { Row, ScopeValues } from '../types';
import type { CursorStore } from './cursor-store';
import type { Drafts } from './drafts';
import type { Outbox } from './outbox';
import { fromWireData, type RowDoc, type RowsPage } from './wire';

/** How a set of server rows should be applied. `seqGuard` is for push answers, which are a receipt rather than a read. */
export interface ApplyOptions {
  scope?: ScopeValues;
  /** Default true for `applyPage`, false for `applyRows`. */
  advanceCursor?: boolean;
  /** Skips a row whose `seq` is not above the local `sync_seq`. Default false for `applyPage`, true for `applyRows`. */
  seqGuard?: boolean;
}

/** What one apply did, for logs and tests. */
export interface ApplyReport {
  upserted: number;
  deleted: number;
  skippedBySeq: number;
  heldColumns: number;
  heldTombstones: number;
  keptPendingColumns: number;
}

/**
 * The only path server truth takes into the local tables. One page is one
 * transaction and therefore one invalidation event, however many rows it holds.
 * Two rules protect what the user is doing: a column with a `pending` or
 * `sending` outbox entry keeps the local value until the push answers, and a
 * column being typed — or a tombstone for a row being typed — is handed to the
 * draft store to hold until the draft ends.
 */
export class PullApplier {
  constructor(
    private readonly db: Database,
    private readonly writer: ServerWriter,
    private readonly outbox: Outbox,
    private readonly drafts: Drafts,
    private readonly cursors: CursorStore,
  ) {}

  async applyPage(table: string, page: RowsPage, options: ApplyOptions = {}): Promise<ApplyReport> {
    const report = await this.applyRows(table, page.rows, { ...options, advanceCursor: false, seqGuard: options.seqGuard ?? false });
    if (options.advanceCursor !== false) await this.cursors.set(table, options.scope, page.next);
    return report;
  }

  async applyRows(table: string, rows: RowDoc[], options: ApplyOptions = {}): Promise<ApplyReport> {
    const def = this.db.tableDef(table);
    if (!def.synced) throw new Error(`${table} is not a synced table`);
    const keyColumn = def.synced.key;
    const seqGuard = options.seqGuard ?? true;

    const report: ApplyReport = { upserted: 0, deleted: 0, skippedBySeq: 0, heldColumns: 0, heldTombstones: 0, keptPendingColumns: 0 };

    await this.db.transaction(async (tx) => {
      for (const doc of rows) {
        const existing = await tx.queryOne<{ [SYNC_SEQ_COLUMN]: number }>(
          `SELECT ${quoteIdentifier(SYNC_SEQ_COLUMN)} FROM ${quoteIdentifier(table)} WHERE ${quoteIdentifier(keyColumn)} = ?`,
          [doc.id],
        );
        if (seqGuard && existing && doc.seq <= Number(existing[SYNC_SEQ_COLUMN] ?? 0)) {
          report.skippedBySeq++;
          continue;
        }

        if (doc.removed) {
          if (this.drafts.holdTombstone(table, doc.id)) {
            report.heldTombstones++;
            continue;
          }
          report.deleted += await this.writer.delete(tx, table, doc.id);
          continue;
        }

        const values = fromWireData(def, doc.data);
        const pending = this.outbox.pendingColumns(table, doc.id);
        const drafted = this.drafts.activeColumns(table, doc.id);

        const write: Row = {};
        for (const [column, value] of Object.entries(values)) {
          if (pending.has(column)) {
            report.keptPendingColumns++;
            continue;
          }
          if (drafted.has(column)) {
            this.drafts.holdServerValue(table, doc.id, column, value);
            report.heldColumns++;
            continue;
          }
          write[column] = value;
        }

        write[keyColumn] = doc.id;
        write[SYNC_SEQ_COLUMN] = doc.seq;
        write[SYSTEM_REMOVED_COLUMN] = 0;
        await this.writer.upsert(tx, table, write);
        report.upserted++;
      }
    });

    if (options.advanceCursor === true && rows.length > 0) {
      await this.cursors.set(table, options.scope, Math.max(...rows.map((r) => r.seq)));
    }
    return report;
  }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/sync/pull-applier.test.ts`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
feat(sync): pull applier honouring pending columns, holds and the seq guard

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 25: The pull service — paging, the window rule and open scopes

**Files:**
- Create: `packages/core/src/sync/pull-service.ts`
- Test: `packages/core/src/sync/pull-service.test.ts`

**Interfaces:**
- Consumes: `SyncTransport`, `PullApplier`, `CursorStore`, `formatScope`, `toWireTable`, `PULL_WINDOW`, `DEFAULT_PAGE_LIMIT`.
- Produces:
  - `interface PullOptions { from?: 'cursor' | 'window' | 0; limit?: number; maxPages?: number }`
  - `interface PullReport { rows: number; pages: number; cursor: number }`
  - `class PullService { constructor(transport: SyncTransport, applier: PullApplier, cursors: CursorStore, options?: { window?: number; pageLimit?: number }); pull(table: string, scope?: ScopeValues, options?: PullOptions): Promise<PullReport>; registerScope(table: string, scope?: ScopeValues): () => void; openScopes(table: string): Array<ScopeValues | undefined> }`

- [ ] **Step 1: Write the failing test**

`src/sync/pull-service.test.ts`:

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { FakeTransport } from '../testing/fake-transport';
import { Outbox } from './outbox';
import { Drafts } from './drafts';
import { CursorStore } from './cursor-store';
import { PullApplier } from './pull-applier';
import { PullService } from './pull-service';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup(pageSize = 2) {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  const drafts = new Drafts(db, outbox, writer);
  const cursors = new CursorStore(db);
  const applier = new PullApplier(db, writer, outbox, drafts, cursors);
  const transport = new FakeTransport({ pageSize });
  const pull = new PullService(transport, applier, cursors, { window: 1000 });
  return { db, transport, cursors, pull };
}

describe('PullService', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('follows hasMore until the scope is exhausted', async () => {
    const s = await setup(2);
    db = s.db;
    s.transport.seed('C_WORK_TASK', [
      { id: 'A', data: { WO_NO: 3188 } }, { id: 'B', data: { WO_NO: 3188 } }, { id: 'C', data: { WO_NO: 3188 } },
    ]);

    const report = await s.pull.pull('c_work_task', { wo_no: 3188 });
    expect(report).toMatchObject({ rows: 3, pages: 2 });
    expect(await db.query('SELECT system_id FROM c_work_task')).toHaveLength(3);
  });

  it('sends the wire table name and the formatted scope', async () => {
    const s = await setup();
    db = s.db;
    s.transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188 } }]);
    await s.pull.pull('c_work_task', { wo_no: 3188 });
    expect(s.transport.pulls[0]).toMatchObject({ table: 'C_WORK_TASK', scope: 'WO_NO:3188', after: 0 });
  });

  it('continues from the cursor on the next pull', async () => {
    const s = await setup();
    db = s.db;
    s.transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188 } }]);
    await s.pull.pull('c_work_task', { wo_no: 3188 });
    const cursor = await s.cursors.get('c_work_task', { wo_no: 3188 });

    await s.pull.pull('c_work_task', { wo_no: 3188 });
    expect(s.transport.pulls[1]?.after).toBe(cursor);
  });

  it('rewinds by the window for a tick-driven pull', async () => {
    const s = await setup();
    db = s.db;
    await s.cursors.set('c_work_task', { wo_no: 3188 }, 5000);
    await s.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(s.transport.pulls[0]?.after).toBe(4000);
  });

  it('never rewinds below zero', async () => {
    const s = await setup();
    db = s.db;
    await s.cursors.set('c_work_task', { wo_no: 3188 }, 10);
    await s.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(s.transport.pulls[0]?.after).toBe(0);
  });

  it('reads the scope whole for a manual refresh', async () => {
    const s = await setup();
    db = s.db;
    await s.cursors.set('c_work_task', { wo_no: 3188 }, 5000);
    await s.pull.pull('c_work_task', { wo_no: 3188 }, { from: 0 });
    expect(s.transport.pulls[0]?.after).toBe(0);
  });

  it('tracks the scopes the app has open', async () => {
    const s = await setup();
    db = s.db;
    const close = s.pull.registerScope('c_work_task', { wo_no: 3188 });
    s.pull.registerScope('c_work_task', { wo_no: 4000 });
    expect(s.pull.openScopes('c_work_task')).toHaveLength(2);
    close();
    expect(s.pull.openScopes('c_work_task')).toEqual([{ wo_no: 4000 }]);
  });

  it('stops after maxPages so a runaway server cannot loop forever', async () => {
    const s = await setup(1);
    db = s.db;
    s.transport.seed('C_WORK_TASK', [
      { id: 'A', data: { WO_NO: 3188 } }, { id: 'B', data: { WO_NO: 3188 } }, { id: 'C', data: { WO_NO: 3188 } },
    ]);
    const report = await s.pull.pull('c_work_task', { wo_no: 3188 }, { maxPages: 2 });
    expect(report.pages).toBe(2);
    expect(report.rows).toBe(2);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/sync/pull-service.test.ts`
Expected: FAIL — `Failed to resolve import "./pull-service"`.

- [ ] **Step 3: Write `src/sync/pull-service.ts`**

```ts
import { formatScope, scopeKey } from '../schema/scopes';
import type { ScopeValues } from '../types';
import type { CursorStore } from './cursor-store';
import type { PullApplier } from './pull-applier';
import type { SyncTransport } from './transport';
import { DEFAULT_PAGE_LIMIT, PULL_WINDOW, toWireTable } from './wire';

/** Where a pull starts: at the stored cursor, a window behind it (tick-driven), or at zero (manual refresh). */
export interface PullOptions {
  from?: 'cursor' | 'window' | 0;
  limit?: number;
  /** Safety valve against a server that always says `hasMore`. Default 100. */
  maxPages?: number;
}

export interface PullReport {
  rows: number;
  pages: number;
  cursor: number;
}

/**
 * Fetches pages for one `(table, scope)` and hands them to the applier. A pull
 * the client makes because a tick said something changed starts a window behind
 * its cursor (`max(0, cursor − 1000)`), because `SYNC_SEQ` is assigned in draw
 * order and not in commit order, so a row can commit behind a cursor that has
 * already moved past it. A manual refresh reads the scope whole from zero.
 * Re-seeing a row costs nothing: every apply is an idempotent upsert by id.
 */
export class PullService {
  private readonly open = new Map<string, { table: string; scope?: ScopeValues; count: number }>();

  constructor(
    private readonly transport: SyncTransport,
    private readonly applier: PullApplier,
    private readonly cursors: CursorStore,
    private readonly options: { window?: number; pageLimit?: number } = {},
  ) {}

  async pull(table: string, scope?: ScopeValues, options: PullOptions = {}): Promise<PullReport> {
    const from = options.from ?? 'cursor';
    const cursor = await this.cursors.get(table, scope);
    const window = this.options.window ?? PULL_WINDOW;
    let after = from === 0 ? 0 : from === 'window' ? Math.max(0, cursor - window) : cursor;

    const limit = options.limit ?? this.options.pageLimit ?? DEFAULT_PAGE_LIMIT;
    const maxPages = options.maxPages ?? 100;

    let rows = 0;
    let pages = 0;
    for (;;) {
      const wireScope = formatScope(scope);
      const page = await this.transport.pullRows({
        table: toWireTable(table),
        ...(wireScope ? { scope: wireScope } : {}),
        after,
        limit,
      });
      pages++;
      rows += page.rows.length;
      await this.applier.applyPage(table, page, { ...(scope ? { scope } : {}), advanceCursor: true });
      after = page.next;
      if (!page.hasMore || pages >= maxPages) break;
    }

    return { rows, pages, cursor: await this.cursors.get(table, scope) };
  }

  /** Tells the service that a view is showing this scope, so tick-driven pulls know what to refresh. Returns the deregistration function. */
  registerScope(table: string, scope?: ScopeValues): () => void {
    const key = scopeKey(table, scope);
    const existing = this.open.get(key);
    if (existing) existing.count++;
    else this.open.set(key, { table, ...(scope ? { scope } : {}), count: 1 });
    return () => {
      const entry = this.open.get(key);
      if (!entry) return;
      entry.count--;
      if (entry.count <= 0) this.open.delete(key);
    };
  }

  openScopes(table: string): Array<ScopeValues | undefined> {
    return [...this.open.values()].filter((entry) => entry.table === table).map((entry) => entry.scope);
  }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/sync/pull-service.test.ts`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
feat(sync): pull service with paging, the window rule and open scopes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 26: The push service — debounce, batching and idempotent batch ids

**Files:**
- Create: `packages/core/src/sync/push-service.ts`
- Test: `packages/core/src/sync/push-batching.test.ts`

**Interfaces:**
- Consumes: `SyncTransport`, `Outbox`, `PullApplier`, `Database`, `newBatchId`, `MAX_BATCH_CHANGES`, `toWireTable`, `toWireColumn`, `decodeScalar`.
- Produces:
  - `interface SyncStatus { online: boolean; sending: boolean; attempt: number; nextRetryAt: number | null; lastError: string | null }`
  - `interface PushOutcome { applied: number; noop: number; rejected: number; batches: number }`
  - `interface PushServiceOptions { deviceId: string; debounceMs?: number; maxChangesPerBatch?: number; backoffMs?: number[]; isTerminalError?: (error: unknown) => boolean }`
  - `class PushService { constructor(db: Database, transport: SyncTransport, outbox: Outbox, applier: PullApplier, options: PushServiceOptions); schedule(): void; pushNow(): Promise<PushOutcome>; notifyOnline(): void; status(): SyncStatus; onStatusChange(listener: (status: SyncStatus) => void): () => void; onRejected(listener: (entry: OutboxEntry) => void): () => void; stop(): void }`

- [ ] **Step 1: Write the failing test**

`src/sync/push-batching.test.ts`:

```ts
import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { FakeTransport } from '../testing/fake-transport';
import { Outbox } from './outbox';
import { Drafts } from './drafts';
import { CursorStore } from './cursor-store';
import { PullApplier } from './pull-applier';
import { PushService } from './push-service';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup(options: { maxChangesPerBatch?: number } = {}) {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  const drafts = new Drafts(db, outbox, writer);
  const applier = new PullApplier(db, writer, outbox, drafts, new CursorStore(db));
  const transport = new FakeTransport();
  const push = new PushService(db, transport, outbox, applier, { deviceId: 'ipad-test', debounceMs: 2000, ...options });

  await db.transaction(async (tx) => {
    for (const id of ['A', 'B']) {
      await writer.upsert(tx, 'c_work_task', { system_id: id, wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', sync_seq: 1, system_removed: 0 });
    }
  });
  transport.seed('C_WORK_TASK', [
    { id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } },
    { id: 'B', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } },
  ]);
  return { db, outbox, transport, push };
}

describe('PushService batching', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('sends the wire shapes the API expects', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    await s.push.pushNow();

    const batch = s.transport.pushes[0];
    expect(batch?.deviceId).toBe('ipad-test');
    expect(batch?.batchId.length).toBeLessThanOrEqual(36);
    expect(batch?.changes[0]).toMatchObject({ table: 'C_WORK_TASK', id: 'A', column: 'C_QTY_INSTALLED', old: 1, new: 10 });
    expect(typeof batch?.changes[0]?.changedAt).toBe('string');
  });

  it('keeps a change group whole and in recorded order', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'WORKSTARTED', c_qty_installed: 10 } });
    await s.push.pushNow();
    const columns = s.transport.pushes[0]?.changes.map((c) => c.column);
    expect(columns).toEqual(['ROWSTATE', 'C_QTY_INSTALLED']);
  });

  it('never splits a group across batches at the cap', async () => {
    const s = await setup({ maxChangesPerBatch: 3 });
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' } });
    await s.outbox.record({ table: 'c_work_task', systemId: 'B', changes: { c_qty_installed: 20, rowstate: 'WORKSTARTED' } });

    await s.push.pushNow();

    expect(s.transport.pushes).toHaveLength(2);
    expect(s.transport.pushes[0]?.changes.map((c) => c.id)).toEqual(['A', 'A']);
    expect(s.transport.pushes[1]?.changes.map((c) => c.id)).toEqual(['B', 'B']);
  });

  it('does nothing when there is nothing pending', async () => {
    const s = await setup();
    db = s.db;
    expect(await s.push.pushNow()).toMatchObject({ batches: 0 });
    expect(s.transport.pushes).toHaveLength(0);
  });

  it('debounces scheduled pushes into one', async () => {
    vi.useFakeTimers();
    try {
      const s = await setup();
      db = s.db;
      await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
      s.push.schedule();
      s.push.schedule();
      s.push.schedule();
      await vi.advanceTimersByTimeAsync(1999);
      expect(s.transport.pushes).toHaveLength(0);
      await vi.advanceTimersByTimeAsync(2);
      expect(s.transport.pushes).toHaveLength(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('reuses the batch id when a network error made the outcome unknown', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    s.transport.failNextPush();

    await s.push.pushNow();
    expect((await s.outbox.pending()).map((e) => e.status)).toEqual(['pending']);

    await s.push.pushNow();
    expect(s.transport.pushes).toHaveLength(2);
    expect(s.transport.pushes[0]?.batchId).toBe(s.transport.pushes[1]?.batchId);
  });

  it('only sends pending entries, never ones already sending', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'other-batch');
    expect(await s.push.pushNow()).toMatchObject({ batches: 0 });
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/sync/push-batching.test.ts`
Expected: FAIL — `Failed to resolve import "./push-service"`.

- [ ] **Step 3: Write `src/sync/push-service.ts`**

```ts
import type { Database } from '../db/database';
import type { OutboxEntry } from './outbox';
import type { Outbox } from './outbox';
import type { PullApplier } from './pull-applier';
import type { SyncTransport } from './transport';
import { MAX_BATCH_CHANGES, newBatchId, toWireColumn, toWireTable, type PushBatch, type PushChange, type RowDoc } from './wire';

/** What the app shows in the header: are we online, is a push in flight, and when does the next retry happen. */
export interface SyncStatus {
  online: boolean;
  sending: boolean;
  attempt: number;
  nextRetryAt: number | null;
  lastError: string | null;
}

export interface PushOutcome {
  applied: number;
  noop: number;
  rejected: number;
  batches: number;
}

export interface PushServiceOptions {
  deviceId: string;
  /** Default 2000 ms. */
  debounceMs?: number;
  /** Default 500, the server's cap. */
  maxChangesPerBatch?: number;
  /** Default [5000, 30000, 120000]; the last value repeats until the app reports it is online again. */
  backoffMs?: number[];
  /** Decides whether a thrown transport error is terminal (a 4xx) rather than a network blip. Default: everything is retryable. */
  isTerminalError?: (error: unknown) => boolean;
}

interface PreparedBatch {
  batchId: string;
  entries: OutboxEntry[];
}

/**
 * Sends recorded changes and files the answers. It debounces (2 s by default),
 * builds batches that never split a change group, marks entries `sending` under
 * one batch id, and applies the answer through the pull applier with the
 * seq-monotonic guard — a push answer is a receipt of what that batch did, not a
 * read of the current row. A network error returns the entries to `pending` and
 * retries the SAME batch id, which the server answers idempotently, with backoff
 * 5 s / 30 s / 2 min until the app reports it is online again.
 */
export class PushService {
  private timer: ReturnType<typeof setTimeout> | undefined;
  private inFlight: Promise<PushOutcome> | undefined;
  private retryBatch: PreparedBatch | undefined;
  private state: SyncStatus = { online: true, sending: false, attempt: 0, nextRetryAt: null, lastError: null };
  private readonly statusListeners = new Set<(status: SyncStatus) => void>();
  private readonly rejectedListeners = new Set<(entry: OutboxEntry) => void>();

  constructor(
    private readonly db: Database,
    private readonly transport: SyncTransport,
    private readonly outbox: Outbox,
    private readonly applier: PullApplier,
    private readonly options: PushServiceOptions,
  ) {}

  /** Asks for a push after the debounce window. Calling it again inside the window does not add a push. */
  schedule(): void {
    if (this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = undefined;
      void this.pushNow().catch((error) => console.error('[declarative-sqlite] push failed', error));
    }, this.options.debounceMs ?? 2000);
  }

  /** Pushes everything pending now, in batches, and returns the totals. Concurrent callers share one run. */
  async pushNow(): Promise<PushOutcome> {
    if (this.inFlight) return this.inFlight;
    this.inFlight = this.run().finally(() => {
      this.inFlight = undefined;
    });
    return this.inFlight;
  }

  private async run(): Promise<PushOutcome> {
    const outcome: PushOutcome = { applied: 0, noop: 0, rejected: 0, batches: 0 };
    this.setStatus({ sending: true });
    try {
      for (;;) {
        const batch = this.retryBatch ?? (await this.nextBatch());
        if (!batch) break;
        const sent = await this.sendBatch(batch);
        outcome.batches++;
        outcome.applied += sent.applied;
        outcome.noop += sent.noop;
        outcome.rejected += sent.rejected;
        if (!sent.delivered) break;
      }
    } finally {
      this.setStatus({ sending: false });
    }
    return outcome;
  }

  private async nextBatch(): Promise<PreparedBatch | undefined> {
    const pending = await this.outbox.pending();
    if (pending.length === 0) return undefined;

    const cap = Math.min(this.options.maxChangesPerBatch ?? MAX_BATCH_CHANGES, MAX_BATCH_CHANGES);
    const groups = new Map<string, OutboxEntry[]>();
    for (const entry of pending) {
      const group = groups.get(entry.groupId);
      if (group) group.push(entry);
      else groups.set(entry.groupId, [entry]);
    }

    const entries: OutboxEntry[] = [];
    for (const group of groups.values()) {
      if (entries.length > 0 && entries.length + group.length > cap) break;
      entries.push(...group);
      if (entries.length >= cap) break;
    }

    const batchId = newBatchId();
    await this.outbox.markSending(
      entries.map((e) => e.id),
      batchId,
    );
    return { batchId, entries };
  }

  private async sendBatch(batch: PreparedBatch): Promise<{ delivered: boolean; applied: number; noop: number; rejected: number }> {
    const changes: PushChange[] = batch.entries.map((entry) => ({
      table: toWireTable(entry.tableName),
      id: entry.systemId,
      column: toWireColumn(entry.columnName),
      old: entry.oldValue,
      new: entry.newValue,
      changedAt: entry.changedAt,
    }));
    const payload: PushBatch = { batchId: batch.batchId, deviceId: this.options.deviceId, changes };

    let answer;
    try {
      answer = await this.transport.push(payload);
    } catch (error) {
      await this.handleFailure(batch, error);
      return { delivered: false, applied: 0, noop: 0, rejected: 0 };
    }

    this.retryBatch = undefined;
    this.setStatus({ attempt: 0, nextRetryAt: null, lastError: null, online: true });

    await this.outbox.applyResults(
      batch.batchId,
      answer.results,
      batch.entries.map((e) => e.id),
    );
    await this.applyAnswerRows(batch, answer.rows);

    const counts = { applied: 0, noop: 0, rejected: 0 };
    for (const result of answer.results) counts[result.result]++;
    if (counts.rejected > 0) {
      for (const entry of await this.outbox.entries({ status: 'rejected' })) {
        for (const listener of [...this.rejectedListeners]) listener(entry);
      }
    }
    return { delivered: true, ...counts };
  }

  /** Applies the answer rows table by table, with the seq guard, and without moving any cursor. Rows the batch did not mention are ignored. */
  private async applyAnswerRows(batch: PreparedBatch, rows: RowDoc[]): Promise<void> {
    if (rows.length === 0) return;
    const tableOf = new Map<string, string>();
    for (const entry of batch.entries) tableOf.set(entry.systemId, entry.tableName);

    const byTable = new Map<string, RowDoc[]>();
    for (const row of rows) {
      const table = tableOf.get(row.id);
      if (!table) continue;
      const bucket = byTable.get(table);
      if (bucket) bucket.push(row);
      else byTable.set(table, [row]);
    }
    for (const [table, tableRows] of byTable) {
      await this.applier.applyRows(table, tableRows, { seqGuard: true, advanceCursor: false });
    }
  }

  private async handleFailure(batch: PreparedBatch, error: unknown): Promise<void> {
    const message = error instanceof Error ? error.message : String(error);
    await this.outbox.resetSending(batch.batchId);

    if (this.options.isTerminalError?.(error)) {
      this.retryBatch = undefined;
      await this.outbox.applyResults(
        batch.batchId,
        batch.entries.map((_, index) => ({ index, result: 'rejected' as const, error: message })),
        batch.entries.map((e) => e.id),
      );
      this.setStatus({ lastError: message });
      return;
    }

    this.retryBatch = batch;
    const backoff = this.options.backoffMs ?? [5000, 30000, 120000];
    const attempt = this.state.attempt + 1;
    const delay = backoff[Math.min(attempt - 1, backoff.length - 1)] ?? 120000;
    this.setStatus({ attempt, online: false, lastError: message, nextRetryAt: Date.now() + delay });

    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = undefined;
      void this.pushNow().catch(() => undefined);
    }, delay);
  }

  /** The app reports connectivity came back: retry immediately instead of waiting out the backoff. */
  notifyOnline(): void {
    this.setStatus({ online: true, nextRetryAt: null });
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    void this.pushNow().catch(() => undefined);
  }

  status(): SyncStatus {
    return this.state;
  }

  onStatusChange(listener: (status: SyncStatus) => void): () => void {
    this.statusListeners.add(listener);
    return () => {
      this.statusListeners.delete(listener);
    };
  }

  onRejected(listener: (entry: OutboxEntry) => void): () => void {
    this.rejectedListeners.add(listener);
    return () => {
      this.rejectedListeners.delete(listener);
    };
  }

  /** Cancels any scheduled push. Called when the database closes. */
  stop(): void {
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
  }

  private setStatus(patch: Partial<SyncStatus>): void {
    this.state = { ...this.state, ...patch };
    for (const listener of [...this.statusListeners]) listener(this.state);
  }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/sync/push-batching.test.ts`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
feat(sync): push service with debounce, whole groups and idempotent batches

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 27: The push answer — receipts, the seq guard, rejections and backoff

Task 26 built the send path; this task pins what happens to the answer, which is where the live findings FN-6/FN-8 live: the rows in a push answer are the state inside that batch's own transaction, so they go through the applier's seq guard and never move a cursor.

**Files:**
- Test: `packages/core/src/sync/push-answer.test.ts`
- Modify: `packages/core/src/sync/push-service.ts` (only if a test exposes a gap)

**Interfaces:**
- Consumes: everything from Task 26.
- Produces: no new API.

- [ ] **Step 1: Write the failing test**

`src/sync/push-answer.test.ts`:

```ts
import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { FakeTransport } from '../testing/fake-transport';
import { Outbox } from './outbox';
import { Drafts } from './drafts';
import { CursorStore } from './cursor-store';
import { PullApplier } from './pull-applier';
import { PushService } from './push-service';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup(options: Partial<{ isTerminalError: (e: unknown) => boolean }> = {}) {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  const drafts = new Drafts(db, outbox, writer);
  const cursors = new CursorStore(db);
  const applier = new PullApplier(db, writer, outbox, drafts, cursors);
  const transport = new FakeTransport();
  const push = new PushService(db, transport, outbox, applier, { deviceId: 'ipad', debounceMs: 1, ...options });

  await db.transaction(async (tx) => {
    await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', sync_seq: 50, system_removed: 0 });
  });
  transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } }]);
  return { db, outbox, transport, push, cursors };
}

describe('PushService answers', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('marks applied entries and lets the returned row land', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });

    const outcome = await s.push.pushNow();

    expect(outcome).toMatchObject({ applied: 1, rejected: 0 });
    expect(s.outbox.pendingColumns('c_work_task', 'A').size).toBe(0);
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 10 });
  });

  it('skips an answer row whose seq is not above the local one', async () => {
    const s = await setup();
    db = s.db;
    await db.execute('UPDATE c_work_task SET sync_seq = 100000 WHERE system_id = ?', ['A']);
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });

    await s.push.pushNow();

    // The local row keeps the value the outbox wrote; the tick-driven pull brings the final state.
    expect(await db.queryOne('SELECT c_qty_installed, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 10, sync_seq: 100000,
    });
  });

  it('never moves a cursor from a push answer', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    await s.push.pushNow();
    expect(await s.cursors.get('c_work_task', { wo_no: 3188 })).toBe(0);
  });

  it('keeps a rejected entry visible with its message and reports it', async () => {
    const s = await setup();
    db = s.db;
    s.transport.reject('C_WORK_TASK', 'ROWSTATE', 'CBADSTATE: this rowstate cannot be pushed');
    const rejected = vi.fn();
    s.push.onRejected(rejected);

    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'CANCELLED' } });
    const outcome = await s.push.pushNow();

    expect(outcome.rejected).toBe(1);
    expect(rejected).toHaveBeenCalled();
    const entries = await s.outbox.entries({ status: 'rejected' });
    expect(entries[0]?.errorText).toContain('CBADSTATE');
  });

  it('does not resend a rejected entry on the next push', async () => {
    const s = await setup();
    db = s.db;
    s.transport.reject('C_WORK_TASK', 'ROWSTATE', 'CBADSTATE: no');
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'CANCELLED' } });
    await s.push.pushNow();
    await s.push.pushNow();
    expect(s.transport.pushes).toHaveLength(1);
  });

  it('answers noop without changing anything', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 1 } });
    const outcome = await s.push.pushNow();
    expect(outcome).toMatchObject({ noop: 1 });
    expect((await s.outbox.entries())[0]?.status).toBe('noop');
  });

  it('backs off 5 s, 30 s, 2 min across repeated network failures', async () => {
    vi.useFakeTimers();
    try {
      const s = await setup();
      db = s.db;
      await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });

      s.transport.failNextPush();
      await s.push.pushNow();
      expect(s.push.status()).toMatchObject({ attempt: 1, online: false });
      const first = s.push.status().nextRetryAt ?? 0;

      s.transport.failNextPush();
      await vi.advanceTimersByTimeAsync(5001);
      expect(s.push.status().attempt).toBe(2);
      const second = s.push.status().nextRetryAt ?? 0;
      expect(second - first).toBeGreaterThanOrEqual(25000);

      await vi.advanceTimersByTimeAsync(30001);
      expect(s.push.status()).toMatchObject({ attempt: 0, online: true });
      expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 10 });
    } finally {
      vi.useRealTimers();
    }
  });

  it('retries immediately when the app says it is online again', async () => {
    vi.useFakeTimers();
    try {
      const s = await setup();
      db = s.db;
      await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
      s.transport.failNextPush();
      await s.push.pushNow();

      s.push.notifyOnline();
      await vi.advanceTimersByTimeAsync(1);
      expect(s.transport.pushes).toHaveLength(2);
    } finally {
      vi.useRealTimers();
    }
  });

  it('marks the batch rejected for a terminal error instead of looping', async () => {
    const s = await setup({ isTerminalError: () => true });
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    s.transport.failNextPush(new Error('HTTP 400 bad request'));

    await s.push.pushNow();

    const entries = await s.outbox.entries();
    expect(entries[0]).toMatchObject({ status: 'rejected' });
    expect(entries[0]?.errorText).toContain('400');
  });
});
```

- [ ] **Step 2: Run it**

Run: `npm test -- src/sync/push-answer.test.ts`
Expected: most pass on Task 26's implementation. Any failure is a real gap — fix `push-service.ts` until all nine pass. Do not relax an assertion: each one is a live finding or a spec rule.

- [ ] **Step 3: Run the whole suite and typecheck**

Run: `npm test && npm run typecheck`

- [ ] **Step 4: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
test(sync): push answers are receipts - seq guard, rejections, backoff

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 28: Tick coalescing and `createSyncRuntime`

**Files:**
- Create: `packages/core/src/sync/tick-coalescer.ts`
- Create: `packages/core/src/sync/runtime.ts`
- Test: `packages/core/src/sync/tick-coalescer.test.ts`
- Test: `packages/core/src/sync/runtime.test.ts`
- Modify: `packages/core/src/index.ts`

**Interfaces:**
- Consumes: `PullService`, `CursorStore`, `Database`, `Outbox`, `Overlay`, `Drafts`, `PullApplier`, `PushService`, `createServerWriteCapability`, `serverWriter`.
- Produces:
  - `interface Tick { table: string; seq: number; scopes?: Array<string | number> }`
  - `class TickCoalescer { constructor(pull: PullService, cursors: CursorStore, options?: { windowMs?: number }); notify(tick: Tick): void; flush(): Promise<void>; stop(): void }`
  - `interface SyncRuntimeOptions { db: Database; transport: SyncTransport; deviceId: string; debounceMs?: number; maxChangesPerBatch?: number; pullWindow?: number; pageLimit?: number; tickWindowMs?: number; clock?: () => Date; isTerminalError?: (error: unknown) => boolean }`
  - `interface SyncRuntime { outbox: Outbox; overlay: Overlay; drafts: Drafts; cursors: CursorStore; applier: PullApplier; pull: PullService; push: PushService; ticks: TickCoalescer; close(): void }`
  - `function createSyncRuntime(options: SyncRuntimeOptions): Promise<SyncRuntime>`

- [ ] **Step 1: Write the failing tests**

`src/sync/tick-coalescer.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest';
import { TickCoalescer } from './tick-coalescer';
import type { PullService } from './pull-service';
import type { CursorStore } from './cursor-store';

function fakes(openScopes: Array<Record<string, string | number> | undefined>, cursor = 0) {
  const pull = { pull: vi.fn().mockResolvedValue({ rows: 0, pages: 1, cursor: 0 }), openScopes: () => openScopes } as unknown as PullService;
  const cursors = { get: vi.fn().mockResolvedValue(cursor) } as unknown as CursorStore;
  return { pull, cursors };
}

describe('TickCoalescer', () => {
  it('collects ticks for the window and then pulls once per open scope', async () => {
    vi.useFakeTimers();
    try {
      const { pull, cursors } = fakes([{ wo_no: 3188 }, { wo_no: 4000 }]);
      const ticks = new TickCoalescer(pull, cursors, { windowMs: 1500 });
      ticks.notify({ table: 'c_work_task', seq: 10 });
      ticks.notify({ table: 'c_work_task', seq: 11 });
      await vi.advanceTimersByTimeAsync(1400);
      expect(pull.pull).not.toHaveBeenCalled();

      await vi.advanceTimersByTimeAsync(200);
      expect(pull.pull).toHaveBeenCalledTimes(2);
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 3188 }, { from: 'window' });
    } finally {
      vi.useRealTimers();
    }
  });

  it('skips a scope whose cursor is already at or past the tick seq', async () => {
    vi.useFakeTimers();
    try {
      const { pull, cursors } = fakes([{ wo_no: 3188 }], 50);
      const ticks = new TickCoalescer(pull, cursors, { windowMs: 10 });
      ticks.notify({ table: 'c_work_task', seq: 50 });
      await vi.advanceTimersByTimeAsync(20);
      expect(pull.pull).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });

  it('pulls only the scopes the tick lists when it lists any', async () => {
    vi.useFakeTimers();
    try {
      const { pull, cursors } = fakes([{ wo_no: 3188 }, { wo_no: 4000 }]);
      const ticks = new TickCoalescer(pull, cursors, { windowMs: 10 });
      ticks.notify({ table: 'c_work_task', seq: 10, scopes: [4000] });
      await vi.advanceTimersByTimeAsync(20);
      expect(pull.pull).toHaveBeenCalledTimes(1);
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 4000 }, { from: 'window' });
    } finally {
      vi.useRealTimers();
    }
  });

  it('flush() pulls immediately without waiting for the window', async () => {
    const { pull, cursors } = fakes([{ wo_no: 3188 }]);
    const ticks = new TickCoalescer(pull, cursors, { windowMs: 5000 });
    ticks.notify({ table: 'c_work_task', seq: 10 });
    await ticks.flush();
    expect(pull.pull).toHaveBeenCalledTimes(1);
  });
});
```

`src/sync/runtime.test.ts`:

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { FakeTransport } from '../testing/fake-transport';
import { createSyncRuntime } from './runtime';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('createSyncRuntime', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('wires overlay and draft holds into every live query', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }]);
    const sync = await createSyncRuntime({ db, transport, deviceId: 'ipad' });

    await sync.pull.pull('c_work_task', { wo_no: 3188 });

    const query = db.live<{ system_id: string; c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ?',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const seen: Array<Array<{ c_qty_installed: number }>> = [];
    query.subscribe((rows) => seen.push(rows));
    await settle();
    expect(seen.at(-1)?.[0]?.c_qty_installed).toBe(1);

    await sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    await settle();
    expect(seen.at(-1)?.[0]?.c_qty_installed).toBe(10);

    sync.drafts.begin('c_work_task', 'A', 'c_qty_installed', 10);
    sync.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);
    await query.refresh();
    expect(seen.at(-1)?.[0]?.c_qty_installed).toBe(12);

    query.close();
    sync.close();
  });

  it('loads the outbox index on creation so a restart keeps overlaying', async () => {
    const adapter = new MemoryAdapter();
    db = await Database.open({ schema: testSchema(), adapter });
    const transport = new FakeTransport();
    const first = await createSyncRuntime({ db, transport, deviceId: 'ipad' });
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }]);
    await first.pull.pull('c_work_task', { wo_no: 3188 });
    await first.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    first.close();

    const second = await createSyncRuntime({ db, transport, deviceId: 'ipad' });
    expect(second.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 10 });
    second.close();
  });
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `npm test -- src/sync/tick-coalescer.test.ts src/sync/runtime.test.ts`
Expected: FAIL — unresolved imports.

- [ ] **Step 3: Write `src/sync/tick-coalescer.ts`**

```ts
import type { ScopeValues } from '../types';
import type { CursorStore } from './cursor-store';
import type { PullService } from './pull-service';

/** One `TableChanged` notification: the table, the highest `SYNC_SEQ` the tick service has seen, and optionally the scope values that changed. */
export interface Tick {
  table: string;
  seq: number;
  scopes?: Array<string | number>;
}

/**
 * Turns a stream of notifications into as few pulls as possible. Ticks are
 * collected for about 1.5 seconds and then resolved together: for each table,
 * every scope the app has open is pulled once, skipping scopes whose cursor is
 * already at or past the tick's seq, and — when the tick lists the scopes that
 * changed — skipping the ones it does not mention. That is what stops a device
 * on another work order from pulling an empty page every time anyone saves.
 */
export class TickCoalescer {
  private pendingTicks = new Map<string, Tick>();
  private timer: ReturnType<typeof setTimeout> | undefined;

  constructor(
    private readonly pull: PullService,
    private readonly cursors: CursorStore,
    private readonly options: { windowMs?: number } = {},
  ) {}

  notify(tick: Tick): void {
    const existing = this.pendingTicks.get(tick.table);
    if (!existing || tick.seq > existing.seq) {
      this.pendingTicks.set(tick.table, {
        ...tick,
        ...(existing?.scopes && tick.scopes ? { scopes: [...new Set([...existing.scopes, ...tick.scopes])] } : {}),
      });
    } else if (existing.scopes && tick.scopes) {
      existing.scopes = [...new Set([...existing.scopes, ...tick.scopes])];
    }

    if (this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = undefined;
      void this.flush().catch((error) => console.error('[declarative-sqlite] tick pull failed', error));
    }, this.options.windowMs ?? 1500);
  }

  /** Resolves the collected ticks now. The Sync button calls this so the user does not wait out the window. */
  async flush(): Promise<void> {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    const ticks = [...this.pendingTicks.values()];
    this.pendingTicks.clear();

    for (const tick of ticks) {
      for (const scope of this.pull.openScopes(tick.table)) {
        if (!this.tickCoversScope(tick, scope)) continue;
        const cursor = await this.cursors.get(tick.table, scope);
        if (cursor >= tick.seq) continue;
        await this.pull.pull(tick.table, scope, { from: 'window' });
      }
    }
  }

  stop(): void {
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
    this.pendingTicks.clear();
  }

  private tickCoversScope(tick: Tick, scope?: ScopeValues): boolean {
    if (!tick.scopes || tick.scopes.length === 0) return true;
    if (!scope) return true;
    const values = Object.values(scope).map(String);
    return tick.scopes.some((value) => values.includes(String(value)));
  }
}
```

- [ ] **Step 4: Write `src/sync/runtime.ts`**

```ts
import type { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import type { Row } from '../types';
import { CursorStore } from './cursor-store';
import { Drafts } from './drafts';
import { Outbox } from './outbox';
import { Overlay } from './overlay';
import { PullApplier } from './pull-applier';
import { PullService } from './pull-service';
import { PushService } from './push-service';
import { TickCoalescer } from './tick-coalescer';
import type { SyncTransport } from './transport';

export interface SyncRuntimeOptions {
  db: Database;
  transport: SyncTransport;
  /** Logged with every change on the server; the app's installation id. */
  deviceId: string;
  debounceMs?: number;
  maxChangesPerBatch?: number;
  pullWindow?: number;
  pageLimit?: number;
  tickWindowMs?: number;
  clock?: () => Date;
  isTerminalError?: (error: unknown) => boolean;
}

/** Everything the sync layer exposes for one database. Create it once, right after `Database.open`. */
export interface SyncRuntime {
  outbox: Outbox;
  overlay: Overlay;
  drafts: Drafts;
  cursors: CursorStore;
  applier: PullApplier;
  pull: PullService;
  push: PushService;
  ticks: TickCoalescer;
  close(): void;
}

/**
 * Builds the sync layer on top of an open database and wires it in: it mints the
 * server-write capability (so synced tables become writable to the applier and
 * the outbox, and to nothing else), loads the outbox's pending index, and
 * installs the row transform that puts the overlay and the draft holds in front
 * of every live query. Call `close()` when the database closes.
 */
export async function createSyncRuntime(options: SyncRuntimeOptions): Promise<SyncRuntime> {
  const { db, transport } = options;
  const writer = serverWriter(db, createServerWriteCapability());

  const outbox = new Outbox(db, writer, options.clock ? { clock: options.clock } : {});
  await outbox.load();

  const overlay = new Overlay(db, outbox);
  const drafts = new Drafts(db, outbox, writer);
  const cursors = new CursorStore(db, options.clock ? { clock: options.clock } : {});
  const applier = new PullApplier(db, writer, outbox, drafts, cursors);

  const pull = new PullService(transport, applier, cursors, {
    ...(options.pullWindow !== undefined ? { window: options.pullWindow } : {}),
    ...(options.pageLimit !== undefined ? { pageLimit: options.pageLimit } : {}),
  });
  const push = new PushService(db, transport, outbox, applier, {
    deviceId: options.deviceId,
    ...(options.debounceMs !== undefined ? { debounceMs: options.debounceMs } : {}),
    ...(options.maxChangesPerBatch !== undefined ? { maxChangesPerBatch: options.maxChangesPerBatch } : {}),
    ...(options.isTerminalError ? { isTerminalError: options.isTerminalError } : {}),
  });
  const ticks = new TickCoalescer(pull, cursors, options.tickWindowMs !== undefined ? { windowMs: options.tickWindowMs } : {});

  const transform = (table: string, rows: Row[]): Row[] => drafts.apply(table, overlay.apply(table, rows));
  db.setRowTransform(transform);

  const unsubscribeOutbox = outbox.subscribe(() => push.schedule());
  const unsubscribeDrafts = drafts.subscribe(() => undefined);

  return {
    outbox, overlay, drafts, cursors, applier, pull, push, ticks,
    close() {
      unsubscribeOutbox();
      unsubscribeDrafts();
      push.stop();
      ticks.stop();
      db.setRowTransform(undefined);
    },
  };
}
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `npm test -- src/sync`
Expected: PASS across the sync suite (6 tick + runtime tests added).

- [ ] **Step 6: Export the sync layer**

Append to `src/index.ts`:

```ts
export { Outbox, OutboxError } from './sync/outbox';
export { Overlay } from './sync/overlay';
export { Drafts } from './sync/drafts';
export { CursorStore } from './sync/cursor-store';
export { PullApplier } from './sync/pull-applier';
export { PullService } from './sync/pull-service';
export { PushService } from './sync/push-service';
export { TickCoalescer } from './sync/tick-coalescer';
export { createSyncRuntime } from './sync/runtime';
export type { OutboxEntry, OutboxStatus, RecordRequest } from './sync/outbox';
export type { DraftState } from './sync/drafts';
export type { CursorRow } from './sync/cursor-store';
export type { ApplyOptions, ApplyReport } from './sync/pull-applier';
export type { PullOptions, PullReport } from './sync/pull-service';
export type { PushOutcome, PushServiceOptions, SyncStatus } from './sync/push-service';
export type { Tick } from './sync/tick-coalescer';
export type { SyncRuntime, SyncRuntimeOptions } from './sync/runtime';
```

- [ ] **Step 7: Commit**

```bash
git add src/sync src/index.ts
git commit -m "$(cat <<'MSG'
feat(sync): tick coalescing and createSyncRuntime wiring

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 29: The race scenarios as named tests

Spec §9 lists the races this design exists to survive. Each one becomes a named test against the whole stack in memory: a real SQLite, the real runtime, the scripted server.

**Files:**
- Create: `packages/core/src/sync/scenarios.test.ts`

**Interfaces:**
- Consumes: `Database`, `createSyncRuntime`, `FakeTransport`, `SchemaBuilder`.
- Produces: no new API.

- [ ] **Step 1: Write the scenario suite**

`src/sync/scenarios.test.ts`:

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { FakeTransport } from '../testing/fake-transport';
import { createSyncRuntime, type SyncRuntime } from './runtime';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
    t.text('internal_remark');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function scene() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const transport = new FakeTransport();
  transport.seed('C_WORK_TASK', [
    { id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED', INTERNAL_REMARK: null } },
    { id: 'B', data: { WO_NO: 3188, C_QTY_INSTALLED: 2, ROWSTATE: 'RELEASED', INTERNAL_REMARK: null } },
  ]);
  const sync = await createSyncRuntime({ db, transport, deviceId: 'ipad-test', debounceMs: 10 });
  await sync.pull.pull('c_work_task', { wo_no: 3188 });
  return { db, transport, sync };
}

describe('sync scenarios', () => {
  let db: Database | undefined;
  let sync: SyncRuntime | undefined;

  afterEach(async () => {
    sync?.close();
    await db?.close();
    db = undefined;
    sync = undefined;
  });

  it('pull during draft: the typed value stays, siblings update', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    s.sync.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.sync.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);

    s.transport.serverEdit('C_WORK_TASK', 'A', { C_QTY_INSTALLED: 7, ROWSTATE: 'WORKSTARTED' });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });

    expect(s.sync.drafts.get('c_work_task', 'A', 'c_qty_installed')).toBe(12);
    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 1, rowstate: 'WORKSTARTED',
    });
  });

  it('pull between record() and the push answer: the pending column is untouched', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    await s.sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    s.transport.serverEdit('C_WORK_TASK', 'A', { C_QTY_INSTALLED: 7, ROWSTATE: 'WORKSTARTED' });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });

    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 10, rowstate: 'WORKSTARTED',
    });

    await s.sync.push.pushNow();
    expect(s.sync.outbox.pendingColumns('c_work_task', 'A').size).toBe(0);
  });

  it('rejected change: the entry stays visible and the local value reverts on the next pull', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;
    s.transport.reject('C_WORK_TASK', 'ROWSTATE', 'CBADSTATE: not a state this LU can act on');

    await s.sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'CANCELLED' } });
    await s.sync.push.pushNow();

    const rejected = await s.sync.outbox.entries({ status: 'rejected' });
    expect(rejected).toHaveLength(1);

    s.transport.serverEdit('C_WORK_TASK', 'A', { ROWSTATE: 'RELEASED' });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(await db.queryOne('SELECT rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ rowstate: 'RELEASED' });
  });

  it('tombstone during edit: the row survives until the draft ends, then the push says CNOROW', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    s.sync.drafts.begin('c_work_task', 'A', 'internal_remark', null);
    s.sync.drafts.set('c_work_task', 'A', 'internal_remark', 'sjekket');

    s.transport.tombstone('C_WORK_TASK', 'A');
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeDefined();

    await s.sync.drafts.end('c_work_task', 'A', 'internal_remark');
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeUndefined();

    await s.sync.push.pushNow();
    const entries = await s.sync.outbox.entries({ status: 'rejected' });
    expect(entries[0]?.errorText).toContain('CNOROW');
  });

  it('two devices interleaved: the later arrival stands and both devices converge', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    await s.sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    s.transport.serverEdit('C_WORK_TASK', 'A', { C_QTY_INSTALLED: 99 }); // the other device got there first
    await s.sync.push.pushNow();                                        // ours arrives later and wins

    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 10 });
  });

  it('out-of-order arrival: the window brings back a row that committed behind the cursor', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    await s.sync.cursors.set('c_work_task', { wo_no: 3188 }, 900);
    s.transport.serverEdit('C_WORK_TASK', 'B', { C_QTY_INSTALLED: 42 });

    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['B'])).toEqual({ c_qty_installed: 42 });
  });

  it('a 200-row page commits once', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;
    s.transport.seed('C_WORK_TASK', Array.from({ length: 200 }, (_, i) => ({ id: `n-${i}`, data: { WO_NO: 3188, C_QTY_INSTALLED: i } })));

    let events = 0;
    db.invalidations.subscribe(() => {
      events++;
    });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { limit: 500 });

    expect(events).toBe(2); // one for the page, one for the cursor row
    expect(await db.query('SELECT system_id FROM c_work_task')).toHaveLength(202);
  });

  it('a live query is not re-run for a foreign scope', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;
    s.transport.seed('C_WORK_TASK', [{ id: 'Z', data: { WO_NO: 4000, C_QTY_INSTALLED: 1 } }]);

    const query = db.live({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    let emissions = 0;
    query.subscribe(() => {
      emissions++;
    });
    await settle();
    const before = emissions;

    await s.sync.pull.pull('c_work_task', { wo_no: 4000 });
    await settle();

    expect(emissions).toBe(before);
    query.close();
  });

  it('an identical result is not emitted', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    const query = db.live({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    let emissions = 0;
    query.subscribe(() => {
      emissions++;
    });
    await settle();
    const before = emissions;

    s.transport.serverEdit('C_WORK_TASK', 'A', { INTERNAL_REMARK: 'irrelevant to this query' });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    await settle();

    expect(emissions).toBe(before);
    query.close();
  });
});
```

- [ ] **Step 2: Run the suite**

Run: `npm test -- src/sync/scenarios.test.ts`
Expected: 9 tests. Any failure is a real defect in the layer it exercises — fix the layer, not the scenario. The one assertion that may need adjusting is the invalidation count in "a 200-row page commits once": count the events the cursor write produces in your implementation and assert the exact number, never a range.

- [ ] **Step 3: Run everything**

Run: `npm test && npm run typecheck`

- [ ] **Step 4: Commit**

```bash
git add src/sync
git commit -m "$(cat <<'MSG'
test(sync): the spec's race scenarios as named end-to-end tests

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---
### Task 30: The WASM base adapter and the OPFS backend

Everything so far runs on `MemoryAdapter`. The persistent backends share its SQL surface and differ only in how the database is opened. The official build ships **no IndexedDB VFS** — v2's "IndexedDB backend" silently fell back to an in-memory database, which is why a browser without OPFS quietly lost data on reload. v3 is honest about it: OPFS uses the SAH-pool VFS, and the IndexedDB backend (Task 31) is an in-memory database with a persisted image.

**Files:**
- Create: `packages/core/src/adapters/wasm.ts`
- Create: `packages/core/src/adapters/opfs-adapter.ts`
- Modify: `packages/core/src/adapters/memory-adapter.ts` (extract the shared base)
- Test: `packages/core/src/adapters/wasm.test.ts`

**Interfaces:**
- Consumes: `SQLiteAdapter`, `RunResult`, `SqlValue`, `loadSqlite3`.
- Produces:
  - `abstract class WasmAdapterBase implements SQLiteAdapter` — everything except `open()`; subclasses set `this.sqlite3` and `this.db`
  - `class OpfsAdapter extends WasmAdapterBase { constructor(name: string, options?: { wasmDir?: string; poolName?: string }); open(): Promise<void>; static isSupported(): boolean }`

- [ ] **Step 1: Write the failing test**

`src/adapters/wasm.test.ts` (what can be tested in Node: the base class behaves like the memory adapter, and `OpfsAdapter` refuses to open where OPFS does not exist instead of silently falling back):

```ts
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
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/adapters/wasm.test.ts`
Expected: FAIL — `Failed to resolve import "./wasm"`.

- [ ] **Step 3: Extract `src/adapters/wasm.ts`**

Move everything except `open()` out of `MemoryAdapter`:

```ts
import type { SqlValue } from '../types';
import type { RunResult, SQLiteAdapter } from './adapter';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Sqlite3Module = any;

/**
 * Everything the WASM adapters share: binding, stepping, reading rows and
 * exporting the image. A subclass only has to open a database handle and assign
 * `sqlite3` and `db`; how the bytes are stored is the only thing that differs
 * between memory, OPFS and the IndexedDB snapshot.
 */
export abstract class WasmAdapterBase implements SQLiteAdapter {
  protected sqlite3: Sqlite3Module | undefined;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  protected db: any;

  abstract open(): Promise<void>;

  async close(): Promise<void> {
    if (!this.db) return;
    this.db.close();
    this.db = undefined;
  }

  isOpen(): boolean {
    return this.db !== undefined;
  }

  async exec(sql: string): Promise<void> {
    this.ensureOpen();
    this.db.exec(sql);
  }

  async all<T>(sql: string, params: SqlValue[] = []): Promise<T[]> {
    this.ensureOpen();
    const stmt = this.db.prepare(sql);
    try {
      this.bind(stmt, params);
      const rows: T[] = [];
      while (stmt.step()) rows.push(stmt.get({}) as T);
      return rows;
    } finally {
      stmt.finalize();
    }
  }

  async get<T>(sql: string, params: SqlValue[] = []): Promise<T | undefined> {
    return (await this.all<T>(sql, params))[0];
  }

  async run(sql: string, params: SqlValue[] = []): Promise<RunResult> {
    this.ensureOpen();
    const stmt = this.db.prepare(sql);
    try {
      this.bind(stmt, params);
      stmt.step();
    } finally {
      stmt.finalize();
    }
    return { changes: this.db.changes(), lastInsertRowid: Number(this.sqlite3.capi.sqlite3_last_insert_rowid(this.db)) };
  }

  async export(): Promise<Uint8Array> {
    this.ensureOpen();
    return new Uint8Array(this.sqlite3.capi.sqlite3_js_db_export(this.db.pointer));
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  protected bind(stmt: any, params: SqlValue[]): void {
    for (let i = 0; i < params.length; i++) stmt.bind(i + 1, params[i] ?? null);
  }

  protected ensureOpen(): void {
    if (!this.db) throw new Error('Database is not open. Call open() first.');
  }
}
```

`memory-adapter.ts` keeps `loadSqlite3` and becomes:

```ts
export class MemoryAdapter extends WasmAdapterBase {
  constructor(private readonly options: { wasmDir?: string } = {}) {
    super();
  }

  override async open(): Promise<void> {
    if (this.db) return;
    this.sqlite3 = await loadSqlite3(this.options.wasmDir);
    this.db = new this.sqlite3.oo1.DB(':memory:');
  }
}
```

- [ ] **Step 4: Write `src/adapters/opfs-adapter.ts`**

```ts
import { loadSqlite3 } from './memory-adapter';
import { WasmAdapterBase } from './wasm';

/**
 * A database stored in the Origin Private File System through SQLite's
 * SAH-pool VFS. This is the backend to want: real file I/O, no image copying,
 * and it works on the main thread as well as in a worker without COOP/COEP
 * headers. It needs `createSyncAccessHandle`, which is Chrome/Edge 108+,
 * Firefox 111+ and Safari 17+; where that is missing, `open()` throws rather
 * than quietly producing a database that disappears on reload.
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
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `npm test -- src/adapters`
Expected: PASS — the memory adapter suite from Task 2 still passes unchanged, plus the three new assertions.

- [ ] **Step 6: Commit**

```bash
git add src/adapters
git commit -m "$(cat <<'MSG'
feat(adapters): shared WASM base and the OPFS SAH-pool backend

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 31: The IndexedDB snapshot backend and `openAdapter`

The official SQLite WASM build has no IndexedDB VFS. Where OPFS is unavailable the honest option is an in-memory database whose image is written to IndexedDB after writes settle and read back on open. It is slower for a large database and it loses at most the last debounce window on a crash — both are stated in the JSDoc so nobody discovers them in production.

**Files:**
- Create: `packages/core/src/adapters/indexeddb-adapter.ts`
- Create: `packages/core/src/adapters/open-adapter.ts`
- Test: `packages/core/src/adapters/open-adapter.test.ts`
- Modify: `packages/core/src/index.ts`

**Interfaces:**
- Consumes: `WasmAdapterBase`, `loadSqlite3`, `MemoryAdapter`, `OpfsAdapter`, `SQLiteAdapter`.
- Produces:
  - `class IndexedDbAdapter extends WasmAdapterBase { constructor(name: string, options?: { wasmDir?: string; saveDebounceMs?: number }); open(): Promise<void>; flush(): Promise<void>; static isSupported(): boolean }`
  - `type AdapterBackend = 'opfs' | 'indexeddb' | 'memory'`
  - `interface AdapterCapabilities { opfs(): boolean; indexedDb(): boolean }`
  - `interface OpenAdapterOptions { name: string; backend?: AdapterBackend | 'auto'; wasmDir?: string; opfsTimeoutMs?: number; capabilities?: AdapterCapabilities }`
  - `interface OpenedAdapter { adapter: SQLiteAdapter; backend: AdapterBackend; warnings: string[] }`
  - `function openAdapter(options: OpenAdapterOptions): Promise<OpenedAdapter>`

- [ ] **Step 1: Write the failing test**

`src/adapters/open-adapter.test.ts`:

```ts
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
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/adapters/open-adapter.test.ts`
Expected: FAIL — `Failed to resolve import "./open-adapter"`.

- [ ] **Step 3: Write `src/adapters/indexeddb-adapter.ts`**

```ts
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
```

- [ ] **Step 4: Write `src/adapters/open-adapter.ts`**

```ts
import type { SQLiteAdapter } from './adapter';
import { IndexedDbAdapter } from './indexeddb-adapter';
import { MemoryAdapter } from './memory-adapter';
import { OpfsAdapter } from './opfs-adapter';

export type AdapterBackend = 'opfs' | 'indexeddb' | 'memory';

/** Injectable capability probes, so the selection logic is testable in Node. */
export interface AdapterCapabilities {
  opfs(): boolean;
  indexedDb(): boolean;
}

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
```

- [ ] **Step 5: Run the test and watch it pass**

Run: `npm test -- src/adapters/open-adapter.test.ts`
Expected: PASS, 5 tests.

- [ ] **Step 6: Export the adapters**

Append to `src/index.ts`:

```ts
export { WasmAdapterBase } from './adapters/wasm';
export { OpfsAdapter } from './adapters/opfs-adapter';
export { IndexedDbAdapter } from './adapters/indexeddb-adapter';
export { openAdapter } from './adapters/open-adapter';
export type { AdapterBackend, AdapterCapabilities, OpenAdapterOptions, OpenedAdapter } from './adapters/open-adapter';
```

- [ ] **Step 7: Commit**

```bash
git add src/adapters src/index.ts
git commit -m "$(cat <<'MSG'
feat(adapters): IndexedDB snapshot backend and openAdapter selection

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 32: The browser smoke check

This repository has no Playwright and no vitest-browser, and adding a browser runner for two adapters is more machinery than the check is worth. The smoke is therefore a small page plus a written procedure, run by hand once per release — and it is the only place OPFS and IndexedDB are proven, so it is not optional.

**Files:**
- Create: `packages/core/examples/browser-smoke/index.html`
- Create: `packages/core/examples/browser-smoke/main.ts`
- Create: `packages/core/examples/browser-smoke/README.md`

**Interfaces:**
- Consumes: `openAdapter`, `Database`, `SchemaBuilder`, `createSyncRuntime`, `FakeTransport`.
- Produces: no library API.

- [ ] **Step 1: Write the page**

`examples/browser-smoke/index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>declarative-sqlite browser smoke</title>
  </head>
  <body>
    <h1>declarative-sqlite browser smoke</h1>
    <p>Reload the page after the first run: the row count must keep growing.</p>
    <pre id="out">running…</pre>
    <script type="module" src="./main.ts"></script>
  </body>
</html>
```

`examples/browser-smoke/main.ts`:

```ts
import { Database, SchemaBuilder, createSyncRuntime, openAdapter, FakeTransport } from '../../src/index';

const out = document.getElementById('out') as HTMLPreElement;
const log = (line: string) => {
  out.textContent += `\n${line}`;
};

async function main(): Promise<void> {
  out.textContent = 'opening…';
  const opened = await openAdapter({ name: 'smoke.db' });
  log(`backend: ${opened.backend}`);
  for (const warning of opened.warnings) log(`warning: ${warning}`);

  const schema = new SchemaBuilder();
  schema.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });

  const db = await Database.open({ schema: schema.build(), adapter: opened.adapter });
  const transport = new FakeTransport();
  const sync = await createSyncRuntime({ db, transport, deviceId: 'browser-smoke' });

  const runs = (await db.queryOne<{ n: number }>('SELECT COUNT(*) AS n FROM c_work_task'))?.n ?? 0;
  transport.seed('C_WORK_TASK', [{ id: `row-${runs + 1}`, data: { WO_NO: 3188, C_QTY_INSTALLED: runs + 1 } }]);
  await sync.pull.pull('c_work_task', { wo_no: 3188 });

  const after = (await db.queryOne<{ n: number }>('SELECT COUNT(*) AS n FROM c_work_task'))?.n ?? 0;
  log(`rows before: ${runs}, after: ${after}`);
  log(after > runs ? 'OK: the pull applied' : 'FAIL: nothing was applied');
  log(after > 1 ? 'OK: data survived a reload' : 'reload the page to check persistence');

  if ('flush' in opened.adapter && typeof (opened.adapter as { flush?: () => Promise<void> }).flush === 'function') {
    await (opened.adapter as { flush: () => Promise<void> }).flush();
  }
}

void main().catch((error) => log(`FAIL: ${String(error)}`));
```

- [ ] **Step 2: Write the procedure**

`examples/browser-smoke/README.md`:

```markdown
# Browser smoke check

Run once per release, and after any change to `src/adapters/`. Node tests cover
everything else; this is the only proof that OPFS and the IndexedDB snapshot
work in a real browser.

## Run it

```bash
cd packages/core
npx vite examples/browser-smoke --open
```

## What must happen

| Browser | Expected `backend:` line | Expected on reload |
|---|---|---|
| Chrome/Edge 108+ | `opfs` | the row count grows every reload |
| Firefox 111+ | `opfs` | the row count grows every reload |
| Safari 17+ (macOS/iPadOS) | `opfs` | the row count grows every reload |
| Safari 16 | `indexeddb` (with an OPFS warning) | the row count grows every reload |
| Private window / storage blocked | `memory` with the "not persistent" warning | the count restarts at 1 |

A `FAIL:` line, a `backend: memory` where the table above expects otherwise, or a
count that restarts on reload is a release blocker. Record the browser, the
version and the `backend:` line in the release notes.
```

- [ ] **Step 3: Run it once now and record the result**

Run: `npx vite examples/browser-smoke --open` from `packages/core`, in whichever browser is at hand; paste the observed `backend:` line into `CHANGELOG.md` under the alpha entry (Task 36 creates the file — leave a note in the commit message if it does not exist yet).

- [ ] **Step 4: Commit**

```bash
git add examples
git commit -m "$(cat <<'MSG'
test(adapters): browser smoke page and the manual OPFS/IndexedDB procedure

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 33: React — the provider and `useLiveQuery`

**Files:**
- Create: `packages/core/src/react/provider.tsx`
- Create: `packages/core/src/react/use-live-query.ts`
- Create: `packages/core/src/react/index.ts`
- Modify: `packages/core/tsup.config.ts` (re-enable the `react/index` entry)
- Test: `packages/core/src/react/use-live-query.test.tsx`

**Interfaces:**
- Consumes: `Database`, `SyncRuntime`, `LiveQuery`, `LiveQuerySpec`.
- Produces:
  - `interface SyncProviderProps { db: Database; sync: SyncRuntime; routeKey?: string; children: ReactNode }`
  - `function SyncProvider(props: SyncProviderProps): JSX.Element`
  - `function useDatabase(): Database`
  - `function useSyncRuntime(): SyncRuntime`
  - `function useLiveQuery<T extends Record<string, unknown>>(spec: LiveQuerySpec): T[]`

- [ ] **Step 1: Write the failing test**

`src/react/use-live-query.test.tsx`:

```tsx
/** @vitest-environment happy-dom */
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, waitFor, cleanup } from '@testing-library/react';
import React from 'react';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { FakeTransport } from '../testing/fake-transport';
import { createSyncRuntime, type SyncRuntime } from '../sync/runtime';
import { SyncProvider } from './provider';
import { useLiveQuery } from './use-live-query';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

function Tasks() {
  const rows = useLiveQuery<{ system_id: string; c_qty_installed: number }>({
    sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
    params: [3188],
    reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
    key: 'system_id',
  });
  return (
    <ul>
      {rows.map((row) => (
        <li key={row.system_id} data-testid={row.system_id}>
          {row.c_qty_installed}
        </li>
      ))}
    </ul>
  );
}

describe('useLiveQuery', () => {
  let db: Database | undefined;
  let sync: SyncRuntime | undefined;

  afterEach(async () => {
    cleanup();
    sync?.close();
    await db?.close();
    db = undefined;
    sync = undefined;
  });

  it('renders rows and re-renders when the data changes', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }]);
    sync = await createSyncRuntime({ db, transport, deviceId: 'test' });
    await sync.pull.pull('c_work_task', { wo_no: 3188 });

    render(
      <SyncProvider db={db} sync={sync}>
        <Tasks />
      </SyncProvider>,
    );

    await waitFor(() => expect(screen.getByTestId('A').textContent).toBe('1'));

    await sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    await waitFor(() => expect(screen.getByTestId('A').textContent).toBe('10'));
  });

  it('throws a useful error outside the provider', () => {
    expect(() => render(<Tasks />)).toThrow(/SyncProvider/);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/react/use-live-query.test.tsx`
Expected: FAIL — `Failed to resolve import "./provider"`.

- [ ] **Step 3: Write `src/react/provider.tsx`**

```tsx
import React, { createContext, useContext, useEffect, type ReactNode } from 'react';
import type { Database } from '../db/database';
import type { SyncRuntime } from '../sync/runtime';

interface SyncContextValue {
  db: Database;
  sync: SyncRuntime;
}

const SyncContext = createContext<SyncContextValue | undefined>(undefined);

export interface SyncProviderProps {
  db: Database;
  sync: SyncRuntime;
  /**
   * A value that changes whenever the user navigates — `location.pathname` in a
   * router. Changing it ends every open draft, which is one of the exit paths
   * the draft lifecycle requires.
   */
  routeKey?: string;
  children: ReactNode;
}

/**
 * Puts the database and the sync runtime in context and owns the global draft
 * exit paths: `pagehide` and `visibilitychange` end every open draft, so
 * backgrounding the app on an iPad commits what the user typed instead of
 * losing it, and so does a route change when `routeKey` is supplied.
 */
export function SyncProvider({ db, sync, routeKey, children }: SyncProviderProps): JSX.Element {
  useEffect(() => {
    const endAll = () => {
      void sync.drafts.endAll();
    };
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') endAll();
    };
    window.addEventListener('pagehide', endAll);
    document.addEventListener('visibilitychange', onVisibility);
    return () => {
      window.removeEventListener('pagehide', endAll);
      document.removeEventListener('visibilitychange', onVisibility);
    };
  }, [sync]);

  useEffect(() => {
    return () => {
      void sync.drafts.endAll();
    };
  }, [sync, routeKey]);

  return <SyncContext.Provider value={{ db, sync }}>{children}</SyncContext.Provider>;
}

/** The database from the nearest `SyncProvider`. Throws with a readable message when there is none. */
export function useDatabase(): Database {
  const value = useContext(SyncContext);
  if (!value) throw new Error('useDatabase must be used inside a <SyncProvider>');
  return value.db;
}

/** The sync runtime from the nearest `SyncProvider`. Throws with a readable message when there is none. */
export function useSyncRuntime(): SyncRuntime {
  const value = useContext(SyncContext);
  if (!value) throw new Error('useSyncRuntime must be used inside a <SyncProvider>');
  return value.sync;
}
```

- [ ] **Step 4: Write `src/react/use-live-query.ts`**

```ts
import { useEffect, useMemo, useSyncExternalStore } from 'react';
import type { LiveQuerySpec } from '../live/live-query';
import { useDatabase } from './provider';

const EMPTY: never[] = [];

/**
 * Subscribes a component to a live query through `useSyncExternalStore`. The
 * query is created from the spec and re-created only when the SQL, the
 * parameters or the declared reads change, so a parent re-render costs nothing.
 * The returned array is referentially stable between emissions and its
 * unchanged rows keep their identity, which is what makes a keyed list cheap.
 * The query is closed when the component unmounts.
 */
export function useLiveQuery<T extends Record<string, unknown>>(spec: LiveQuerySpec): T[] {
  const db = useDatabase();
  const key = `${spec.sql}|${JSON.stringify(spec.params ?? [])}|${JSON.stringify(spec.reads)}|${spec.key}`;

  const query = useMemo(() => db.live<T>(spec), [db, key]);

  useEffect(() => {
    return () => {
      query.close();
    };
  }, [query]);

  return useSyncExternalStore(
    (onStoreChange) => query.subscribe(() => onStoreChange()),
    () => query.snapshot(),
    () => EMPTY as unknown as T[],
  );
}
```

- [ ] **Step 5: Write `src/react/index.ts` and re-enable the tsup entry**

```ts
/**
 * `declarative-sqlite/react` — the thin React binding. Everything here is a view
 * over the primitives in the root entry point; nothing in this file holds state
 * of its own, because drafts, the outbox and live queries already live in the
 * library where a component unmount cannot lose them.
 */
export { SyncProvider, useDatabase, useSyncRuntime } from './provider';
export type { SyncProviderProps } from './provider';
export { useLiveQuery } from './use-live-query';
```

In `tsup.config.ts`, remove the `// re-enabled in Task 33` comment so the entry `'react/index': 'src/react/index.ts'` is active.

- [ ] **Step 6: Run the test and the build**

Run: `npm test -- src/react/use-live-query.test.tsx && npm run build`
Expected: PASS, 2 tests; `dist/react/index.js`, `dist/react/index.cjs` and `dist/react/index.d.ts` exist.

- [ ] **Step 7: Commit**

```bash
git add src/react tsup.config.ts
git commit -m "$(cat <<'MSG'
feat(react): SyncProvider with the draft exit paths and useLiveQuery

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 34: React — `useDraftField`

The only way an editable field is written. The hook owns nothing: it reads and drives the library's draft store, so a virtualised list can unmount the row mid-edit and the keystrokes survive.

**Files:**
- Create: `packages/core/src/react/use-draft-field.ts`
- Modify: `packages/core/src/react/index.ts`
- Test: `packages/core/src/react/use-draft-field.test.tsx`

**Interfaces:**
- Consumes: `useSyncRuntime`, `Drafts`, `Outbox`.
- Produces:
  - `interface DraftFieldBinding<T> { value: T; isDrafting: boolean; isPending: boolean; onFocus(): void; onChange(next: T | React.ChangeEvent<HTMLInputElement>): void; onBlur(): void; onKeyDown(event: React.KeyboardEvent): void }`
  - `function useDraftField<T>(table: string, systemId: string, column: string, currentValue: T): DraftFieldBinding<T>`

- [ ] **Step 1: Write the failing test**

`src/react/use-draft-field.test.tsx`:

```tsx
/** @vitest-environment happy-dom */
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, waitFor, cleanup, fireEvent } from '@testing-library/react';
import React from 'react';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { FakeTransport } from '../testing/fake-transport';
import { createSyncRuntime, type SyncRuntime } from '../sync/runtime';
import { SyncProvider } from './provider';
import { useLiveQuery } from './use-live-query';
import { useDraftField } from './use-draft-field';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.text('internal_remark');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

function Remark({ systemId, value }: { systemId: string; value: string }) {
  const field = useDraftField<string>('c_work_task', systemId, 'internal_remark', value);
  return <input data-testid={`remark-${systemId}`} value={field.value ?? ''} onFocus={field.onFocus} onChange={field.onChange} onBlur={field.onBlur} onKeyDown={field.onKeyDown} />;
}

function List() {
  const rows = useLiveQuery<{ system_id: string; internal_remark: string }>({
    sql: 'SELECT system_id, internal_remark FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
    params: [3188],
    reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
    key: 'system_id',
  });
  return (
    <>
      {rows.map((row) => (
        <Remark key={row.system_id} systemId={row.system_id} value={row.internal_remark} />
      ))}
    </>
  );
}

describe('useDraftField', () => {
  let db: Database | undefined;
  let sync: SyncRuntime | undefined;

  async function setup() {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, INTERNAL_REMARK: 'start' } }]);
    sync = await createSyncRuntime({ db, transport, deviceId: 'test', debounceMs: 10_000 });
    await sync.pull.pull('c_work_task', { wo_no: 3188 });
    render(
      <SyncProvider db={db} sync={sync}>
        <List />
      </SyncProvider>,
    );
    await waitFor(() => expect(screen.getByTestId('remark-A')).toBeDefined());
    return { transport, sync };
  }

  afterEach(async () => {
    cleanup();
    sync?.close();
    await db?.close();
    db = undefined;
    sync = undefined;
  });

  it('shows the stream value until the field takes focus', async () => {
    const s = await setup();
    const input = screen.getByTestId('remark-A') as HTMLInputElement;
    expect(input.value).toBe('start');
    expect(s.sync.drafts.isActive('c_work_task', 'A', 'internal_remark')).toBe(false);
  });

  it('keeps what is typed while a pull lands underneath', async () => {
    const s = await setup();
    const input = screen.getByTestId('remark-A') as HTMLInputElement;
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: 'sjekket' } });

    s.transport.serverEdit('C_WORK_TASK', 'A', { INTERNAL_REMARK: 'from the server' });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });

    await waitFor(() => expect((screen.getByTestId('remark-A') as HTMLInputElement).value).toBe('sjekket'));
  });

  it('commits on blur and the value stays through the overlay', async () => {
    const s = await setup();
    const input = screen.getByTestId('remark-A') as HTMLInputElement;
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: 'sjekket' } });
    fireEvent.blur(input);

    await waitFor(() => expect(s.sync.outbox.pendingValue('c_work_task', 'A', 'internal_remark')).toEqual({ value: 'sjekket' }));
    await waitFor(() => expect((screen.getByTestId('remark-A') as HTMLInputElement).value).toBe('sjekket'));
  });

  it('commits on Enter', async () => {
    const s = await setup();
    const input = screen.getByTestId('remark-A') as HTMLInputElement;
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: 'enter' } });
    fireEvent.keyDown(input, { key: 'Enter' });

    await waitFor(() => expect(s.sync.outbox.pendingValue('c_work_task', 'A', 'internal_remark')).toEqual({ value: 'enter' }));
  });

  it('abandons the draft on Escape without recording anything', async () => {
    const s = await setup();
    const input = screen.getByTestId('remark-A') as HTMLInputElement;
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: 'oops' } });
    fireEvent.keyDown(input, { key: 'Escape' });

    await waitFor(() => expect(s.sync.drafts.isActive('c_work_task', 'A', 'internal_remark')).toBe(false));
    expect(await db!.query('SELECT id FROM outbox')).toEqual([]);
    await waitFor(() => expect((screen.getByTestId('remark-A') as HTMLInputElement).value).toBe('start'));
  });

  it('records nothing when the value was not changed', async () => {
    const s = await setup();
    const input = screen.getByTestId('remark-A') as HTMLInputElement;
    fireEvent.focus(input);
    fireEvent.blur(input);
    expect(await db!.query('SELECT id FROM outbox')).toEqual([]);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/react/use-draft-field.test.tsx`
Expected: FAIL — `Failed to resolve import "./use-draft-field"`.

- [ ] **Step 3: Write `src/react/use-draft-field.ts`**

```ts
import { useCallback, useSyncExternalStore, type ChangeEvent, type KeyboardEvent } from 'react';
import { useSyncRuntime } from './provider';

/** Everything an input needs. Spread it onto the element; do not keep a `useState` beside it. */
export interface DraftFieldBinding<T> {
  value: T;
  isDrafting: boolean;
  isPending: boolean;
  onFocus(): void;
  onChange(next: T | ChangeEvent<HTMLInputElement | HTMLTextAreaElement>): void;
  onBlur(): void;
  onKeyDown(event: KeyboardEvent): void;
}

/**
 * Binds one editable column of one row. The draft lives in the library's store,
 * keyed `(table, systemId, column)`, so the input can unmount and remount — a
 * virtualised list, a re-render from a pull — without losing a keystroke. Focus
 * starts the draft, every keystroke updates it, and blur, Enter, an explicit
 * save, the Sync button, a route change or `pagehide` end it: changed values go
 * to the outbox and the pending overlay takes the column over, unchanged ones
 * release it and let any held server value through. Escape abandons the draft.
 * `currentValue` is what the live query emitted for this cell — already
 * overlaid and already held — and is what the field shows when no draft is open.
 */
export function useDraftField<T>(table: string, systemId: string, column: string, currentValue: T): DraftFieldBinding<T> {
  const sync = useSyncRuntime();

  const isDrafting = useSyncExternalStore(
    (onStoreChange) => sync.drafts.subscribe(onStoreChange),
    () => sync.drafts.isActive(table, systemId, column),
    () => false,
  );

  const draftValue = useSyncExternalStore(
    (onStoreChange) => sync.drafts.subscribe(onStoreChange),
    () => sync.drafts.get(table, systemId, column),
    () => undefined,
  );

  const isPending = useSyncExternalStore(
    (onStoreChange) => sync.outbox.subscribe(onStoreChange),
    () => sync.outbox.pendingColumns(table, systemId).has(column),
    () => false,
  );

  const onFocus = useCallback(() => {
    sync.drafts.begin(table, systemId, column, currentValue);
  }, [sync, table, systemId, column, currentValue]);

  const onChange = useCallback(
    (next: T | ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
      const value =
        next !== null && typeof next === 'object' && 'target' in next
          ? ((next.target as HTMLInputElement).value as unknown as T)
          : next;
      if (!sync.drafts.isActive(table, systemId, column)) sync.drafts.begin(table, systemId, column, currentValue);
      sync.drafts.set(table, systemId, column, value);
    },
    [sync, table, systemId, column, currentValue],
  );

  const onBlur = useCallback(() => {
    void sync.drafts.end(table, systemId, column);
  }, [sync, table, systemId, column]);

  const onKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (event.key === 'Enter') {
        void sync.drafts.end(table, systemId, column);
      } else if (event.key === 'Escape') {
        sync.drafts.set(table, systemId, column, currentValue);
        void sync.drafts.end(table, systemId, column);
      }
    },
    [sync, table, systemId, column, currentValue],
  );

  return {
    value: (isDrafting ? (draftValue as T) : currentValue),
    isDrafting,
    isPending,
    onFocus,
    onChange,
    onBlur,
    onKeyDown,
  };
}
```

Note the Escape path: setting the draft back to the seed makes `end()` see an unchanged value, so it releases the column and applies any held server value — exactly the "unchanged" branch, with no special case in the draft store.

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/react/use-draft-field.test.tsx`
Expected: PASS, 6 tests.

- [ ] **Step 5: Export it**

Add to `src/react/index.ts`:

```ts
export { useDraftField } from './use-draft-field';
export type { DraftFieldBinding } from './use-draft-field';
```

- [ ] **Step 6: Commit**

```bash
git add src/react
git commit -m "$(cat <<'MSG'
feat(react): useDraftField as the only write path for editable fields

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 35: React — `useOutboxCounts` and `useSyncStatus`

**Files:**
- Create: `packages/core/src/react/use-outbox-counts.ts`
- Create: `packages/core/src/react/use-sync-status.ts`
- Modify: `packages/core/src/react/index.ts`
- Test: `packages/core/src/react/use-outbox-counts.test.tsx`

**Interfaces:**
- Consumes: `useSyncRuntime`, `Outbox.counts`, `Outbox.subscribe`, `PushService.status`, `PushService.onStatusChange`.
- Produces:
  - `interface OutboxCounts { pending: number; sending: number; rejected: number }`
  - `function useOutboxCounts(): OutboxCounts`
  - `function useSyncStatus(): SyncStatus`

- [ ] **Step 1: Write the failing test**

`src/react/use-outbox-counts.test.tsx`:

```tsx
/** @vitest-environment happy-dom */
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, waitFor, cleanup } from '@testing-library/react';
import React from 'react';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { FakeTransport } from '../testing/fake-transport';
import { createSyncRuntime, type SyncRuntime } from '../sync/runtime';
import { SyncProvider } from './provider';
import { useOutboxCounts } from './use-outbox-counts';
import { useSyncStatus } from './use-sync-status';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

function Badge() {
  const counts = useOutboxCounts();
  const status = useSyncStatus();
  return (
    <div>
      <span data-testid="pending">{counts.pending}</span>
      <span data-testid="rejected">{counts.rejected}</span>
      <span data-testid="online">{String(status.online)}</span>
    </div>
  );
}

describe('useOutboxCounts / useSyncStatus', () => {
  let db: Database | undefined;
  let sync: SyncRuntime | undefined;

  afterEach(async () => {
    cleanup();
    sync?.close();
    await db?.close();
    db = undefined;
    sync = undefined;
  });

  it('shows the pending count and follows it', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }]);
    sync = await createSyncRuntime({ db, transport, deviceId: 'test', debounceMs: 10_000 });
    await sync.pull.pull('c_work_task', { wo_no: 3188 });

    render(
      <SyncProvider db={db} sync={sync}>
        <Badge />
      </SyncProvider>,
    );

    await waitFor(() => expect(screen.getByTestId('pending').textContent).toBe('0'));
    expect(screen.getByTestId('online').textContent).toBe('true');

    await sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    await waitFor(() => expect(screen.getByTestId('pending').textContent).toBe('1'));
  });

  it('shows a rejected change and the offline state', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }]);
    transport.reject('C_WORK_TASK', 'C_QTY_INSTALLED', 'CBADSTATE: no');
    sync = await createSyncRuntime({ db, transport, deviceId: 'test', debounceMs: 10_000 });
    await sync.pull.pull('c_work_task', { wo_no: 3188 });

    render(
      <SyncProvider db={db} sync={sync}>
        <Badge />
      </SyncProvider>,
    );

    await sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    await sync.push.pushNow();
    await waitFor(() => expect(screen.getByTestId('rejected').textContent).toBe('1'));
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm test -- src/react/use-outbox-counts.test.tsx`
Expected: FAIL — `Failed to resolve import "./use-outbox-counts"`.

- [ ] **Step 3: Write the two hooks**

`src/react/use-outbox-counts.ts`:

```ts
import { useEffect, useState } from 'react';
import { useSyncRuntime } from './provider';

/** What the header badge shows: recorded but unsent, in flight, and refused by the server. */
export interface OutboxCounts {
  pending: number;
  sending: number;
  rejected: number;
}

const ZERO: OutboxCounts = { pending: 0, sending: 0, rejected: 0 };

/**
 * Follows the outbox counters for a badge. Counting is a query, so this hook
 * keeps state rather than reading a snapshot synchronously: it recounts whenever
 * the outbox changes and drops the result if the component has unmounted.
 */
export function useOutboxCounts(): OutboxCounts {
  const sync = useSyncRuntime();
  const [counts, setCounts] = useState<OutboxCounts>(ZERO);

  useEffect(() => {
    let alive = true;
    const refresh = () => {
      void sync.outbox.counts().then((next) => {
        if (alive) setCounts(next);
      });
    };
    refresh();
    const stop = sync.outbox.subscribe(refresh);
    return () => {
      alive = false;
      stop();
    };
  }, [sync]);

  return counts;
}
```

`src/react/use-sync-status.ts`:

```ts
import { useSyncExternalStore } from 'react';
import type { SyncStatus } from '../sync/push-service';
import { useSyncRuntime } from './provider';

const OFFLINE_UNKNOWN: SyncStatus = { online: true, sending: false, attempt: 0, nextRetryAt: null, lastError: null };

/**
 * The push service's current state: online, a push in flight, how many attempts
 * the current backoff has made and when the next one is due. Use it for the
 * header indicator and for an "offline, N changes waiting" line — the app owns
 * the Norwegian wording.
 */
export function useSyncStatus(): SyncStatus {
  const sync = useSyncRuntime();
  return useSyncExternalStore(
    (onStoreChange) => sync.push.onStatusChange(() => onStoreChange()),
    () => sync.push.status(),
    () => OFFLINE_UNKNOWN,
  );
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `npm test -- src/react`
Expected: PASS across the React suite (10 tests).

- [ ] **Step 5: Export them**

Add to `src/react/index.ts`:

```ts
export { useOutboxCounts } from './use-outbox-counts';
export type { OutboxCounts } from './use-outbox-counts';
export { useSyncStatus } from './use-sync-status';
export type { SyncStatus } from '../sync/push-service';
```

- [ ] **Step 6: Commit**

```bash
git add src/react
git commit -m "$(cat <<'MSG'
feat(react): useOutboxCounts and useSyncStatus for the sync badge

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 36: Build, docs and the alpha release

**Files:**
- Modify: `packages/core/package.json` (verify the exports map against the built output)
- Create: `packages/core/CHANGELOG.md`
- Modify: `packages/core/README.md` (full rewrite)
- Test: `packages/core/src/index.test.ts` (extend into a public-surface test)

**Interfaces:**
- Consumes: every public export.
- Produces: the published package shape.

- [ ] **Step 1: Extend the entry-point test**

`src/index.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import * as root from './index';

describe('public surface', () => {
  it('reports the v3 alpha version', () => {
    expect(root.VERSION).toBe('3.0.0-alpha.1');
  });

  it('exports the five layers', () => {
    for (const name of [
      'SchemaBuilder', 'validateScopes',
      'runMigration', 'planMigration', 'MigrationBlockedError',
      'MemoryAdapter', 'OpfsAdapter', 'IndexedDbAdapter', 'openAdapter',
      'Database', 'Transaction', 'LiveQuery',
      'Outbox', 'Overlay', 'Drafts', 'CursorStore', 'PullApplier', 'PullService', 'PushService', 'TickCoalescer', 'createSyncRuntime',
      'FakeTransport',
    ]) {
      expect(root, `missing export: ${name}`).toHaveProperty(name);
    }
  });

  it('does not export the server-write capability', () => {
    expect(root).not.toHaveProperty('createServerWriteCapability');
  });
});
```

Run: `npm test -- src/index.test.ts` and fix any missing export.

- [ ] **Step 2: Write `CHANGELOG.md`**

```markdown
# Changelog

## 3.0.0-alpha.1

A full rewrite. v3 is a sync data layer, not a database wrapper: the three owners
of state — server truth in tables, the outbox of unconfirmed changes, and the
draft being typed — are primitives the API enforces.

### Added
- `.synced()` tables: server truth, writable only by the pull applier and the
  outbox committer through a capability object.
- `Outbox` with change groups, statuses, idempotent batch ids, retry and discard.
- `Overlay`: pending outbox columns win on every read of a synced table.
- `Drafts`: focus lifecycle, per-column holds, held tombstones, and every exit
  path (blur, Enter, save, Sync, route change, `pagehide`).
- `CursorStore`, `PullApplier`, `PullService` (window rule), `PushService`
  (debounce, groups intact, backoff, answers as receipts), `TickCoalescer`.
- `db.live(...)`: scope-aware invalidation, one emission per transaction,
  emit-on-change with row identity preserved.
- `declarative-sqlite/react`: `SyncProvider`, `useLiveQuery`, `useDraftField`,
  `useOutboxCounts`, `useSyncStatus`.
- `MemoryAdapter`, `OpfsAdapter` (SAH-pool VFS), `IndexedDbAdapter` (persisted
  image), and `openAdapter` with capability probing and an OPFS timeout.
- `FakeTransport`: a scripted server for application tests.

### Removed
- HLC, per-column LWW, `__hlc` columns, `__dirty_rows`, `bulkLoad`'s merge and
  `forceOverwrite`. The server decides; the client records and overlays.
- RxJS streams (`stream`, `subscribeToTable`) — replaced by live queries.
- File management (`files/`, ZenFS) — the app uses ZenFS directly.
- `query-builder.ts`, the persistence examples and the storage-init helpers.

### Changed
- `date()` and `guid()` store TEXT, so introspection round-trips and migrations
  stop proposing spurious table rebuilds.
- Automatic migration is still additive and still refuses to rebuild a table
  without `allowRecreate: true`.

### Known limits
- `IndexedDbAdapter` persists the whole database image after writes settle; it
  can lose the last debounce window on a crash. Prefer OPFS.
- v3 is modify-only, matching `PushBatch`: creates and deletes of server rows go
  through the app's existing v1 path until IFS defines the v3 equivalents.
```

- [ ] **Step 3: Rewrite `README.md`**

Structure (write it out in full, with runnable code):
1. What it is, in three sentences: server truth, outbox, drafts.
2. Install, and the two entry points.
3. Quick start: `SchemaBuilder` with one `.synced()` table → `openAdapter` → `Database.open` → `createSyncRuntime` → one `db.live` and one `outbox.record`. Copy the code from `src/sync/runtime.test.ts`, which is known to run.
4. The three owners of state, with the table from the spec's §7 and a sentence each on overlay and holds.
5. Live queries: the spec's rules 1–5 as a numbered list with the `db.live` example.
6. Writing: `db.tables` for local tables, `outbox.record` for synced ones, and why a synced table has no write methods.
7. Sync: implementing `SyncTransport` against `/sync/rows` and `/sync/push`, the window rule, the push answer as a receipt, tick coalescing.
8. React: the provider, the four hooks, and the exit paths.
9. Adapters: the table from `examples/browser-smoke/README.md`, and the IndexedDB caveat.
10. Testing your app: `MemoryAdapter` + `FakeTransport`, with the scripted-server example.
11. Migrating from 2.x: a link to `MIGRATION-v2-to-v3.md`.

- [ ] **Step 4: Verify the package as it would publish**

```bash
cd "C:/repos/Apply AS/declarative_sqlite/packages/core"
npm run typecheck && npm test && npm run build
npm pack --dry-run
```
Expected: `dist/index.{js,cjs,d.ts}` and `dist/react/index.{js,cjs,d.ts}` are in the tarball listing, `src/` is not, and the version is `3.0.0-alpha.1`.

- [ ] **Step 5: Commit**

```bash
git add package.json CHANGELOG.md README.md src/index.test.ts
git commit -m "$(cat <<'MSG'
chore(release): 3.0.0-alpha.1 build, exports map, CHANGELOG and README

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

### Task 37: The Apply Work migration guide

The last deliverable is the document the consuming app's Phase 3 executes against. It is written here, in the library repo, because it is the library's contract with its only consumer.

**Files:**
- Create: `packages/core/MIGRATION-v2-to-v3.md`

**Interfaces:**
- Consumes: the whole public surface.
- Produces: no code.

- [ ] **Step 1: Write the guide**

`MIGRATION-v2-to-v3.md`, with these sections and real code in each:

1. **What changes, in one table.** `SchemaBuilder` survives; `.lww()` and every `*__hlc` column are gone; `DeclarativeDatabase` becomes `Database`; `stream`/`subscribeToTable` become `db.live`/`useLiveQuery`; `db.update` on a synced table becomes `outbox.record`; `Hlc`, `dirtyRowStore`, `bulkLoad(..., forceOverwrite)` and `AdapterFactory` are gone.

2. **`src/schema.ts`.** Show one table before and after:

```ts
// v2
builder.table('c_work_task', (table) => {
  table.real('wo_no').notNull(0.0);
  table.real('c_qty_installed').lww();
  table.text('rowstate').maxLength(100).lww();
  table.integer('system_removed').notNull(0);
  table.key('system_id').primary();
});

// v3
schema.table('c_work_task', (table) => {
  table.real('wo_no').notNull(0.0);
  table.real('c_qty_installed');
  table.text('rowstate').maxLength(100);
  table.integer('system_removed').notNull(0);
  table.key('system_id').primary();
}).synced({ key: 'system_id', scope: ['wo_no'] });
```

   Then the scope per mirror table, taken from `wire-format.md` §9.2: `c_work_task`/`c_work_order`/`c_maint_material_req_line`/`c_work_order_attachment`/`c_work_order_note` → `['wo_no']`; `c_checklist`/`c_check_item`/`c_approval_line` → `['task_seq']`; `c_doc_ref_object`/`c_aw_proarc_doc_rev_conn`/`c_ncr_object_connection`/`c_wo_document` → `['lu_name', 'key_ref']`; `c_aw_shipment` → `['receiver_id']`; `c_aw_shipment_line` → `['shipment_id']`; `c_ncr` → `['ncr_no']`. The tables `wire-format.md` marks `ALLOW_FULL_PULL = yes` (`c_apply_work_user`, `c_aw_inventory_location`, `c_aw_proarc_doc_rev`, `c_edm_file`, `c_work_file`) declare `scope: []` and are pulled whole. `outbox` and `sync_cursor` are dropped from `schema.ts` if they were ever added by hand — the library owns them.

3. **`src/v2/services/DatabaseService.ts`.** Replace `AdapterFactory.create(...)` and the Safari branching with `openAdapter({ name, wasmDir: '/assets' })`, keeping the Capacitor path as a supplied adapter:

```ts
const opened = isNative
  ? { adapter: await openCapacitorAdapter(dbName), backend: 'native' as const, warnings: [] }
  : await openAdapter({ name: dbName, wasmDir: '/assets' });
this.db = await Database.open<AppRows, SyncedTableName>({ schema, adapter: opened.adapter });
this.sync = await createSyncRuntime({ db: this.db, transport: new HttpSyncTransport(api), deviceId });
```

   `AppRows` is a `RowMap` built from the 19 interfaces already in `schema.ts`; `SyncedTableName` is the union of the mirror table names. The 30-second `PRAGMA wal_checkpoint(TRUNCATE)` timer goes away; call `adapter.flush()` on `pagehide` when the backend is `indexeddb`.

4. **Replacing `SyncService.ts`.** A mapping table: `pullData`/`pullSpecificTables` → `sync.pull.pull(table, scope)`; `pushData` → `sync.push.pushNow()`/`schedule()`; `triggerDebouncedSync` → `sync.push.schedule()`; SignalR `TableChanged` → `sync.ticks.notify({ table, seq, scopes })`; the Sync button → `await sync.drafts.endAll(); await sync.push.pushNow(); await sync.pull.pull(table, scope, { from: 0 })`; `recentlyPushedTables`, the ETag cache and `RemovalStagingService` are deleted with nothing replacing them.

5. **The `SyncTransport` implementation**, in full, against the app's API client:

```ts
export class HttpSyncTransport implements SyncTransport {
  constructor(private readonly api: ApiClient, private readonly domain: string) {}

  async pullRows(req: PullRequest): Promise<RowsPage> {
    const params = new URLSearchParams({ domain: this.domain, table: req.table, after: String(req.after) });
    if (req.scope) params.set('scope', req.scope);
    if (req.limit) params.set('limit', String(req.limit));
    return this.api.get<RowsPage>(`/sync/rows?${params.toString()}`);
  }

  async push(batch: PushBatch): Promise<PushResult> {
    return this.api.post<PushResult>(`/sync/push?domain=${encodeURIComponent(this.domain)}`, batch);
  }
}
```

   with a note that a 4xx should be surfaced through `isTerminalError` so the push service marks the batch rejected instead of retrying forever.

6. **Hooks and components.** `useDatabaseRecord.updateField` → `sync.outbox.record({ table, systemId, changes: { [field]: value } })`; the `__hlc` branch and `db.generateHLC()` are deleted; every editable field moves to `useDraftField`; lists move to `useLiveQuery`; `useTableSync` becomes a `useEffect` that calls `sync.pull.registerScope(table, scope)` and pulls once.

7. **The one-time upgrade (Phase 3 Task 3.8).** Push any remaining v2 `__dirty_rows` through the old path, close the v2 database, delete the OPFS file / IndexedDB image, open v3 (which creates everything), then `sync.pull.pull(...)` for the last ten visited work orders. Show the check that decides it ran:

```ts
const legacy = await db.queryOne<{ n: number }>(
  `SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' AND name = '__dirty_rows'`,
);
if ((legacy?.n ?? 0) > 0) await runLegacyUpgrade();
```

8. **What v3 does not do.** Creates and deletes of server rows: `PushBatch` is modify-only and `SYSTEM_REMOVED` is not writable, so `BulkNew`/`BulkRemove` stay in the app until IFS Phase-2 task 2.0 defines the v3 equivalents. The library records a change group per row and never invents one.

- [ ] **Step 2: Check every code block against the built package**

For each snippet, confirm the symbol exists in `dist/index.d.ts` (or `dist/react/index.d.ts`):

```bash
cd "C:/repos/Apply AS/declarative_sqlite/packages/core"
grep -o "openAdapter\|createSyncRuntime\|SyncTransport\|useDraftField\|useLiveQuery" dist/index.d.ts dist/react/index.d.ts | sort -u
```
Expected: every name used in the guide appears. Fix the guide, not the package, if one does not.

- [ ] **Step 3: Commit**

```bash
git add MIGRATION-v2-to-v3.md
git commit -m "$(cat <<'MSG'
docs: migration guide from declarative-sqlite 2.x to 3.0 for Apply Work

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
)"
```

---

## Self-review

**Spec coverage.** Every section of `2026-09-17-v3-sync-data-layer-design.md` maps to tasks: §3 the rewrite (Task 1); §5.1 database core, single write path, invalidation bus, typed `db.tables`, server-truth guard (Tasks 10–12); §5.2 fluent schema, `.synced()`, library tables, additive auto-migration with plan mode and guarded recreation (Tasks 3–5, 6–9); §6 live queries, all five rules (Tasks 13–15, with the overlay/hold transform installed in Task 28); §7.1 outbox with change groups (18–19); §7.2 overlay (20); §7.3 drafts including held tombstones and exit paths (21–22); §7.4 cursors and pull, window rule, 200-row page in one transaction (23–25); §7.5 push, debounce, groups intact, idempotent batch, backoff, answers as receipts with the seq guard (26–27); §7.6 tick coalescing (28); §7.7 transport mirroring the wire format, with the local 4000-character refusal (16–17); §8 the React binding (33–35); §9 the `MemoryAdapter`, all nine named scenarios and the migration matrix (2, 29, 9); §10 the Apply Work migration path (37). The adapters of §2's goals are Tasks 30–32. Consumer requirements A3/A4 are covered by Tasks 16–17 (wire), 24 and 29 (editing while a pull lands), 18 (one user, coupled fields), 28 (notification noise), 27 (a push answer is a receipt); Phase 3's Task 3.7 draft lifecycle is Tasks 21, 22 and 34.

**Placeholder scan.** No step says "TBD", "add error handling" or "similar to Task N". Every code step carries the code. Two steps deliberately verify rather than write — Task 27 Step 2 and Task 15 Step 2 run tests against code written in the preceding task and fix gaps; both name the file to change and forbid relaxing the assertions. Task 36's README and Task 37's guide are specified section by section with their code, which is the most a document task can be without being the document.

**Type consistency.** Checked across tasks: `ScopeValues`, `Row`, `SqlValue` come from `src/types.ts` (Task 2) and are used unchanged everywhere. `scopeKey`/`formatScope` (Task 5) are used by the cursor store (23) and the pull service (25) with the same signature. `SYNC_SEQ_COLUMN`/`SYSTEM_REMOVED_COLUMN`/`SYSTEM_ID_COLUMN` are defined once (Task 4) and imported by the applier (24) and the database (12). `ServerWriter.setColumns(tx, table, key, values)` is defined in Task 12 and called with that shape by the outbox (18), the drafts (22) and the applier (24). `Outbox.applyResults(batchId, results, order)` (19) is called by the push service (26) with `batch.entries.map(e => e.id)` as `order`. `PullApplier.applyRows(table, rows, options)` (24) is called by the push service (27) with `{ seqGuard: true, advanceCursor: false }`. `LiveQuerySpec`/`RowTransform` (14) are what `db.setRowTransform` (14) and `createSyncRuntime` (28) exchange. `SyncStatus` is declared in `push-service.ts` (26) and re-exported from the React entry (35) rather than redeclared.

**Open risks the executor should watch.** (1) The invalidation count in Task 29's "a 200-row page commits once" depends on whether the cursor write is a separate transaction — the step says to assert the exact number observed, not a range. (2) `IndexedDbAdapter` is unproven outside Task 32's manual smoke; if it fails there, the fallback chain still lands on memory with a warning, which is correct behaviour, and the fix belongs in Task 31. (3) `useSyncExternalStore` requires `getSnapshot` to be referentially stable — `LiveQuery.snapshot()` returns the cached array, which is why Task 13's identity preservation is load-bearing for Task 33 and not merely an optimisation.
