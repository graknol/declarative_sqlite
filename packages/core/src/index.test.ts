import { describe, it, expect } from 'vitest';
import { VERSION } from './index';

describe('declarative-sqlite', () => {
  it('reports the v3 alpha version', () => {
    expect(VERSION).toBe('3.0.0-alpha.1');
  });
});
