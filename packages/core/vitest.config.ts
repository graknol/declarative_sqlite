import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    // browser-test/ holds Playwright specs that need a real browser: `npm run test:browser`.
    exclude: ['**/node_modules/**', '**/dist/**', 'browser-test/**'],
    coverage: { provider: 'v8', reporter: ['text'], exclude: ['dist/', '**/*.test.ts'] },
  },
});
