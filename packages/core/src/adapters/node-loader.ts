// Default imports only (not named): a browser bundler that still traverses into
// this Node-only module despite the dynamic import in memory-adapter.ts (Rollup,
// which Vite's production build uses, does) externalizes an unresolved `node:`
// specifier to a stub module exporting nothing but `default`. A named import
// (`import { createRequire } from 'node:module'`) fails Rollup's static binding
// check against that stub even though this code never runs in the browser; a
// default import only ever needs the `default` binding, which the stub always
// provides, so the build only warns instead of hard-erroring.
import nodeModule from 'node:module';
import path from 'node:path';
import nodeUrl from 'node:url';
import type { Sqlite3Module } from './wasm';

/**
 * Resolves and loads the Node entry point of `@sqlite.org/sqlite-wasm`
 * (`sqlite-wasm/jswasm/sqlite3-node.mjs`). That file is not listed in the
 * package's `exports` map, so importing it by specifier throws
 * `ERR_PACKAGE_PATH_NOT_EXPORTED` under plain Node; only `.` and
 * `./package.json` are exported. We resolve `./package.json` (which *is*
 * exported) with `createRequire`, then join its directory to the real file
 * and import that absolute `file://` URL instead, which bypasses the
 * `exports` map entirely and works both under vitest and in a consuming
 * Node process with no bundler-specific alias required.
 */
export async function loadNodeSqlite3(): Promise<Sqlite3Module> {
  const require = nodeModule.createRequire(import.meta.url);
  const pkgJson = require.resolve('@sqlite.org/sqlite-wasm/package.json');
  const entry = path.join(path.dirname(pkgJson), 'sqlite-wasm', 'jswasm', 'sqlite3-node.mjs');
  return import(/* @vite-ignore */ nodeUrl.pathToFileURL(entry).href);
}
