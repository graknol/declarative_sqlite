import { describe, it, expect } from 'vitest';
import { SchemaBuilder } from '../schema/schema-builder';
import {
  assertScalarFits, decodeScalar, encodeScalar, fromWireData, MAX_BATCH_ID_CHARS,
  newBatchId, toWireColumn, toWireTable, ValueTooLongError,
} from './wire';

const taskTable = (() => {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
    t.date('planned_start');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build().tables[0]!;
})();

describe('wire helpers', () => {
  it('encodes scalars as JSON and decodes them back', () => {
    expect(encodeScalar(10)).toBe('10');
    expect(encodeScalar('WORKSTARTED')).toBe('"WORKSTARTED"');
    expect(encodeScalar(null)).toBe('null');
    expect(encodeScalar(undefined)).toBe('null');
    expect(encodeScalar(true)).toBe('true');
    expect(decodeScalar('10')).toBe(10);
    expect(decodeScalar('"WORKSTARTED"')).toBe('WORKSTARTED');
    expect(decodeScalar(null)).toBeNull();
  });

  it('refuses a scalar the server column cannot hold', () => {
    const long = encodeScalar('x'.repeat(4100));
    expect(() => assertScalarFits('c_work_task', 'internal_remark', long)).toThrow(ValueTooLongError);
    expect(() => assertScalarFits('c_work_task', 'internal_remark', encodeScalar('ok'))).not.toThrow();
  });

  it('mints a batch id that fits the server column', () => {
    const id = newBatchId();
    expect(id.length).toBeLessThanOrEqual(MAX_BATCH_ID_CHARS);
    expect(newBatchId()).not.toBe(id);
  });

  it('falls back to getRandomValues when randomUUID is missing', () => {
    const originalCrypto = globalThis.crypto;
    try {
      const getRandomValues = originalCrypto.getRandomValues.bind(originalCrypto);
      Object.defineProperty(globalThis, 'crypto', {
        value: { getRandomValues },
        configurable: true,
      });
      const id = newBatchId();
      expect(id.length).toBe(36);
      expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
      expect(newBatchId()).not.toBe(id);
    } finally {
      Object.defineProperty(globalThis, 'crypto', {
        value: originalCrypto,
        configurable: true,
      });
    }
  });

  it('falls back to Math.random when crypto is absent', () => {
    const originalCrypto = globalThis.crypto;
    try {
      Object.defineProperty(globalThis, 'crypto', {
        value: undefined,
        configurable: true,
      });
      const id = newBatchId();
      expect(id.length).toBe(36);
      expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
      expect(newBatchId()).not.toBe(id);
    } finally {
      Object.defineProperty(globalThis, 'crypto', {
        value: originalCrypto,
        configurable: true,
      });
    }
  });

  it('uppercases table and column names for the wire', () => {
    expect(toWireTable('c_work_task')).toBe('C_WORK_TASK');
    expect(toWireColumn('c_qty_installed')).toBe('C_QTY_INSTALLED');
  });

  it('lowercases wire data and drops columns the schema does not declare', () => {
    const row = fromWireData(taskTable, { WO_NO: 3188, C_QTY_INSTALLED: 10, ROWSTATE: 'WORKSTARTED', UNKNOWN_COL: 'x' });
    expect(row).toEqual({ wo_no: 3188, c_qty_installed: 10, rowstate: 'WORKSTARTED' });
  });

  it('coerces booleans and keeps ISO date strings as text', () => {
    const row = fromWireData(taskTable, { PLANNED_START: '2026-09-17T06:00:00Z', ROWSTATE: null });
    expect(row).toEqual({ planned_start: '2026-09-17T06:00:00Z', rowstate: null });
  });
});
