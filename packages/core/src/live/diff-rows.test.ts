import { describe, it, expect } from 'vitest';
import { diffRows } from './diff-rows';

describe('diffRows', () => {
  it('reports no change and returns the previous array for an identical result', () => {
    const previous = [{ system_id: 'A', qty: 1 }];
    const next = [{ system_id: 'A', qty: 1 }];
    const result = diffRows(previous, next, 'system_id');
    expect(result.changed).toBe(false);
    expect(result.rows).toBe(previous);
  });

  it('keeps the identity of rows that did not change', () => {
    const a = { system_id: 'A', qty: 1 };
    const b = { system_id: 'B', qty: 2 };
    const result = diffRows([a, b], [{ system_id: 'A', qty: 1 }, { system_id: 'B', qty: 3 }], 'system_id');
    expect(result.changed).toBe(true);
    expect(result.rows[0]).toBe(a);
    expect(result.rows[1]).not.toBe(b);
    expect(result.rows[1]).toEqual({ system_id: 'B', qty: 3 });
  });

  it('detects a new row, a removed row and a reorder', () => {
    const a = { system_id: 'A' };
    const b = { system_id: 'B' };
    expect(diffRows([a], [a, b], 'system_id').changed).toBe(true);
    expect(diffRows([a, b], [a], 'system_id').changed).toBe(true);
    expect(diffRows([a, b], [{ system_id: 'B' }, { system_id: 'A' }], 'system_id').changed).toBe(true);
  });

  it('treats a null and a missing column as different values', () => {
    expect(diffRows([{ system_id: 'A', qty: null }], [{ system_id: 'A' }], 'system_id').changed).toBe(true);
  });

  it('handles duplicate keys by position', () => {
    const rows = [{ system_id: 'A', n: 1 }, { system_id: 'A', n: 2 }];
    expect(diffRows(rows, [{ system_id: 'A', n: 1 }, { system_id: 'A', n: 2 }], 'system_id').changed).toBe(false);
  });
});
