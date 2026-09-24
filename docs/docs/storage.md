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
