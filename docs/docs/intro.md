---
slug: /intro
title: Introduction
description: "What declarative-sqlite is, the three kinds of state it keeps apart, and what it does not do."
---

# declarative-sqlite

declarative-sqlite is a TypeScript library for apps that must keep working
without a network. It runs real SQLite in the browser (WebAssembly, stored in
OPFS where available), keeps a local copy of server data, lets the user edit it
offline, and syncs the edits back when the connection returns.

:::note Version
These docs cover **v3**, currently published as an alpha:
`npm install declarative-sqlite@alpha`. v3 is a rewrite; see
[Upgrading from v2](./upgrading-from-v2.md) if you have an existing app.
:::

## What you get

- **A declarative schema.** Describe tables in code. `Database.open` compares
  the schema with the database on disk and migrates it. Migrations only add
  tables, columns and indexes; they never drop anything.
- **Live queries.** Write plain SQL, declare which tables (and which slice of
  them) it reads, and subscribe. The query re-runs only when a committed write
  touches what it declared, and it emits only when its rows actually changed.
- **Sync.** Pull server rows page by page from a cursor, record local edits in
  an outbox, and push them in batches the server can apply idempotently. You
  supply two functions that talk to your API; the library never makes HTTP
  calls itself.
- **React bindings** in `declarative-sqlite/react`: `useLiveQuery`,
  `useDraftField`, `useOutboxCounts`, `useSyncStatus`.

## The three kinds of state

An offline-first app has three sources of truth for any value on screen. The
library keeps them apart:

| State | Where it lives | Who changes it |
|---|---|---|
| **Server truth** | Tables marked `.synced()` | Only the sync layer: pulls, and the local write done by `outbox.record` |
| **Outbox** | The library's own `outbox` table | `sync.outbox.record(...)`; entries settle when the server answers |
| **Draft** | Memory, keyed by table, row and column | An input the user is typing in (`useDraftField`) |

When a row is read through a live query, pending outbox values are laid over
the server value, and a column someone is typing in is held at the draft
value. A pull that arrives in the meantime can't overwrite either one.

## When it fits

- Browser apps, PWAs and web views that must work offline for long periods.
- A backend you control, or can put an adapter in front of, that can serve rows
  by sequence number and accept column-level changes. The
  [server protocol](./server-protocol.md) page lists exactly what it must do.

## What it does not do

- **Create or delete synced rows from the client.** The push format carries
  column changes to rows that already exist. New server rows and deletions
  arrive by pulling. Tables you don't sync (`db.tables.<name>`) have full
  insert, update and delete.
- **Merge conflicts.** The server decides: the last change to arrive wins, per
  column. Anything the server refuses comes back as a `rejected` outbox entry
  for the app to show.
- **Talk to the network.** You write the transport, so you own auth, URLs and
  headers.
- **Store files.** Keep blobs in your own storage and reference them from rows.

## Layout of the package

```
declarative-sqlite          schema, migration, adapters, Database, live queries, sync
declarative-sqlite/react    SyncProvider and hooks (react is an optional peer dependency)
```

Next: [Getting started](./getting-started.md).
