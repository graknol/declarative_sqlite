/**
 * Ambient module declaration for the official SQLite WASM build's Node entry
 * point. `@sqlite.org/sqlite-wasm` does not publish a subpath export or type
 * declaration for `sqlite-wasm/jswasm/sqlite3-node.mjs`, so TypeScript cannot
 * resolve it on its own; `vitest.config.ts` aliases the same path to the real
 * file for tests, and this declaration lets `tsc --noEmit` and the tsup build
 * type-check the dynamic `import()` in `memory-adapter.ts` without it.
 */
declare module '@sqlite.org/sqlite-wasm/sqlite-wasm/jswasm/sqlite3-node.mjs' {
  const init: (config: unknown) => Promise<unknown>;
  export default init;
}
