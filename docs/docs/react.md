---
title: React
description: "SyncProvider, useLiveQuery, useDraftField, useOutboxCounts and useSyncStatus."
---

# React

`declarative-sqlite/react` is a small layer over the core library. It holds no
state of its own: queries, drafts and the outbox live in the library, so a
component unmounting never loses anything.

Requires React 18 or later.

## Setup

Open the database and the sync runtime once, outside React, then provide
them:

```tsx
import { SyncProvider } from 'declarative-sqlite/react';

const db = await Database.open<Rows, 'task'>({ schema, adapter });
const sync = await createSyncRuntime({ db, transport, deviceId });

root.render(
  <SyncProvider db={db} sync={sync} routeKey={location.pathname}>
    <App />
  </SyncProvider>,
);
```

`SyncProvider` ends every open draft (saving what the user typed) when the
page is hidden (`pagehide`, or `visibilitychange` to hidden), when the provider
unmounts, and when `routeKey` changes. Pass something that changes on
navigation, such as the router's pathname.

`useDatabase()` and `useSyncRuntime()` return the two objects anywhere below
the provider.

## useLiveQuery

```tsx
import { useLiveQuery } from 'declarative-sqlite/react';

function TaskList({ projectId }: { projectId: number }) {
  const tasks = useLiveQuery<Rows['task']>({
    sql: 'SELECT * FROM task WHERE project_id = ? ORDER BY title',
    params: [projectId],
    reads: [{ table: 'task', scope: { project_id: projectId } }],
    key: 'system_id',
  });
  return <ul>{tasks.map((t) => <TaskRow key={t.system_id} task={t} />)}</ul>;
}
```

The query is created when the component mounts, closed when it unmounts, and
recreated only when the SQL, params, `reads` or `key` change. You can pass a
new object literal on every render. Unchanged rows keep their identity, so
`React.memo` on the row component works.

To tell "loading" from "empty", use `useLiveQueryState`:

```tsx
const { rows, hasLoaded } = useLiveQueryState<Rows['task']>(spec);
if (!hasLoaded) return <Spinner />;
if (rows.length === 0) return <p>No tasks</p>;
```

## useDraftField

This is how you bind an input to a column of a synced row:

```tsx
import { useDraftField } from 'declarative-sqlite/react';

function TitleInput({ task }: { task: Rows['task'] }) {
  const field = useDraftField('task', task.system_id, 'title', task.title);
  return (
    <input
      value={field.value}
      onFocus={field.onFocus}
      onChange={field.onChange}
      onBlur={field.onBlur}
      onKeyDown={field.onKeyDown}
      className={field.isPending ? 'unsynced' : undefined}
    />
  );
}
```

- Pass the value from your live query as the last argument.
- **Focus** starts a draft. Each **keystroke** updates it. While the draft is
  open, pulls can't change the field.
- **Blur** or **Enter** ends it: a changed value is recorded in the outbox; an
  unchanged one is released, and any server value that arrived meanwhile is
  applied.
- **Escape** reverts to the value at focus and releases the field.
- `isDrafting` is true while editing; `isPending` is true while the column has
  an unconfirmed outbox entry.

Don't keep a `useState` copy of the value next to it. The draft lives in the
library so it survives the row re-rendering or unmounting (for example in a
virtualised list).

### Non-text values

Passed a change event, `onChange` stores `event.target.value`, which is a
string. For a numeric column, convert it yourself, or the value is recorded as
a string:

```tsx
const field = useDraftField('task', task.system_id, 'hours', task.hours);

<input
  type="number"
  value={field.value ?? ''}
  onFocus={field.onFocus}
  onChange={(e) => field.onChange(e.target.value === '' ? null : Number(e.target.value))}
  onBlur={field.onBlur}
  onKeyDown={field.onKeyDown}
/>
```

`onChange` also accepts the value directly, which suits checkboxes, selects
and custom controls.

## useOutboxCounts and useSyncStatus

```tsx
import { useOutboxCounts, useSyncStatus } from 'declarative-sqlite/react';

function SyncBadge() {
  const { pending, sending, rejected } = useOutboxCounts();
  const status = useSyncStatus(); // { online, sending, attempt, nextRetryAt, lastError }

  if (!status.online) return <span>Offline · {pending} waiting</span>;
  if (rejected > 0) return <span>{rejected} change(s) refused</span>;
  return <span>{pending + sending === 0 ? 'Saved' : 'Saving…'}</span>;
}
```

## Registering visible scopes

For [change notifications](./sync.md#change-notifications-ticks) to pull the
right data, register the scopes a screen shows:

```tsx
function ProjectScreen({ projectId }: { projectId: number }) {
  const sync = useSyncRuntime();
  useEffect(() => {
    void sync.pull.pull('task', { project_id: projectId });
    return sync.pull.registerScope('task', { project_id: projectId });
  }, [sync, projectId]);
  // …
}
```
