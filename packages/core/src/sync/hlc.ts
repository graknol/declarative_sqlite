/**
 * Hybrid Logical Clock (HLC) Implementation
 * 
 * HLC provides distributed timestamps that combine physical time with logical counters
 * for conflict-free ordering of events in distributed systems.
 * 
 * Format: <milliseconds>:<counter>:<nodeId>
 * Example: "1701878400000:0:node-abc123"
 */

export interface HlcTimestamp {
  milliseconds: number;
  counter: number;
  nodeId: string;
}

export class Hlc {
  private lastMilliseconds: number = 0;
  private counter: number = 0;

  constructor(private nodeId: string) {
    if (!nodeId || nodeId.length === 0) {
      throw new Error('HLC requires a non-empty nodeId');
    }
  }

  /**
   * Generate a new HLC timestamp
   */
  now(): HlcTimestamp {
    const physicalTime = Date.now();

    if (physicalTime > this.lastMilliseconds) {
      // Physical time advanced, reset counter
      this.lastMilliseconds = physicalTime;
      this.counter = 0;
    } else {
      // Physical time hasn't advanced, increment counter
      this.counter++;
    }

    return this.createTimestamp(
      this.lastMilliseconds,
      this.counter,
      this.nodeId
    );
  }

  /**
   * Update HLC based on received timestamp (for clock synchronization)
   */
  update(received: HlcTimestamp): HlcTimestamp {
    const physicalTime = Date.now();
    const maxMilliseconds = Math.max(physicalTime, this.lastMilliseconds, received.milliseconds);

    if (maxMilliseconds === this.lastMilliseconds && maxMilliseconds === received.milliseconds) {
      // Both clocks at same time, use max counter + 1
      this.counter = Math.max(this.counter, received.counter) + 1;
    } else if (maxMilliseconds === this.lastMilliseconds) {
      // Our clock is ahead
      this.counter++;
    } else if (maxMilliseconds === received.milliseconds) {
      // Received clock is ahead
      this.counter = received.counter + 1;
    } else {
      // Physical time advanced beyond both
      this.counter = 0;
    }

    this.lastMilliseconds = maxMilliseconds;

    return this.createTimestamp(
      this.lastMilliseconds,
      this.counter,
      this.nodeId
    );
  }

  /**
   * Create an HLC timestamp with automatic serialization support
   */
  private createTimestamp(
    milliseconds: number,
    counter: number,
    nodeId: string
  ): HlcTimestamp {
    const timestamp: HlcTimestamp = {
      milliseconds,
      counter,
      nodeId,
    };

    // Add toString() method for automatic serialization
    Object.defineProperty(timestamp, 'toString', {
      value: () => Hlc.toString(timestamp),
      enumerable: false,
    });

    return timestamp;
  }

  /**
   * Serialize HLC timestamp to string
   */
  static toString(timestamp: HlcTimestamp): string {
    return `${timestamp.milliseconds}:${timestamp.counter}:${timestamp.nodeId}`;
  }

  /**
   * Parse HLC timestamp from string
   */
  static parse(hlcString: string): HlcTimestamp {
    const parts = hlcString.split(':');
    if (parts.length !== 3) {
      throw new Error(`Invalid HLC format: ${hlcString}. Expected format: milliseconds:counter:nodeId`);
    }

    const milliseconds = parseInt(parts[0]!, 10);
    const counter = parseInt(parts[1]!, 10);
    const nodeId = parts[2]!;

    if (isNaN(milliseconds) || isNaN(counter)) {
      throw new Error(`Invalid HLC format: ${hlcString}. milliseconds and counter must be numbers`);
    }

    const timestamp: HlcTimestamp = { milliseconds, counter, nodeId };

    // Add toString() method for automatic serialization
    Object.defineProperty(timestamp, 'toString', {
      value: () => Hlc.toString(timestamp),
      enumerable: false,
    });

    return timestamp;
  }

  /**
   * Compare two HLC timestamps
   * Returns: -1 if a < b, 0 if a === b, 1 if a > b
   */
  static compare(a: HlcTimestamp, b: HlcTimestamp): number {
    // First compare milliseconds
    if (a.milliseconds < b.milliseconds) return -1;
    if (a.milliseconds > b.milliseconds) return 1;

    // Then compare counter
    if (a.counter < b.counter) return -1;
    if (a.counter > b.counter) return 1;

    // Then compare nodeId (for deterministic ordering)
    if (a.nodeId < b.nodeId) return -1;
    if (a.nodeId > b.nodeId) return 1;

    return 0;
  }

  /**
   * Check if timestamp a is before timestamp b
   */
  static isBefore(a: HlcTimestamp, b: HlcTimestamp): boolean {
    return this.compare(a, b) < 0;
  }

  /**
   * Check if timestamp a is after timestamp b
   */
  static isAfter(a: HlcTimestamp, b: HlcTimestamp): boolean {
    return this.compare(a, b) > 0;
  }

  /**
   * Get the maximum of two timestamps
   */
  static max(a: HlcTimestamp, b: HlcTimestamp): HlcTimestamp {
    return this.compare(a, b) >= 0 ? a : b;
  }
}
