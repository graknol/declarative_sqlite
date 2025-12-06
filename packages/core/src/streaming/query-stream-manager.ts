import { StreamingQuery } from './streaming-query';

/**
 * QueryStreamManager manages all active streaming queries and
 * triggers refreshes when data changes.
 */
export class QueryStreamManager {
  private streams = new Map<string, StreamingQuery<any>>();
  private streamCounter = 0;
  
  /**
   * Register a new streaming query
   */
  registerStream<T>(stream: StreamingQuery<T>): string {
    const id = `stream_${++this.streamCounter}`;
    this.streams.set(id, stream);
    return id;
  }
  
  /**
   * Unregister a streaming query
   */
  unregisterStream(id: string): void {
    const stream = this.streams.get(id);
    if (stream) {
      stream.complete();
      this.streams.delete(id);
    }
  }
  
  /**
   * Notify all streams that depend on a table that data has changed
   */
  notifyTableChanged(tableName: string): void {
    for (const stream of this.streams.values()) {
      const dependencies = stream.getDependencies();
      if (dependencies.includes(tableName)) {
        stream.refresh();
      }
    }
  }
  
  /**
   * Notify all streams that depend on any of the given tables
   */
  notifyTablesChanged(tableNames: string[]): void {
    for (const tableName of tableNames) {
      this.notifyTableChanged(tableName);
    }
  }
  
  /**
   * Get count of active streams
   */
  getStreamCount(): number {
    return this.streams.size;
  }
  
  /**
   * Get all stream IDs
   */
  getStreamIds(): string[] {
    return Array.from(this.streams.keys());
  }
  
  /**
   * Clear all streams
   */
  clear(): void {
    for (const stream of this.streams.values()) {
      stream.complete();
    }
    this.streams.clear();
  }
}
