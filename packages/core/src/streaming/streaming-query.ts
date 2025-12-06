import { Observable, Subject } from 'rxjs';
import { SQLiteAdapter } from '../adapters/adapter.interface';

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
 */
export class StreamingQuery<T = any> extends Observable<T[]> {
  private subject = new Subject<T[]>();
  private dependencies: string[] = [];
  
  constructor(
    private adapter: SQLiteAdapter,
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
    let sql = `SELECT * FROM "${this.tableName}"`;
    const args: any[] = [];
    
    if (this.options.where) {
      sql += ` WHERE ${this.options.where}`;
      if (this.options.whereArgs) {
        args.push(...this.options.whereArgs);
      }
    }
    
    if (this.options.orderBy) {
      sql += ` ORDER BY ${this.options.orderBy}`;
    }
    
    if (this.options.limit !== undefined) {
      sql += ` LIMIT ${this.options.limit}`;
    }
    
    if (this.options.offset !== undefined) {
      sql += ` OFFSET ${this.options.offset}`;
    }
    
    const stmt = this.adapter.prepare(sql);
    return stmt.all(...args) as T[];
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
