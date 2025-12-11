/**
 * Comlink transfer handlers for DbRecord serialization.
 * 
 * This module provides utilities to enable DbRecord instances to be passed
 * through Comlink when using a web worker-based database setup.
 * 
 * Usage:
 * ```typescript
 * import { transferHandlers } from 'comlink';
 * import { registerDbRecordTransferHandler } from 'declarative-sqlite';
 * 
 * // In both main thread and worker:
 * registerDbRecordTransferHandler(transferHandlers);
 * ```
 */

import { DbRecord, SerializableDbRecord, ReadonlyDbRecord } from './db-record';

/**
 * Checks if a value is a DbRecord instance
 */
export function isDbRecord(value: any): value is DbRecord<any> {
  return !!value && typeof value === 'object' && '_db' in value && '_tableName' in value && '_values' in value;
}

/**
 * Checks if a value is a serialized DbRecord
 */
export function isSerializableDbRecord(value: any): value is SerializableDbRecord {
  return !!value && typeof value === 'object' && value.__type === 'SerializableDbRecord';
}

/**
 * Register Comlink transfer handler for DbRecord.
 * This allows DbRecord instances to be automatically serialized when passed through Comlink.
 * 
 * Note: Comlink is an optional peer dependency. This function should only be called
 * if you're using Comlink.
 * 
 * @param transferHandlers - The transferHandlers object from Comlink
 * 
 * @example
 * ```typescript
 * import { transferHandlers } from 'comlink';
 * import { registerDbRecordTransferHandler } from 'declarative-sqlite';
 * 
 * registerDbRecordTransferHandler(transferHandlers);
 * ```
 */
export function registerDbRecordTransferHandler(transferHandlers: Map<string, any>): void {
  transferHandlers.set('DbRecord', {
    canHandle: (obj: any): boolean => {
      return isDbRecord(obj);
    },
    serialize: (obj: DbRecord<any>) => {
      const serialized = obj.toSerializable();
      return [serialized, []]; // [value, transferables]
    },
    deserialize: (obj: SerializableDbRecord) => {
      return DbRecord.fromSerializable(obj);
    }
  });
}

/**
 * Manually serialize a DbRecord for Comlink transfer.
 * Use this if you want explicit control over serialization.
 * 
 * @param record - The DbRecord to serialize
 * @returns A serializable plain object
 */
export function serializeDbRecord<T extends Record<string, any>>(
  record: DbRecord<T> & T
): SerializableDbRecord {
  return (record as any).toSerializable();
}

/**
 * Manually deserialize a DbRecord from Comlink transfer.
 * Use this if you want explicit control over deserialization.
 * 
 * @param data - The serialized DbRecord data
 * @returns A read-only DbRecord-like object
 */
export function deserializeDbRecord(data: SerializableDbRecord): ReadonlyDbRecord {
  return DbRecord.fromSerializable(data);
}

/**
 * Helper to convert query results containing DbRecords to serializable format.
 * Useful when you want to return query results from a worker.
 * 
 * @param records - Array of DbRecord instances
 * @returns Array of serializable plain objects
 */
export function serializeDbRecords<T extends Record<string, any>>(
  records: (DbRecord<T> & T)[]
): SerializableDbRecord[] {
  return records.map(record => serializeDbRecord(record));
}

/**
 * Helper to convert serialized DbRecords back to read-only DbRecord objects.
 * 
 * @param data - Array of serialized DbRecord data
 * @returns Array of read-only DbRecord-like objects
 */
export function deserializeDbRecords(data: SerializableDbRecord[]): ReadonlyDbRecord[] {
  return data.map(item => deserializeDbRecord(item));
}
