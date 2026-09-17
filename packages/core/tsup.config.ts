import { defineConfig } from 'tsup';

export default defineConfig({
  entry: { index: 'src/index.ts' }, // 'react/index': 'src/react/index.ts', re-enabled in Task 33
  format: ['esm', 'cjs'],
  dts: true,
  clean: true,
  sourcemap: true,
  treeshake: true,
  external: ['react', '@sqlite.org/sqlite-wasm'],
});
