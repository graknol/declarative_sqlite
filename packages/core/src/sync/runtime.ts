import type { Database } from '../db/database';
import { createServerWriteCapability, serverWriter, type ServerWriter } from '../db/server-truth';
import type { Row } from '../types';
import { CursorStore } from './cursor-store';
import { Drafts } from './drafts';
import { Outbox } from './outbox';
import { Overlay } from './overlay';
import { PullApplier } from './pull-applier';
import { PullService } from './pull-service';
import { PushService } from './push-service';
import { TickCoalescer } from './tick-coalescer';
import type { SyncTransport } from './transport';

export interface SyncRuntimeOptions {
  db: Database;
  transport: SyncTransport;
  /** Logged with every change on the server; the app's installation id. */
  deviceId: string;
  debounceMs?: number;
  maxChangesPerBatch?: number;
  pullWindow?: number;
  pageLimit?: number;
  tickWindowMs?: number;
  clock?: () => Date;
  isTerminalError?: (error: unknown) => boolean;
}

/** Everything the sync layer exposes for one database. Create it once, right after `Database.open`. */
export interface SyncRuntime {
  outbox: Outbox;
  overlay: Overlay;
  drafts: Drafts;
  cursors: CursorStore;
  applier: PullApplier;
  pull: PullService;
  push: PushService;
  ticks: TickCoalescer;
  close(): void;
}

interface CoreServices {
  writer: ServerWriter;
  outbox: Outbox;
  overlay: Overlay;
  drafts: Drafts;
  cursors: CursorStore;
  applier: PullApplier;
}

/**
 * Builds the three state owners (outbox, overlay, drafts) and the cursor store
 * and applier that sit between them and the network, and loads the outbox's
 * pending index so overlaying survives a restart. Everything downstream that
 * needs to write a synced table shares the one `ServerWriter` minted here.
 */
async function createCoreServices(db: Database, clock: (() => Date) | undefined): Promise<CoreServices> {
  const writer = serverWriter(db, createServerWriteCapability());
  const clockOption = clock ? { clock } : {};

  const outbox = new Outbox(db, writer, clockOption);
  await outbox.load();

  const overlay = new Overlay(db, outbox);
  const drafts = new Drafts(db, outbox, writer);
  const cursors = new CursorStore(db, clockOption);
  const applier = new PullApplier(db, writer, outbox, drafts, cursors);

  return { writer, outbox, overlay, drafts, cursors, applier };
}

/** Builds the pull, push and tick services on top of the core services, from the tuning knobs `createSyncRuntime`'s caller supplied. */
function createNetworkServices(
  options: SyncRuntimeOptions,
  core: CoreServices,
): { pull: PullService; push: PushService; ticks: TickCoalescer } {
  const { db, transport } = options;

  const pull = new PullService(transport, core.applier, core.cursors, {
    ...(options.pullWindow !== undefined ? { window: options.pullWindow } : {}),
    ...(options.pageLimit !== undefined ? { pageLimit: options.pageLimit } : {}),
  });

  const push = new PushService(db, transport, core.outbox, core.applier, {
    deviceId: options.deviceId,
    ...(options.debounceMs !== undefined ? { debounceMs: options.debounceMs } : {}),
    ...(options.maxChangesPerBatch !== undefined ? { maxChangesPerBatch: options.maxChangesPerBatch } : {}),
    ...(options.isTerminalError ? { isTerminalError: options.isTerminalError } : {}),
  });

  const ticks = new TickCoalescer(pull, core.cursors, options.tickWindowMs !== undefined ? { windowMs: options.tickWindowMs } : {});

  return { pull, push, ticks };
}

/**
 * Builds the sync layer on top of an open database and wires it in: it mints the
 * server-write capability (so synced tables become writable to the applier and
 * the outbox, and to nothing else), loads the outbox's pending index, and
 * installs the row transform that puts the overlay and the draft holds in front
 * of every live query. Call `close()` when the database closes.
 */
export async function createSyncRuntime(options: SyncRuntimeOptions): Promise<SyncRuntime> {
  const { db } = options;
  const core = await createCoreServices(db, options.clock);
  const { pull, push, ticks } = createNetworkServices(options, core);

  const transform = (table: string, rows: Row[]): Row[] => core.drafts.apply(table, core.overlay.apply(table, rows));
  db.setRowTransform(transform);

  const unsubscribeOutbox = core.outbox.subscribe(() => push.schedule());

  return {
    outbox: core.outbox,
    overlay: core.overlay,
    drafts: core.drafts,
    cursors: core.cursors,
    applier: core.applier,
    pull,
    push,
    ticks,
    close() {
      unsubscribeOutbox();
      push.stop();
      ticks.stop();
      db.setRowTransform(undefined);
    },
  };
}
