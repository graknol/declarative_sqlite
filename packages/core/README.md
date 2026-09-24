# declarative-sqlite

An offline-first sync data layer for SQLite in the browser. It runs real
SQLite (WebAssembly, stored in OPFS where available), keeps a local copy of
server data, lets the user edit it offline, and syncs the edits back when the
connection returns — keeping **server truth**, the **outbox** of unconfirmed
changes, and the **draft** a user is typing as first-class, non-overlapping
primitives instead of conventions an app has to get right on its own.

- **Declarative schema** with additive, automatic migration.
- **Live queries**: plain SQL that re-runs only for the rows it actually reads.
- **Sync built in**: cursor-based pull, a column-level outbox, idempotent
  batched push. You supply a transport; the library never speaks HTTP itself.
- **React bindings** in `declarative-sqlite/react`.

Full docs, guides and the API reference live at
**[declarative-sqlite.linden.no](https://declarative-sqlite.linden.no/)**.

## Install

```bash
npm install declarative-sqlite
```

`react` (18+) is an optional peer dependency, only needed for
`declarative-sqlite/react`.

## Quick start

```ts
import { SchemaBuilder, openAdapter, Database } from 'declarative-sqlite';

const schema = new SchemaBuilder();
schema.table('note', (t) => {
  t.text('body').notNull('');
  t.date('created_at');
});

const { adapter } = await openAdapter({ name: 'notes.db' });
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

For a synced table, sync runtime, and React hooks, see
[Getting started](https://declarative-sqlite.linden.no/docs/getting-started).

## Where to go next

- [Introduction](https://declarative-sqlite.linden.no/docs/intro) — what it is, the three kinds of state, when it fits.
- [Getting started](https://declarative-sqlite.linden.no/docs/getting-started) — install, a local database, adding sync.
- [Sync](https://declarative-sqlite.linden.no/docs/sync) — pulling, the outbox, pushing, rejected changes.
- [Server protocol](https://declarative-sqlite.linden.no/docs/server-protocol) — what your backend needs to serve.
- [React](https://declarative-sqlite.linden.no/docs/react) — the provider and hooks.
- [Upgrading from v2](https://declarative-sqlite.linden.no/docs/upgrading-from-v2) — migration guide, or see [`MIGRATION-v2-to-v3.md`](./MIGRATION-v2-to-v3.md) in this package.
- [Changelog](./CHANGELOG.md)
