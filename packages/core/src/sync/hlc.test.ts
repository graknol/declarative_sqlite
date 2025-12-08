import { describe, it, expect, beforeEach } from 'vitest';
import { Hlc } from './hlc.js';

describe('Hlc', () => {
  let hlc: Hlc;

  beforeEach(() => {
    hlc = new Hlc('test-node');
  });

  describe('now', () => {
    it('should generate timestamps with increasing physical time', async () => {
      const ts1 = hlc.now();
      
      // Wait a bit to ensure physical time advances
      await new Promise(resolve => setTimeout(resolve, 5));
      
      const ts2 = hlc.now();

      expect(ts2.milliseconds).toBeGreaterThanOrEqual(ts1.milliseconds);
      expect(ts2.nodeId).toBe('test-node');
    });

    it('should increment counter when physical time does not advance', () => {
      const ts1 = hlc.now();
      const _ts2 = hlc.now();
      const ts3 = hlc.now();

      // At least one should have an incremented counter
      expect(ts3.counter).toBeGreaterThan(ts1.counter);
    });
  });

  describe('toString and parse', () => {
    it('should serialize and deserialize timestamps', () => {
      const original = hlc.now();
      const str = Hlc.toString(original);
      const parsed = Hlc.parse(str);

      expect(parsed.milliseconds).toBe(original.milliseconds);
      expect(parsed.counter).toBe(original.counter);
      expect(parsed.nodeId).toBe(original.nodeId);
    });

    it('should parse valid HLC string', () => {
      const parsed = Hlc.parse('1701878400000:5:node-abc');

      expect(parsed.milliseconds).toBe(1701878400000);
      expect(parsed.counter).toBe(5);
      expect(parsed.nodeId).toBe('node-abc');
    });

    it('should throw on invalid HLC string', () => {
      expect(() => Hlc.parse('invalid')).toThrow();
      expect(() => Hlc.parse('1234:abc:node')).toThrow();
    });
  });

  describe('compare', () => {
    it('should compare by milliseconds first', () => {
      const ts1 = { milliseconds: 1000, counter: 0, nodeId: 'a' };
      const ts2 = { milliseconds: 2000, counter: 0, nodeId: 'a' };

      expect(Hlc.compare(ts1, ts2)).toBe(-1);
      expect(Hlc.compare(ts2, ts1)).toBe(1);
    });

    it('should compare by counter if milliseconds equal', () => {
      const ts1 = { milliseconds: 1000, counter: 0, nodeId: 'a' };
      const ts2 = { milliseconds: 1000, counter: 5, nodeId: 'a' };

      expect(Hlc.compare(ts1, ts2)).toBe(-1);
      expect(Hlc.compare(ts2, ts1)).toBe(1);
    });

    it('should compare by nodeId if milliseconds and counter equal', () => {
      const ts1 = { milliseconds: 1000, counter: 0, nodeId: 'a' };
      const ts2 = { milliseconds: 1000, counter: 0, nodeId: 'b' };

      expect(Hlc.compare(ts1, ts2)).toBe(-1);
      expect(Hlc.compare(ts2, ts1)).toBe(1);
    });

    it('should return 0 for equal timestamps', () => {
      const ts1 = { milliseconds: 1000, counter: 5, nodeId: 'a' };
      const ts2 = { milliseconds: 1000, counter: 5, nodeId: 'a' };

      expect(Hlc.compare(ts1, ts2)).toBe(0);
    });
  });

  describe('isBefore and isAfter', () => {
    it('should correctly determine ordering', () => {
      const earlier = { milliseconds: 1000, counter: 0, nodeId: 'a' };
      const later = { milliseconds: 2000, counter: 0, nodeId: 'a' };

      expect(Hlc.isBefore(earlier, later)).toBe(true);
      expect(Hlc.isAfter(later, earlier)).toBe(true);
      expect(Hlc.isBefore(later, earlier)).toBe(false);
      expect(Hlc.isAfter(earlier, later)).toBe(false);
    });
  });

  describe('max', () => {
    it('should return the maximum timestamp', () => {
      const ts1 = { milliseconds: 1000, counter: 0, nodeId: 'a' };
      const ts2 = { milliseconds: 2000, counter: 0, nodeId: 'a' };

      expect(Hlc.max(ts1, ts2)).toBe(ts2);
      expect(Hlc.max(ts2, ts1)).toBe(ts2);
    });
  });

  describe('update', () => {
    it('should update local clock based on received timestamp', () => {
      const received = {
        milliseconds: Date.now() + 1000,
        counter: 5,
        nodeId: 'remote-node',
      };

      const updated = hlc.update(received);

      expect(updated.milliseconds).toBeGreaterThanOrEqual(received.milliseconds);
      expect(updated.nodeId).toBe('test-node');
    });
  });
});
