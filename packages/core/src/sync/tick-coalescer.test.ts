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

  it('flush() pulls immediately without waiting for the window', async () => {
    const { pull, cursors } = fakes([{ wo_no: 3188 }]);
    const ticks = new TickCoalescer(pull, cursors, { windowMs: 5000 });
    ticks.notify({ table: 'c_work_task', seq: 10 });
    await ticks.flush();
    expect(pull.pull).toHaveBeenCalledTimes(1);
  });
});
