import { describe, it, expect } from 'vitest';
import { formatScope, parseScope, scopeKey, scopeMatches, validateScopes } from './scopes';
import { SchemaBuilder } from './schema-builder';

describe('scope helpers', () => {
  it('formats a scope the way the wire format spells it', () => {
    expect(formatScope({ wo_no: 3188 })).toBe('WO_NO:3188');
  });

  it('sorts several pairs so the cursor key is stable', () => {
    expect(formatScope({ lu_name: 'JtTask', key_ref: 'X' })).toBe('KEY_REF:X,LU_NAME:JtTask');
  });

  it('returns undefined for no scope', () => {
    expect(formatScope(undefined)).toBeUndefined();
  });

  it('rejects a value containing a comma', () => {
    expect(() => formatScope({ key_ref: 'A,B' })).toThrow(/comma/);
  });

  it('rejects an empty value and more than four pairs', () => {
    expect(() => formatScope({ key_ref: '  ' })).toThrow(/empty/);
    expect(() => formatScope({ a: 1, b: 2, c: 3, d: 4, e: 5 })).toThrow(/four/);
  });

  it('round-trips a value that itself contains a colon', () => {
    // Only the FIRST colon separates column from value, so an ISO timestamp
    // survives. Nothing rejects a colon on the way in, so nothing may lose it
    // on the way out.
    const written = formatScope({ changed_at: '2026-09-18T01:23:45Z' });
    expect(parseScope(written)).toEqual({ changed_at: '2026-09-18T01:23:45Z' });
  });

  it('accepts exactly four pairs', () => {
    const four = formatScope({ a: 1, b: 2, c: 3, d: 4 });
    expect(Object.keys(parseScope(four))).toHaveLength(4);
  });
  it('parses a scope back to lowercase columns', () => {
    expect(parseScope('WO_NO:3188')).toEqual({ wo_no: '3188' });
  });

  it('builds the cursor key', () => {
    expect(scopeKey('c_work_task', { wo_no: 3188 })).toBe('c_work_task|WO_NO:3188');
    expect(scopeKey('c_edm_file', undefined)).toBe('c_edm_file|*');
  });

  it('matches a written row against a query scope', () => {
    expect(scopeMatches({ wo_no: 3188 }, { wo_no: 3188 })).toBe(true);
    expect(scopeMatches({ wo_no: 4000 }, { wo_no: 3188 })).toBe(false);
    expect(scopeMatches(null, { wo_no: 3188 })).toBe(true); // unknown scope means "might match"
    expect(scopeMatches({ wo_no: 4000 }, undefined)).toBe(true); // query has no scope
  });
});

describe('validateScopes', () => {
  const schema = (() => {
    const s = new SchemaBuilder();
    s.table('c_work_task', (t) => {
      t.text('system_id');
      t.real('wo_no');
    }).synced({ key: 'system_id', scope: ['wo_no'] });
    return s.build();
  })();

  it('passes when every scope column is on the server allow-list', () => {
    expect(() => validateScopes(schema, { C_WORK_TASK: ['WO_NO'] })).not.toThrow();
  });

  it('throws naming the table and column when it is not', () => {
    expect(() => validateScopes(schema, { C_WORK_TASK: ['TASK_SEQ'] })).toThrow(/C_WORK_TASK.*WO_NO/);
  });
});
