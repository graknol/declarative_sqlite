---
title: Testing
description: "Test sync behaviour in memory with MemoryAdapter and FakeTransport."
---

# Testing

Everything in the library runs in memory against a real SQLite engine, so
sync behaviour can be tested with ordinary unit tests: no browser, no server.

- `MemoryAdapter`: an in-memory SQLite database. Works in Node.
- `FakeTransport`: a scripted server that follows the
  [server protocol](./server-protocol.md).

```ts
import { describe, it, expect } from 'vitest';
import { Database, MemoryAdapter, FakeTransport, createSyncRuntime } from 'declarative-sqlite';
import { appSchema } from '../src/schema';

describe('task sync', () => {
  it('keeps the user edit when another device changes the same row', async () => {
    const db = await Database.open({ schema: appSchema, adapter: new MemoryAdapter() });
    const server = new FakeTransport();
    server.seed('TASK', [{ id: 'A', data: { PROJECT_ID: 42, TITLE: 'Pump', HOURS: 1 } }]);

    const sync = await createSyncRuntime({ db, transport: server, deviceId: 'test', debounceMs: 0 });
    await sync.pull.pull('task', { project_id: 42 });

    await sync.outbox.record({ table: 'task', systemId: 'A', changes: { hours: 5 } });
    server.serverEdit('TASK', 'A', { TITLE: 'Pump (renamed)' });
    await sync.pull.pull('task', { project_id: 42 });

    const row = await db.tables.task.get('A');
    expect(row).toMatchObject({ hours: 5, title: 'Pump (renamed)' });

    await sync.push.pushNow();
    expect(await sync.outbox.counts()).toMatchObject({ pending: 0, rejected: 0 });

    sync.close();
    await db.close();
  });
});
```

Table and column names passed to `FakeTransport` are the uppercase wire
names.

## FakeTransport

| Method | Simulates |
|---|---|
| `seed(table, rows)` | Rows that already exist on the server. Each gets the next `seq` |
| `serverEdit(table, id, data)` | Another device changing a row |
| `tombstone(table, id)` | A row deleted on the server |
| `reject(table, column, error)` | The server refusing every change to that column |
| `failNextPush(error?)` | A network failure on the next push |
| `pushes`, `pulls` | Every batch and request received, for assertions |

`new FakeTransport({ pageSize: 2 })` forces small pages to test paging.

It behaves like a real server: changes apply in order with the last one
winning, replaying a `batchId` returns the stored answer, and a change to a
missing or deleted row is rejected.

## Tips

- Set `debounceMs: 0` or call `sync.push.pushNow()` so tests don't wait for
  the push timer.
- Pass `clock` to `createSyncRuntime` for deterministic timestamps.
- Close the runtime and the database at the end of each test.
