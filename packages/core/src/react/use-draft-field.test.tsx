/** @vitest-environment happy-dom */
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, waitFor, cleanup, fireEvent } from '@testing-library/react';
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
    // Some tests (e.g. the one below that checks a draft survives a pull)
    // deliberately leave a draft open. `cleanup()` unmounts <SyncProvider>,
    // whose own effect cleanup ends every open draft by calling
    // `sync.drafts.endAll()` without awaiting it, so that write can still be
    // in flight when `db.close()` runs right after — a race, unrelated to
    // this hook, in code this task does not own. Ending drafts explicitly
    // here, while the database is still open, settles them deterministically
    // before teardown instead of leaving that write to race the close.
    await sync?.drafts.endAll();
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
    await setup();
    const input = screen.getByTestId('remark-A') as HTMLInputElement;
    fireEvent.focus(input);
    fireEvent.blur(input);
    expect(await db!.query('SELECT id FROM outbox')).toEqual([]);
  });
});
