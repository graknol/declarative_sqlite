import type { DbTable } from '../types';
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
  
  constructor(public readonly name: string) {
    // Add system columns automatically
    this.addSystemColumns();
  }
  
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
    return {
      name: this.name,
      columns: this.columnBuilders.map(b => b.build()),
      keys: this.keyBuilders.map(b => b.build()),
      isSystem: this.name.startsWith('__'),
    };
  }
  
  /**
   * Add system columns that are automatically included in every table
   */
  private addSystemColumns(): void {
    // system_id: Auto-generated UUID primary key
    this.columnBuilders.push(
      new GuidColumnBuilder('system_id')
        .notNull('00000000-0000-0000-0000-000000000000')
    );
    
    // system_created_at: HLC timestamp of creation
    this.columnBuilders.push(
      new TextColumnBuilder('system_created_at')
        .notNull('')
    );
    
    // system_version: HLC timestamp of last modification
    this.columnBuilders.push(
      new TextColumnBuilder('system_version')
        .notNull('')
    );
  }
}
