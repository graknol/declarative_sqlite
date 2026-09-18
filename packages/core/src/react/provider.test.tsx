/** @vitest-environment happy-dom */
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, waitFor, cleanup, fireEvent } from '@testing-library/react';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { FakeTransport } from '../testing/fake-transport';
import { createSyncRuntime, type SyncRuntime } from '../sync/runtime';
import { SyncProvider } from './provider';
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

describe('SyncProvider', () => {
  let db: Database | undefined;
  let sync: SyncRuntime | undefined;
  let consoleErrorSpy: { mockRestore: () => void } | undefined;

  afterEach(async () => {
    cleanup();
    sync?.close();
    if (db) {
      try {
        await db.close();
      } catch {
        // already closed by the test itself
      }
    }
    db = undefined;
    sync = undefined;
    consoleErrorSpy?.mockRestore();
    consoleErrorSpy = undefined;
  });

  it('does not produce an unhandled rejection when the database closes while an unmount-triggered draft flush is mid-flight', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, INTERNAL_REMARK: 'start' } }]);
    sync = await createSyncRuntime({ db, transport, deviceId: 'test' });
    await sync.pull.pull('c_work_task', { wo_no: 3188 });

    const consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    const { unmount } = render(
      <SyncProvider db={db} sync={sync}>
        <Remark systemId="A" value="start" />
      </SyncProvider>,
    );
    await waitFor(() => expect(screen.getByTestId('remark-A')).toBeDefined());

    const input = screen.getByTestId('remark-A') as HTMLInputElement;
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: 'changed while unmounting' } });

    // The exact race: unmount (which fires `sync.drafts.endAll()` from the
    // provider's effect cleanup, un-awaited) and `db.close()` happen in the
    // same synchronous stretch, before anything from the flush has a chance
    // to run — reproducing a page navigating away while a draft is open.
    unmount();
    const closePromise = db.close();

    await closePromise;
    // Give the still in-flight endAll()/endRow()/outbox.record() chain a
    // chance to settle. If provider.tsx does not catch its rejection, vitest
    // reports an unhandled rejection and fails this test run even though no
    // assertion below fails.
    await new Promise((resolve) => setTimeout(resolve, 20));

    expect(consoleErrorSpy).toHaveBeenCalledWith(
      expect.stringContaining('[declarative-sqlite]'),
      expect.objectContaining({ message: expect.stringContaining('closed') }),
    );

    consoleErrorSpy.mockRestore();
  });

  it('re-throws non-database-closure errors so they surface as unhandled rejections', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, INTERNAL_REMARK: 'start' } }]);
    sync = await createSyncRuntime({ db, transport, deviceId: 'test' });
    await sync.pull.pull('c_work_task', { wo_no: 3188 });

    consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    // Directly test endAll() behavior when an OutboxError occurs
    sync.drafts.begin('c_work_task', 'A', 'internal_remark', 'start');
    sync.drafts.set('c_work_task', 'A', 'internal_remark', 'changed');

    // Delete the row to trigger an OutboxError when endAll() tries to record the change
    await db.execute('DELETE FROM c_work_task WHERE system_id = ?', ['A']);

    // When the row no longer exists, endAll() should re-throw the OutboxError
    // rather than catching and logging it to console.error
    await expect(sync.drafts.endAll()).rejects.toThrow('row does not exist locally');

    // Verify console.error was NOT called — the error should have been re-thrown,
    // not caught and logged.
    expect(consoleErrorSpy).not.toHaveBeenCalled();
  });
});
