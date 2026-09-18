import { describe, it, expect } from 'vitest';
import * as root from './index';

describe('public surface', () => {
  it('reports the v3 alpha version', () => {
    expect(root.VERSION).toBe('3.0.0-alpha.1');
  });

  it('exports the five layers', () => {
    for (const name of [
      'SchemaBuilder', 'validateScopes',
      'runMigration', 'planMigration', 'MigrationBlockedError',
      'MemoryAdapter', 'OpfsAdapter', 'IndexedDbAdapter', 'openAdapter',
      'Database', 'Transaction', 'LiveQuery',
      'Outbox', 'Overlay', 'Drafts', 'CursorStore', 'PullApplier', 'PullService', 'PushService', 'TickCoalescer', 'createSyncRuntime',
      'FakeTransport',
    ]) {
      expect(root, `missing export: ${name}`).toHaveProperty(name);
    }
  });

  it('does not export the server-write capability', () => {
    expect(root).not.toHaveProperty('createServerWriteCapability');
  });
});
