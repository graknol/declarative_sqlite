import { test, expect, type Page } from '@playwright/test';

/**
 * OpfsAdapter against real OPFS in Chromium. OPFS sync access handles exist
 * only in workers, so the page runs named workers: "db" plays the app's
 * database worker, "other" a second tab or worker on the same origin. Each
 * test gets a fresh browser context, so an empty origin-private file system;
 * a reload keeps it. Run with `npm run test:browser`; set SQLITE_WASM_PKG to
 * the directory of another @sqlite.org/sqlite-wasm install (3.50+ for the
 * pauseVfs test).
 */

interface OpResult {
  ok: boolean;
  value?: unknown;
  message?: string;
  causeName?: string;
}

type Harness = {
  start(name: string): void;
  stop(name: string): void;
  call(name: string, op: string, ...args: unknown[]): Promise<OpResult>;
};

async function load(page: Page): Promise<void> {
  await page.goto('/');
  await page.waitForSelector('body[data-ready="1"]', { state: 'attached' });
}

function start(page: Page, worker: string): Promise<void> {
  return page.evaluate((w) => (window as unknown as { h: Harness }).h.start(w), worker);
}

function stop(page: Page, worker: string): Promise<void> {
  return page.evaluate((w) => (window as unknown as { h: Harness }).h.stop(w), worker);
}

/** Runs `ops[op](...args)` in the named worker. */
function call(page: Page, worker: string, op: string, ...args: unknown[]): Promise<OpResult> {
  return page.evaluate(
    ([w, o, a]) => (window as unknown as { h: Harness }).h.call(w, o, ...(a as unknown[])),
    [worker, op, args] as const,
  );
}

async function ok(page: Page, worker: string, op: string, ...args: unknown[]): Promise<unknown> {
  const r = await call(page, worker, op, ...args);
  expect(r, `${worker}.${op} ${JSON.stringify(args)} -> ${JSON.stringify(r)}`).toMatchObject({ ok: true });
  return r.value;
}

/**
 * Retries an op until it succeeds: a terminated worker releases its OPFS
 * handles asynchronously. Only for ops whose failure is not cached (open()
 * retries a failed pool install; the static delete does not).
 */
async function eventually(page: Page, worker: string, op: string, ...args: unknown[]): Promise<unknown> {
  let last: OpResult | undefined;
  for (let i = 0; i < 40; i++) {
    last = await call(page, worker, op, ...args);
    if (last.ok) return last.value;
    await page.waitForTimeout(100);
  }
  throw new Error(`${worker}.${op} never succeeded: ${JSON.stringify(last)}`);
}

test('(a) deleting b.db frees its slot and leaves a.db intact across a reload', async ({ page }) => {
  await load(page);
  await start(page, 'db');
  for (const name of ['a.db', 'b.db']) {
    await ok(page, 'db', 'open', name);
    await ok(page, 'db', 'exec', name, `CREATE TABLE t(v TEXT); INSERT INTO t VALUES ('${name}')`);
  }
  expect(await ok(page, 'db', 'poolInfo', 'a.db')).toMatchObject({ fileCount: 2 });

  expect(await ok(page, 'db', 'deleteOwn', 'b.db')).toBe(true);
  expect(await ok(page, 'db', 'poolInfo', 'a.db')).toMatchObject({ fileCount: 1, fileNames: ['/a.db'] });

  await page.reload();
  await page.waitForSelector('body[data-ready="1"]', { state: 'attached' });
  await start(page, 'db');
  await eventually(page, 'db', 'open', 'a.db');
  expect(await ok(page, 'db', 'all', 'a.db', 'SELECT v FROM t')).toEqual([{ v: 'a.db' }]);
  expect(await ok(page, 'db', 'poolInfo', 'a.db')).toMatchObject({ fileNames: ['/a.db'] });

  // b.db comes back empty, not with its old table.
  await ok(page, 'db', 'open', 'b.db');
  expect(await ok(page, 'db', 'all', 'b.db', "SELECT name FROM sqlite_master WHERE name = 't'")).toEqual([]);
});

test('(b) a 7th database opens on a full 6-slot pool, and the pool grows', async ({ page }) => {
  await load(page);
  await start(page, 'seed');
  const seeded = (await ok(page, 'seed', 'seedFullDefaultPool')) as { capacity: number; fileCount: number; seventh: string };
  expect(seeded).toMatchObject({ capacity: 6, fileCount: 6 });
  expect(seeded.seventh).toMatch(/SAH pool is full|SQLITE_CANTOPEN/);
  await stop(page, 'seed'); // releases the pool the raw sqlite-wasm calls installed

  await start(page, 'db');
  await eventually(page, 'db', 'open', 'u7.db');
  await ok(page, 'db', 'exec', 'u7.db', "CREATE TABLE t(x); INSERT INTO t VALUES ('seventh')");
  const info = (await ok(page, 'db', 'poolInfo', 'u7.db')) as { capacity: number; fileCount: number };
  expect(info.fileCount).toBe(7);
  expect(info.capacity).toBeGreaterThanOrEqual(8);
  await ok(page, 'db', 'open', 'u1.db');
  expect(await ok(page, 'db', 'all', 'u1.db', 'SELECT x FROM t')).toEqual([{ x: 1 }]);
});

test('(c) a static delete while another worker holds the pool rejects, deletes nothing, and the data survives', async ({
  page,
}) => {
  await load(page);
  await start(page, 'db');
  await ok(page, 'db', 'open', 'a.db');
  await ok(page, 'db', 'exec', 'a.db', "CREATE TABLE t(v TEXT); INSERT INTO t VALUES ('kept')");

  await start(page, 'other');
  for (let attempt = 1; attempt <= 2; attempt++) {
    const r = await call(page, 'other', 'deleteStatic', 'a.db');
    expect(r.ok, `attempt ${attempt}: ${JSON.stringify(r)}`).toBe(false);
    expect(r.causeName).toBe('NoModificationAllowedError');
    expect(r.message).toMatch(/another tab or worker holds the OPFS pool/);
  }

  expect(await ok(page, 'db', 'all', 'a.db', 'SELECT v FROM t')).toEqual([{ v: 'kept' }]);

  // A new database worker (a fresh install of the pool) still finds the data on disk.
  await stop(page, 'db');
  await start(page, 'db');
  await eventually(page, 'db', 'open', 'a.db');
  expect(await ok(page, 'db', 'all', 'a.db', 'SELECT v FROM t')).toEqual([{ v: 'kept' }]);
  expect(await ok(page, 'db', 'poolInfo', 'a.db')).toMatchObject({ fileNames: ['/a.db'] });
});

test('(d) after another worker deleted a database, the database worker can open the pool again (pauseVfs)', async ({
  page,
}) => {
  await load(page);
  await start(page, 'probe');
  const probe = (await ok(page, 'probe', 'hasPause')) as { has: boolean; libVersion: string };
  await stop(page, 'probe');
  console.log(`sqlite-wasm ${probe.libVersion}, pauseVfs: ${probe.has}`);

  // The (c) situation: the database worker owns a.db and b.db, another worker's delete is refused.
  await start(page, 'db');
  for (const name of ['a.db', 'b.db']) {
    await ok(page, 'db', 'open', name);
    await ok(page, 'db', 'exec', name, `CREATE TABLE t(v TEXT); INSERT INTO t VALUES ('${name}')`);
  }
  await start(page, 'other');
  expect((await call(page, 'other', 'deleteStatic', 'b.db')).causeName).toBe('NoModificationAllowedError');
  await stop(page, 'other');
  await stop(page, 'db');

  // A retry from a fresh worker (the failure is cached per realm) succeeds once the handles are released.
  let deleted: OpResult | undefined;
  for (let i = 0; i < 20 && !deleted?.ok; i++) {
    await start(page, 'other');
    deleted = await call(page, 'other', 'deleteStatic', 'b.db');
    if (!deleted.ok) {
      await stop(page, 'other');
      await page.waitForTimeout(200);
    }
  }
  expect(deleted).toMatchObject({ ok: true, value: true });

  // "other" is still alive. With pauseVfs it has handed the pool back.
  await start(page, 'db');
  const reopened = await call(page, 'db', 'open', 'a.db');
  if (!probe.has) {
    expect(reopened.ok, `sqlite-wasm ${probe.libVersion} has no pauseVfs, so "other" keeps the pool`).toBe(false);
    return;
  }
  expect(reopened, JSON.stringify(reopened)).toMatchObject({ ok: true });
  expect(await ok(page, 'db', 'all', 'a.db', 'SELECT v FROM t')).toEqual([{ v: 'a.db' }]);
  expect(await ok(page, 'db', 'poolInfo', 'a.db')).toMatchObject({ fileNames: ['/a.db'] });
});
