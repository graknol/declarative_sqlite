/** @vitest-environment happy-dom */
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, waitFor, cleanup } from '@testing-library/react';
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
