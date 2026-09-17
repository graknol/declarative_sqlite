import { describe, it, expect } from 'vitest';
import { FakeTransport } from './fake-transport';

describe('FakeTransport', () => {
  it('pages rows by cursor in seq order', async () => {
    const server = new FakeTransport({ pageSize: 2 });
    server.seed('C_WORK_TASK', [
      { id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } },
      { id: 'B', data: { WO_NO: 3188, C_QTY_INSTALLED: 2 } },
      { id: 'C', data: { WO_NO: 3188, C_QTY_INSTALLED: 3 } },
    ]);

    const first = await server.pullRows({ table: 'C_WORK_TASK', scope: 'WO_NO:3188', after: 0 });
    expect(first.rows.map((r) => r.id)).toEqual(['A', 'B']);
    expect(first.hasMore).toBe(true);

    const second = await server.pullRows({ table: 'C_WORK_TASK', scope: 'WO_NO:3188', after: first.next });
    expect(second.rows.map((r) => r.id)).toEqual(['C']);
    expect(second.hasMore).toBe(false);
  });

  it('filters by scope and reports tombstones with empty data', async () => {
    const server = new FakeTransport();
    server.seed('C_WORK_TASK', [
      { id: 'A', data: { WO_NO: 3188 } },
      { id: 'Z', data: { WO_NO: 4000 } },
    ]);
    server.tombstone('C_WORK_TASK', 'A');

    const page = await server.pullRows({ table: 'C_WORK_TASK', scope: 'WO_NO:3188', after: 0 });
    expect(page.rows).toHaveLength(1);
    expect(page.rows[0]).toMatchObject({ id: 'A', removed: true, data: {} });
  });

  it('applies a push in order and answers with the row as the batch left it', async () => {
    const server = new FakeTransport();
    server.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } }]);

    const answer = await server.push({
      batchId: 'b1',
      deviceId: 'ipad',
      changes: [
        { table: 'C_WORK_TASK', id: 'A', column: 'C_QTY_INSTALLED', old: 1, new: 10, changedAt: '2026-09-17T09:00:00Z' },
        { table: 'C_WORK_TASK', id: 'A', column: 'ROWSTATE', old: 'RELEASED', new: 'WORKSTARTED', changedAt: '2026-09-17T09:00:01Z' },
      ],
    });

    expect(answer.results).toEqual([
      { index: 0, result: 'applied', error: null },
      { index: 1, result: 'applied', error: null },
    ]);
    expect(answer.rows[0]?.data).toMatchObject({ C_QTY_INSTALLED: 10, ROWSTATE: 'WORKSTARTED' });
  });

  it('is idempotent on batch id', async () => {
    const server = new FakeTransport();
    server.seed('C_WORK_TASK', [{ id: 'A', data: { C_QTY_INSTALLED: 1 } }]);
    const batch = {
      batchId: 'b1', deviceId: 'ipad',
      changes: [{ table: 'C_WORK_TASK', id: 'A', column: 'C_QTY_INSTALLED', old: 1, new: 2, changedAt: 'x' }],
    };
    const first = await server.push(batch);
    server.serverEdit('C_WORK_TASK', 'A', { C_QTY_INSTALLED: 99 });
    const replay = await server.push(batch);
    expect(replay).toEqual(first);
    expect(server.pushes).toHaveLength(2);
  });

  it('answers CNOROW for an unknown row and rejects a configured column', async () => {
    const server = new FakeTransport();
    server.seed('C_WORK_TASK', [{ id: 'A', data: { C_QTY_INSTALLED: 1 } }]);
    server.reject('C_WORK_TASK', 'ROWSTATE', 'WTCERR2: Qty Installed can only be modified when the Work Task status is Work Started.');

    const answer = await server.push({
      batchId: 'b2', deviceId: 'ipad',
      changes: [
        { table: 'C_WORK_TASK', id: 'GONE', column: 'C_QTY_INSTALLED', old: 1, new: 2, changedAt: 'x' },
        { table: 'C_WORK_TASK', id: 'A', column: 'ROWSTATE', old: null, new: 'WORKSTARTED', changedAt: 'x' },
      ],
    });

    expect(answer.results[0]).toMatchObject({ result: 'rejected' });
    expect(answer.results[0]?.error).toContain('CNOROW');
    expect(answer.results[1]).toMatchObject({ result: 'rejected' });
  });

  it('answers noop when the value is already what the server holds', async () => {
    const server = new FakeTransport();
    server.seed('C_WORK_TASK', [{ id: 'A', data: { C_QTY_INSTALLED: 5 } }]);
    const answer = await server.push({
      batchId: 'b3', deviceId: 'ipad',
      changes: [{ table: 'C_WORK_TASK', id: 'A', column: 'C_QTY_INSTALLED', old: 5, new: 5, changedAt: 'x' }],
    });
    expect(answer.results[0]?.result).toBe('noop');
  });

  it('fails the next push when told to', async () => {
    const server = new FakeTransport();
    server.failNextPush();
    await expect(server.push({ batchId: 'b4', deviceId: 'ipad', changes: [] })).rejects.toThrow();
    await expect(server.push({ batchId: 'b4', deviceId: 'ipad', changes: [] })).resolves.toBeDefined();
  });
});
