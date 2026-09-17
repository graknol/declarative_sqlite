import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    coverage: { provider: 'v8', reporter: ['text'], exclude: ['dist/', '**/*.test.ts'] },
  },
  resolve: {
    alias: {
      '@sqlite.org/sqlite-wasm/sqlite-wasm/jswasm/sqlite3-node.mjs': path.resolve(
        __dirname,
        'node_modules/@sqlite.org/sqlite-wasm/sqlite-wasm/jswasm/sqlite3-node.mjs',
      ),
    },
  },
});
