import { describe, it, expect, beforeEach } from 'vitest';
import { Hlc, MockTimeProvider } from './hlc.js';

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
      const mockTime = new MockTimeProvider(1000);
      const hlc = new Hlc('test-node', mockTime);
      
      // Generate timestamps at the same physical time
      const ts1 = hlc.now();
      const ts2 = hlc.now();
      const ts3 = hlc.now();

      // All should have same milliseconds but incrementing counters
      expect(ts1.milliseconds).toBe(1000);
      expect(ts2.milliseconds).toBe(1000);
      expect(ts3.milliseconds).toBe(1000);
      
      expect(ts1.counter).toBe(0);
      expect(ts2.counter).toBe(1);
      expect(ts3.counter).toBe(2);
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
      const parsed = Hlc.parse('0000001701878400000:000000005:node-abc');

      expect(parsed.milliseconds).toBe(1701878400000);
      expect(parsed.counter).toBe(5);
      expect(parsed.nodeId).toBe('node-abc');
    });

    it('should throw on invalid HLC string', () => {
      expect(() => Hlc.parse('invalid')).toThrow();
      expect(() => Hlc.parse('1234:abc:node')).toThrow();
    });

    it('should automatically serialize when toString() is called', () => {
      const timestamp = hlc.now();
      const str = timestamp.toString();
      
      expect(str).toBe(Hlc.toString(timestamp));
      expect(str).toMatch(/^\d{19}:\d{9}:test-node$/);
    });

    it('should automatically serialize when String() is called', () => {
      const timestamp = hlc.now();
      const str = String(timestamp);
      
      expect(str).toBe(Hlc.toString(timestamp));
      expect(str).not.toBe('[object Object]');
      expect(str).toMatch(/^\d{19}:\d{9}:test-node$/);
    });

    it('should automatically serialize parsed timestamps', () => {
      const parsed = Hlc.parse('0000001701878400000:000000005:node-abc');
      const str = String(parsed);
      
      expect(str).toBe('0000001701878400000:000000005:node-abc');
      expect(str).not.toBe('[object Object]');
    });

    it('should use zero-padded format for proper string sorting', () => {
      const ts1 = hlc.now();
      const str1 = Hlc.toString(ts1);
      
      // Verify format has 19 digits for milliseconds and 9 digits for counter
      const parts = str1.split(':');
      expect(parts[0]!.length).toBe(19);
      expect(parts[1]!.length).toBe(9);
      expect(parts[0]).toMatch(/^\d{19}$/);
      expect(parts[1]).toMatch(/^\d{9}$/);
    });

    it('should maintain sort order with string comparison', () => {
      const ts1 = { milliseconds: 1000, counter: 0, nodeId: 'node1' };
      const ts2 = { milliseconds: 2000, counter: 0, nodeId: 'node2' };
      const ts3 = { milliseconds: 2000, counter: 5, nodeId: 'node3' };
      
      const str1 = Hlc.toString(ts1);
      const str2 = Hlc.toString(ts2);
      const str3 = Hlc.toString(ts3);
      
      // String comparison should match semantic comparison
      expect(str1 < str2).toBe(true);
      expect(str2 < str3).toBe(true);
      expect(str1 < str3).toBe(true);
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
