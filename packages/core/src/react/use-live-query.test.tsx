/** @vitest-environment happy-dom */
import { StrictMode } from 'react';
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, waitFor, cleanup } from '@testing-library/react';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { FakeTransport } from '../testing/fake-transport';
import { createSyncRuntime, type SyncRuntime } from '../sync/runtime';
import { SyncProvider } from './provider';
import { useLiveQuery, useLiveQueryState } from './use-live-query';

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

function TasksForOrder({ woNo }: { woNo: number }) {
  const rows = useLiveQuery<{ system_id: string; c_qty_installed: number }>({
    sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
    params: [woNo],
    reads: [{ table: 'c_work_task', scope: { wo_no: woNo } }],
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

function EmptyOrderTasks() {
  const state = useLiveQueryState<{ system_id: string; c_qty_installed: number }>({
    sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
    params: [3188],
    reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
    key: 'system_id',
  });
  return <div data-testid="status">{state.hasLoaded ? `loaded:${state.rows.length}` : 'loading'}</div>;
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

  it('still shows live data under <StrictMode>, which mounts, cleans up, and re-mounts effects', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }]);
    sync = await createSyncRuntime({ db, transport, deviceId: 'test' });
    await sync.pull.pull('c_work_task', { wo_no: 3188 });

    render(
      <StrictMode>
        <SyncProvider db={db} sync={sync}>
          <Tasks />
        </SyncProvider>
      </StrictMode>,
    );

    await waitFor(() => expect(screen.getByTestId('A').textContent).toBe('1'));
  });

  it('closes old query and creates new one when spec changes', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [
      { id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } },
      { id: 'B', data: { WO_NO: 3189, C_QTY_INSTALLED: 2 } },
    ]);
    sync = await createSyncRuntime({ db, transport, deviceId: 'test' });
    await sync.pull.pull('c_work_task', { wo_no: 3188 });
    await sync.pull.pull('c_work_task', { wo_no: 3189 });

    const { rerender: rerenderComponent } = render(
      <SyncProvider db={db} sync={sync}>
        <TasksForOrder woNo={3188} />
      </SyncProvider>,
    );

    await waitFor(() => expect(screen.getByTestId('A').textContent).toBe('1'));

    rerenderComponent(
      <SyncProvider db={db} sync={sync}>
        <TasksForOrder woNo={3189} />
      </SyncProvider>,
    );

    await waitFor(() => expect(screen.getByTestId('B').textContent).toBe('2'));
    expect(screen.queryByTestId('A')).toBeNull();
  });

  it('useLiveQueryState tells "not loaded yet" apart from "loaded and empty"', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    sync = await createSyncRuntime({ db, transport, deviceId: 'test' });
    // No seed and no pull: wo_no 3188 genuinely has no rows once the query runs.

    render(
      <SyncProvider db={db} sync={sync}>
        <EmptyOrderTasks />
      </SyncProvider>,
    );

    // Synchronously after mount, the query's first run has not resolved yet —
    // this is the state a bare `useLiveQuery() === []` cannot be told apart
    // from "loaded and empty".
    expect(screen.getByTestId('status').textContent).toBe('loading');

    await waitFor(() => expect(screen.getByTestId('status').textContent).toBe('loaded:0'));
  });
});
