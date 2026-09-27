---
title: Storage
description: "Choose where the database lives: OPFS, IndexedDB or memory, via openAdapter."
---

# Storage

The database runs on the official SQLite WebAssembly build. Where the bytes
are kept is decided by an **adapter**.

## openAdapter

`openAdapter` picks the best storage the browser can actually give you:

```ts
import { openAdapter } from 'declarative-sqlite';

const { adapter, backend, warnings } = await openAdapter({ name: 'app.db' });
```

It tries these in order:

| Backend | When | Persists across reloads |
|---|---|---|
| `opfs` | The browser supports OPFS sync access handles: Chrome/Edge 108+, Firefox 111+, Safari 17+ | Yes |
| `indexeddb` | OPFS is missing or fails to open (e.g. Safari 16) | Yes, with a caveat (below) |
| `memory` | Neither works, e.g. storage is blocked in a private window | **No** |

`backend` says where it landed. `warnings` explains every fallback. When the
result is `memory`, it includes "Storage is not persistent", so show the user
something, since everything they do will be lost on reload.

### Options

| Option | Default | Meaning |
|---|---|---|
| `name` | required | Database file name |
| `backend` | `'auto'` | Force `'opfs'`, `'indexeddb'` or `'memory'`. Skips detection, and throws instead of falling back |
| `wasmDir` | – | Folder `sqlite3.wasm` is served from, if not the default location |
| `opfsTimeoutMs` | `5000` | How long to wait for OPFS before falling back. Some browsers that report OPFS support hang on the first open |
| `opfs` | – | `{ poolName?, initialCapacity?, minimumCapacity? }` for the OPFS backend, see [The OPFS pool](#the-opfs-pool) |

## The OPFS pool

The OPFS adapter uses SQLite's SAH-pool VFS. The pool lives in the OPFS
directory `.<poolName>` (default `.declarative-sqlite`) and keeps every file
in one of a fixed number of pre-allocated slots with a random file name. Each
database takes a slot, and so does its rollback journal while a write
transaction runs. The pool needs `createSyncAccessHandle`, which browsers
expose only in dedicated workers, so open OPFS databases in a worker.

| `OpfsAdapter` option | Default | Meaning |
|---|---|---|
| `poolName` | `'declarative-sqlite'` | Pool (VFS) name and directory |
| `initialCapacity` | `6` | Slots when the pool is created for the first time on this origin. Ignored for an existing pool |
| `minimumCapacity` | – | The pool grows to at least this many slots, and `open()` fails if it cannot. It never shrinks |

Whatever you pass, `open()` also tries to grow the pool to `fileCount + 2`
slots: room for one more database and one journal. That is best effort. If
OPFS refuses (quota), it logs a warning and still opens an existing database.
It does not cover the temporary journal slots of several databases writing at
the same time, so size `minimumCapacity` for the databases you keep open.

```ts
const adapter = new OpfsAdapter('user-42.db', { minimumCapacity: 16 });
// or: openAdapter({ name: 'user-42.db', opfs: { minimumCapacity: 16 } })
await adapter.open();
adapter.poolInfo(); // { capacity: 16, fileCount: 1, fileNames: ['/user-42.db'] }
```

### Deleting a database

Because the files have random names, deleting `user-42.db` at the OPFS root
does nothing, and the slot stays taken. Delete through the pool:

```ts
await adapter.deleteDatabase();               // this adapter's own: closes it, then deletes
await adapter.deleteDatabase('user-17.db');   // another database in the same pool
await OpfsAdapter.deleteDatabase('user-17.db', { wasmDir: '/assets' }); // no adapter open
```

Each unlinks the database and its `-journal`, `-wal` and `-shm` names, frees
their slots, and resolves `true` if the database existed. Deleting a database
that another `OpfsAdapter` in the same tab or worker has open throws; close
that adapter first. Call it from the context that owns the database (below).

**Shared devices.** When several people sign in on one device and each gets
their own database, delete the previous user's database on sign-out (or
remove old ones on sign-in), and set `minimumCapacity` to cover the
databases you keep. Otherwise each user who ever signed in keeps a slot, and
once the pool is full, opening a new database fails with "SAH pool is full".

**One holder per origin.** The pool holds exclusive access handles on all
its slots, so only one tab or worker per origin can have it at a time. Call
`deleteDatabase` from the context that owns the databases, typically your
database worker, not from the UI thread.

- If another context holds the pool, `OpfsAdapter.deleteDatabase` rejects
  with an error whose `cause` is the browser's `NoModificationAllowedError`.
  The library deletes nothing. sqlite-wasm's own cleanup of the failed
  install, a recursive delete of the pool directory, still runs, and only
  the browser's OPFS locks on the holder's files stop it. That is checked in
  Chromium. sqlite-wasm caches the failure, so a retry from the same context
  rejects the same way.
- When `OpfsAdapter.deleteDatabase` had to install the pool and nothing is
  open through it afterwards, it pauses the pool, which releases its handles
  (`pauseVfs`, sqlite-wasm 3.50+). The next `open()` resumes it. With an
  older sqlite-wasm, the pool stays held by the context that called it until
  that context ends, and your database worker cannot open it meanwhile.

## The IndexedDB caveat

SQLite's WebAssembly build has no IndexedDB file system, so the IndexedDB
adapter keeps the database in memory and saves a full copy of it to IndexedDB
about 250 ms after writes stop. That means:

- A crash or killed tab can lose writes from the last ~250 ms.
- Each save copies the whole database, so it gets slower as the data grows.

Call `flush()` when the page is being hidden to close that window:

```ts
import { IndexedDbAdapter } from 'declarative-sqlite';

window.addEventListener('pagehide', () => {
  if (adapter instanceof IndexedDbAdapter) void adapter.flush();
});
```

Prefer OPFS whenever it's available; `openAdapter` already does.

## Using an adapter directly

The adapter classes are exported if you want to skip detection:

```ts
import { OpfsAdapter, IndexedDbAdapter, MemoryAdapter } from 'declarative-sqlite';

const adapter = new OpfsAdapter('app.db');
const test = new MemoryAdapter(); // in-process SQLite, used for tests and Node
```

`MemoryAdapter` works in Node as well as the browser, which makes it the
adapter to use in unit tests (see [Testing](./testing.md)).

You can also write your own adapter, for example over a native SQLite bridge,
by implementing the `SQLiteAdapter` interface: `open`, `close`, `exec`, `all`,
`get`, `run`, `isOpen` and `export`.

## Exporting the database

Every built-in adapter can serialise the whole database, which is handy for
support tickets and debugging:

```ts
const bytes: Uint8Array = await adapter.export();
```
