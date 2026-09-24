---
title: Getting started
description: "Install the package, configure Vite, open a local database, and add sync."
---

# Getting started

## Install

```bash
npm install declarative-sqlite
```

The package depends on `@sqlite.org/sqlite-wasm`, which it installs for you.
`react` (18 or later) is an optional peer dependency, only needed for
`declarative-sqlite/react`.

### Bundler setup (Vite)

The SQLite WebAssembly build loads its `.wasm` file at runtime. With Vite,
keep it out of dependency pre-bundling so that the file is found:

```ts title="vite.config.ts"
export default defineConfig({
  optimizeDeps: {
    exclude: ['@sqlite.org/sqlite-wasm'],
  },
});
```

If you serve `sqlite3.wasm` from a folder of your own, pass that folder as
`wasmDir` when opening storage (`openAdapter({ name, wasmDir: '/assets' })`).

The OPFS backend used here doesn't need cross-origin isolation, so you don't
have to set COOP/COEP headers for it.

## A local database

The smallest useful program: one table, stored in the browser, read with a
live query.

```ts
import { SchemaBuilder, openAdapter, Database } from 'declarative-sqlite';

const schema = new SchemaBuilder();
schema.table('note', (t) => {
  t.text('body').notNull('');
  t.date('created_at');
});

const { adapter, backend, warnings } = await openAdapter({ name: 'notes.db' });
warnings.forEach((w) => console.warn(w)); // e.g. "Storage is not persistent"

const db = await Database.open({ schema: schema.build(), adapter });

await db.tables.note.insert({
  system_id: crypto.randomUUID(),
  body: 'Hello',
  created_at: new Date().toISOString(),
});

const notes = db.live<{ system_id: string; body: string }>({
  sql: 'SELECT system_id, body FROM note ORDER BY created_at DESC',
  reads: [{ table: 'note' }],
  key: 'system_id',
});
notes.subscribe((rows) => console.log(rows));
```

Every table gets a `system_id` text column, which is its primary key. You
supply the value when inserting; `crypto.randomUUID()` is a good default.

## Adding sync

To keep a table in step with a server, mark it `.synced()` and create a sync
runtime. The `transport` object is the only piece you write yourself; it
calls your API (see [Sync](./sync.md) and [Server protocol](./server-protocol.md)).

```ts
import {
  SchemaBuilder,
  openAdapter,
  Database,
  createSyncRuntime,
  type SyncTransport,
} from 'declarative-sqlite';

const schema = new SchemaBuilder();
schema
  .table('task', (t) => {
    t.integer('project_id');
    t.text('title');
    t.real('hours');
  })
  .synced({ key: 'system_id', scope: ['project_id'] });

const { adapter } = await openAdapter({ name: 'app.db' });
const db = await Database.open({ schema: schema.build(), adapter });

const transport: SyncTransport = {
  pullRows: (req) => api.get('/sync/rows', req),
  push: (batch) => api.post('/sync/push', batch),
};
const sync = await createSyncRuntime({ db, transport, deviceId: getInstallId() });

// Fetch the server's rows for one project.
await sync.pull.pull('task', { project_id: 42 });

// Edit one. The local row changes immediately; the push goes out ~2 s later.
await sync.outbox.record({
  table: 'task',
  systemId: 'a3f1…',
  changes: { hours: 3.5 },
});
```

When the app shuts down, close the runtime before the database:

```ts
sync.close();
await db.close();
```

## Where to go next

- [Schema](./schema.md): column types, keys, defaults and synced tables.
- [Live queries](./live-queries.md): how invalidation and scopes work.
- [Sync](./sync.md): pulling, the outbox, pushing and rejected changes.
- [React](./react.md): the provider and hooks.
