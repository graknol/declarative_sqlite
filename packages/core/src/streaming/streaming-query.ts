import { Observable, Subject } from 'rxjs';
import type { DeclarativeDatabase } from '../database/declarative-database';

export interface QueryOptions {
  where?: string;
  whereArgs?: any[];
  orderBy?: string;
  limit?: number;
  offset?: number;
}

/**
 * StreamingQuery wraps a database query in an RxJS Observable
 * that automatically refreshes when underlying data changes.
 * Returns plain objects with xRec tracking for change detection.
 */
export class StreamingQuery<T extends Record<string, any> = any> extends Observable<T[]> {
  private subject = new Subject<T[]>();
  private dependencies: string[] = [];
  
  constructor(
    private db: DeclarativeDatabase,
    private tableName: string,
    private options: QueryOptions = {},
    private queryFn?: () => Promise<T[]>
  ) {
    super(subscriber => {
      // Subscribe to the internal subject
      const subscription = this.subject.subscribe(subscriber);
      
      // Execute initial query
      this.executeQuery();
      
      // Return teardown logic
      return () => {
        subscription.unsubscribe();
      };
    });
    
    this.dependencies = [tableName];
  }
  
  /**
   * Execute the query and emit results
   */
  async executeQuery(): Promise<void> {
    try {
      let results: T[];
      
      if (this.queryFn) {
        results = await this.queryFn();
      } else {
        results = await this.executeTableQuery();
      }
      
      this.subject.next(results);
    } catch (error) {
      this.subject.error(error);
    }
  }
  
  private async executeTableQuery(): Promise<T[]> {
    // Use the database query method which returns plain objects with xRec tracking
    return await this.db.query<T>(this.tableName, this.options);
  }
  
  /**
   * Get table dependencies for this query
   */
  getDependencies(): string[] {
    return this.dependencies;
  }
  
  /**
   * Manually refresh the query
   */
  refresh(): void {
    this.executeQuery();
  }
  
  /**
   * Complete the observable and clean up
   */
  complete(): void {
    this.subject.complete();
  }
}
