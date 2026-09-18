import { describe, it, expect, vi } from 'vitest';
import { TickCoalescer } from './tick-coalescer';
import type { PullService } from './pull-service';
import type { CursorStore } from './cursor-store';

function fakes(openScopes: Array<Record<string, string | number> | undefined>, cursor = 0) {
  const pull = { pull: vi.fn().mockResolvedValue({ rows: 0, pages: 1, cursor: 0 }), openScopes: () => openScopes } as unknown as PullService;
  const cursors = { get: vi.fn().mockResolvedValue(cursor) } as unknown as CursorStore;
  return { pull, cursors };
}

describe('TickCoalescer', () => {
  it('collects ticks for the window and then pulls once per open scope', async () => {
    vi.useFakeTimers();
    try {
      const { pull, cursors } = fakes([{ wo_no: 3188 }, { wo_no: 4000 }]);
      const ticks = new TickCoalescer(pull, cursors, { windowMs: 1500 });
      ticks.notify({ table: 'c_work_task', seq: 10 });
      ticks.notify({ table: 'c_work_task', seq: 11 });
      await vi.advanceTimersByTimeAsync(1400);
      expect(pull.pull).not.toHaveBeenCalled();

      await vi.advanceTimersByTimeAsync(200);
      expect(pull.pull).toHaveBeenCalledTimes(2);
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 3188 }, { from: 'window' });
    } finally {
      vi.useRealTimers();
    }
  });

  it('skips a scope whose cursor is already at or past the tick seq', async () => {
    vi.useFakeTimers();
    try {
      const { pull, cursors } = fakes([{ wo_no: 3188 }], 50);
      const ticks = new TickCoalescer(pull, cursors, { windowMs: 10 });
      ticks.notify({ table: 'c_work_task', seq: 50 });
      await vi.advanceTimersByTimeAsync(20);
      expect(pull.pull).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });

  it('pulls only the scopes the tick lists when it lists any', async () => {
    vi.useFakeTimers();
    try {
      const { pull, cursors } = fakes([{ wo_no: 3188 }, { wo_no: 4000 }]);
      const ticks = new TickCoalescer(pull, cursors, { windowMs: 10 });
      ticks.notify({ table: 'c_work_task', seq: 10, scopes: [4000] });
      await vi.advanceTimersByTimeAsync(20);
      expect(pull.pull).toHaveBeenCalledTimes(1);
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 4000 }, { from: 'window' });
    } finally {
      vi.useRealTimers();
    }
  });

  it('merges two scoped ticks into the union of their scopes instead of dropping either', async () => {
    vi.useFakeTimers();
    try {
      const { pull, cursors } = fakes([{ wo_no: 3188 }, { wo_no: 4000 }, { wo_no: 5000 }]);
      const ticks = new TickCoalescer(pull, cursors, { windowMs: 10 });
      ticks.notify({ table: 'c_work_task', seq: 10, scopes: [3188] });
      ticks.notify({ table: 'c_work_task', seq: 20, scopes: [4000] });
      await vi.advanceTimersByTimeAsync(20);
      expect(pull.pull).toHaveBeenCalledTimes(2);
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 3188 }, { from: 'window' });
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 4000 }, { from: 'window' });
    } finally {
      vi.useRealTimers();
    }
  });

  it('does not let a later scoped tick narrow away an earlier table-wide tick', async () => {
    vi.useFakeTimers();
    try {
      const { pull, cursors } = fakes([{ wo_no: 3188 }, { wo_no: 4000 }]);
      const ticks = new TickCoalescer(pull, cursors, { windowMs: 10 });
      ticks.notify({ table: 'c_work_task', seq: 10 });
      ticks.notify({ table: 'c_work_task', seq: 20, scopes: [4000] });
      await vi.advanceTimersByTimeAsync(20);
      expect(pull.pull).toHaveBeenCalledTimes(2);
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 3188 }, { from: 'window' });
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 4000 }, { from: 'window' });
    } finally {
      vi.useRealTimers();
    }
  });

  it('lets a later table-wide tick widen an earlier scoped tick', async () => {
    vi.useFakeTimers();
    try {
      const { pull, cursors } = fakes([{ wo_no: 3188 }, { wo_no: 4000 }]);
      const ticks = new TickCoalescer(pull, cursors, { windowMs: 10 });
      ticks.notify({ table: 'c_work_task', seq: 10, scopes: [4000] });
      ticks.notify({ table: 'c_work_task', seq: 20 });
      await vi.advanceTimersByTimeAsync(20);
      expect(pull.pull).toHaveBeenCalledTimes(2);
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 3188 }, { from: 'window' });
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 4000 }, { from: 'window' });
    } finally {
      vi.useRealTimers();
    }
  });

  it('flush() pulls immediately without waiting for the window', async () => {
    const { pull, cursors } = fakes([{ wo_no: 3188 }]);
    const ticks = new TickCoalescer(pull, cursors, { windowMs: 5000 });
    ticks.notify({ table: 'c_work_task', seq: 10 });
    await ticks.flush();
    expect(pull.pull).toHaveBeenCalledTimes(1);
  });

  it('prevents further pulls after stop() is called during flush', async () => {
    vi.useFakeTimers();
    try {
      let releasePull: (() => void) | undefined;
      const pullBlocker = new Promise<{ rows: number; pages: number; cursor: number }>((resolve) => {
        releasePull = () => resolve({ rows: 0, pages: 1, cursor: 0 });
      });

      const pull = {
        pull: vi.fn().mockReturnValue(pullBlocker),
        openScopes: () => [{ wo_no: 3188 }, { wo_no: 4000 }],
      } as unknown as PullService;
      const cursors = { get: vi.fn().mockResolvedValue(0) } as unknown as CursorStore;

      const ticks = new TickCoalescer(pull, cursors, { windowMs: 10000 });
      ticks.notify({ table: 'c_work_task', seq: 10 });

      // Start flush directly (don't wait for timer) so pendingTicks still has the tick
      const flushPromise = ticks.flush();

      // Let the event loop process - first pull starts but blocks
      await vi.advanceTimersByTimeAsync(0);

      // Call stop() while first pull is pending
      ticks.stop();

      // Release the blocked pull
      if (releasePull) {
        releasePull();
      }

      // Await flush to complete
      await flushPromise;

      // Verify pull was called exactly once (second scope never pulled)
      expect(pull.pull).toHaveBeenCalledTimes(1);
      expect(pull.pull).toHaveBeenCalledWith('c_work_task', { wo_no: 3188 }, { from: 'window' });
    } finally {
      vi.useRealTimers();
    }
  });
});
