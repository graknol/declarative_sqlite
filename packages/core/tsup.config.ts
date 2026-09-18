import { defineConfig } from 'tsup';

export default defineConfig({
  entry: { index: 'src/index.ts', 'react/index': 'src/react/index.ts' },
  format: ['esm', 'cjs'],
  dts: true,
  clean: true,
  sourcemap: true,
  treeshake: true,
  external: ['react', '@sqlite.org/sqlite-wasm', /^node:/],
  // Keep the `node:` prefix on builtins tsup would otherwise strip (its own
  // default), so a Node-only chunk (e.g. node-loader.ts, reached only through
  // a dynamic import) reads unambiguously as a Node builtin rather than a
  // bare, npm-style specifier a browser bundler would try to resolve on disk.
  removeNodeProtocol: false,
});
