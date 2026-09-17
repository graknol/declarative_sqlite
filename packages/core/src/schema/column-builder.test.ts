import { describe, it, expect } from 'vitest';
import { ColumnBuilder } from './column-builder';

describe('ColumnBuilder', () => {
  it('builds a plain text column', () => {
    expect(new ColumnBuilder('part_no', 'TEXT', 'text').build()).toEqual({
      name: 'part_no', type: 'TEXT', logical: 'text', notNull: false,
    });
  });

  it('keeps notNull with its default and chains maxLength in either order', () => {
    const a = new ColumnBuilder('contract', 'TEXT', 'text').notNull('').maxLength(5).build();
    const b = new ColumnBuilder('contract', 'TEXT', 'text').maxLength(5).notNull('').build();
    expect(a).toEqual({ name: 'contract', type: 'TEXT', logical: 'text', notNull: true, defaultValue: '', maxLength: 5 });
    expect(b).toEqual(a);
  });

  it('stores a date as TEXT but remembers it is a date', () => {
    const col = new ColumnBuilder('planned_start', 'TEXT', 'date').build();
    expect(col.type).toBe('TEXT');
    expect(col.logical).toBe('date');
  });

  it('rejects a notNull default of the wrong shape', () => {
    expect(() => new ColumnBuilder('qty', 'REAL', 'real').notNull('nope' as never)).toThrow(/qty/);
  });

  it('rejects a non-positive maxLength', () => {
    expect(() => new ColumnBuilder('a', 'TEXT', 'text').maxLength(0)).toThrow(/maxLength/);
  });
});
