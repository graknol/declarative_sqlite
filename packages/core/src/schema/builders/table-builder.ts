import type { DbTable, DbColumn } from '../types';
import {
  TextColumnBuilder,
  IntegerColumnBuilder,
  RealColumnBuilder,
  GuidColumnBuilder,
  DateColumnBuilder,
  FilesetColumnBuilder,
} from './column-builders';
import { KeyBuilder } from './key-builder';

type AnyColumnBuilder = 
  | TextColumnBuilder
  | IntegerColumnBuilder
  | RealColumnBuilder
  | GuidColumnBuilder
  | DateColumnBuilder
  | FilesetColumnBuilder;

/**
 * Builder for database tables
 */
export class TableBuilder {
  private columnBuilders: AnyColumnBuilder[] = [];
  private keyBuilders: KeyBuilder[] = [];
  
  constructor(public readonly name: string) {}
  
  /**
   * Add a text column
   */
  text(name: string): TextColumnBuilder {
    const builder = new TextColumnBuilder(name);
    this.columnBuilders.push(builder);
    return builder;
  }
  
  /**
   * Add an integer column
   */
  integer(name: string): IntegerColumnBuilder {
    const builder = new IntegerColumnBuilder(name);
    this.columnBuilders.push(builder);
    return builder;
  }
  
  /**
   * Add a real (float) column
   */
  real(name: string): RealColumnBuilder {
    const builder = new RealColumnBuilder(name);
    this.columnBuilders.push(builder);
    return builder;
  }
  
  /**
   * Add a GUID column
   */
  guid(name: string): GuidColumnBuilder {
    const builder = new GuidColumnBuilder(name);
    this.columnBuilders.push(builder);
    return builder;
  }
  
  /**
   * Add a date column
   */
  date(name: string): DateColumnBuilder {
    const builder = new DateColumnBuilder(name);
    this.columnBuilders.push(builder);
    return builder;
  }
  
  /**
   * Add a fileset column
   */
  fileset(name: string): FilesetColumnBuilder {
    const builder = new FilesetColumnBuilder(name);
    this.columnBuilders.push(builder);
    return builder;
  }
  
  /**
   * Define a key (primary, unique, or index)
   */
  key(...columnNames: string[]): KeyBuilder {
    const builder = new KeyBuilder(columnNames);
    this.keyBuilders.push(builder);
    return builder;
  }
  
  /**
   * Build the final table definition
   */
  build(): DbTable {
    const columns = this.columnBuilders.map(b => b.build());
    
    // Add HLC columns for LWW fields
    const hlcColumns: DbColumn[] = [];
    for (const col of columns) {
      if (col.lww) {
        hlcColumns.push({
          name: `${col.name}__hlc`,
          type: 'TEXT',
          notNull: false,
        });
      }
    }

    // Add system columns
    const systemColumns: DbColumn[] = [];
    if (!this.name.startsWith('__')) {
      systemColumns.push({
        name: 'system_id',
        type: 'GUID',
        notNull: true,
        defaultValue: '00000000-0000-0000-0000-000000000000',
      });
      
      const zeroHlc = '000000000000000:000000000:000000000000000000000000000000000000';
      
      systemColumns.push({
        name: 'system_created_at',
        type: 'TEXT',
        notNull: true,
        defaultValue: zeroHlc,
      });
      
      systemColumns.push({
        name: 'system_version',
        type: 'TEXT',
        notNull: true,
        defaultValue: zeroHlc,
      });
      
      systemColumns.push({
        name: 'system_is_local_origin',
        type: 'INTEGER',
        notNull: true,
        defaultValue: 1,
      });
    }

    return {
      name: this.name,
      columns: [...systemColumns, ...columns, ...hlcColumns],
      keys: this.keyBuilders.map(b => b.build()),
      isSystem: this.name.startsWith('__'),
    };
  }
}
