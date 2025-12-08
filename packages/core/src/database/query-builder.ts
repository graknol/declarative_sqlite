import { SQLiteAdapter } from '../adapters/adapter.interface';

export type WhereOperator = '=' | '!=' | '>' | '>=' | '<' | '<=' | 'LIKE' | 'IN' | 'NOT IN';

export interface WhereCondition {
  column: string;
  operator: WhereOperator;
  value: any;
}

export interface JoinClause {
  type: 'INNER' | 'LEFT' | 'RIGHT';
  table: string;
  on: string;
}

/**
 * Fluent query builder for constructing SQL queries
 */
export class QueryBuilder<T = any> {
  private adapter: SQLiteAdapter;
  private selectColumns: string[] = [];
  private fromTable: string = '';
  private joins: JoinClause[] = [];
  private whereConditions: WhereCondition[] = [];
  private orderByClause: string = '';
  private limitValue?: number;
  private offsetValue?: number;
  private groupByColumns: string[] = [];

  constructor(adapter: SQLiteAdapter) {
    this.adapter = adapter;
  }

  /**
   * Specify columns to select
   */
  select(...columns: string[]): this {
    this.selectColumns.push(...columns);
    return this;
  }

  /**
   * Select all columns
   */
  selectAll(): this {
    this.selectColumns = ['*'];
    return this;
  }

  /**
   * Specify the table to query from
   */
  from(table: string): this {
    this.fromTable = table;
    return this;
  }

  /**
   * Add a WHERE condition
   */
  where(column: string, operator: WhereOperator, value: any): this {
    this.whereConditions.push({ column, operator, value });
    return this;
  }

  /**
   * Add a WHERE condition with = operator
   */
  whereEquals(column: string, value: any): this {
    return this.where(column, '=', value);
  }

  /**
   * Add an INNER JOIN
   */
  innerJoin(table: string, on: string): this {
    this.joins.push({ type: 'INNER', table, on });
    return this;
  }

  /**
   * Add a LEFT JOIN
   */
  leftJoin(table: string, on: string): this {
    this.joins.push({ type: 'LEFT', table, on });
    return this;
  }

  /**
   * Add ORDER BY clause
   */
  orderBy(clause: string): this {
    this.orderByClause = clause;
    return this;
  }

  /**
   * Add LIMIT clause
   */
  limit(value: number): this {
    this.limitValue = value;
    return this;
  }

  /**
   * Add OFFSET clause
   */
  offset(value: number): this {
    this.offsetValue = value;
    return this;
  }

  /**
   * Add GROUP BY clause
   */
  groupBy(...columns: string[]): this {
    this.groupByColumns.push(...columns);
    return this;
  }

  /**
   * Build and execute the query
   */
  async execute(): Promise<T[]> {
    const { sql, params } = this.build();
    const stmt = this.adapter.prepare(sql);
    const results = await stmt.all(...params);
    return results as T[];
  }

  /**
   * Build and execute, returning first result
   */
  async first(): Promise<T | null> {
    const results = await this.limit(1).execute();
    return results.length > 0 ? results[0]! : null;
  }

  /**
   * Build the SQL query and parameters
   */
  build(): { sql: string; params: any[] } {
    if (!this.fromTable) {
      throw new Error('FROM clause is required');
    }

    let sql = 'SELECT ';
    sql += this.selectColumns.length > 0 ? this.selectColumns.join(', ') : '*';
    sql += ` FROM "${this.fromTable}"`;

    // Add JOINs
    for (const join of this.joins) {
      sql += ` ${join.type} JOIN "${join.table}" ON ${join.on}`;
    }

    // Add WHERE conditions
    const params: any[] = [];
    if (this.whereConditions.length > 0) {
      const whereClauses = this.whereConditions.map(cond => {
        if (cond.operator === 'IN' || cond.operator === 'NOT IN') {
          const placeholders = Array.isArray(cond.value)
            ? cond.value.map(() => '?').join(', ')
            : '?';
          if (Array.isArray(cond.value)) {
            params.push(...cond.value);
          } else {
            params.push(cond.value);
          }
          return `"${cond.column}" ${cond.operator} (${placeholders})`;
        } else {
          params.push(cond.value);
          return `"${cond.column}" ${cond.operator} ?`;
        }
      });
      sql += ' WHERE ' + whereClauses.join(' AND ');
    }

    // Add GROUP BY
    if (this.groupByColumns.length > 0) {
      sql += ' GROUP BY ' + this.groupByColumns.map(c => `"${c}"`).join(', ');
    }

    // Add ORDER BY
    if (this.orderByClause) {
      sql += ` ORDER BY ${this.orderByClause}`;
    }

    // Add LIMIT
    if (this.limitValue !== undefined) {
      sql += ` LIMIT ${this.limitValue}`;
    }

    // Add OFFSET
    if (this.offsetValue !== undefined) {
      sql += ` OFFSET ${this.offsetValue}`;
    }

    return { sql, params };
  }

  /**
   * Get the SQL string (for debugging)
   */
  toSQL(): string {
    return this.build().sql;
  }
}
