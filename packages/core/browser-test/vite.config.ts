import path from 'node:path';
import { defineConfig } from 'vite';

// SQLITE_WASM_PKG=<dir of an @sqlite.org/sqlite-wasm install> runs the page
// against another sqlite-wasm build than the one in node_modules, e.g. 3.50+
// for pauseVfs.
const wasmPkg = process.env['SQLITE_WASM_PKG'];

export default defineConfig({
  root: __dirname,
  resolve: wasmPkg ? { alias: { '@sqlite.org/sqlite-wasm': path.resolve(wasmPkg) } } : {},
  // sqlite-wasm finds its .wasm next to its own module; pre-bundling would move it.
  optimizeDeps: { exclude: ['@sqlite.org/sqlite-wasm'] },
  server: { fs: { strict: false } },
  worker: { format: 'es' },
});
