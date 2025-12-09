import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import { SqliteWasmAdapter } from '../database/sqlite-wasm-adapter';

export async function createTestAdapter(): Promise<SqliteWasmAdapter> {
  const sqlite3 = await sqlite3InitModule();
  const adapter = new SqliteWasmAdapter(sqlite3);
  await adapter.open(':memory:');
  return adapter;
}
