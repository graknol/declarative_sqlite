import { Database, SchemaBuilder, createSyncRuntime } from '../../src/index';
import { openAdapter } from '../../src/adapters/open-adapter';
import { FakeTransport } from '../../src/testing/fake-transport';

const out = document.getElementById('out') as HTMLPreElement;
const log = (line: string) => {
  out.textContent += `\n${line}`;
};

async function main(): Promise<void> {
  out.textContent = 'opening…';
  const opened = await openAdapter({ name: 'smoke.db' });
  log(`backend: ${opened.backend}`);
  for (const warning of opened.warnings) log(`warning: ${warning}`);

  const schema = new SchemaBuilder();
  schema.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });

  const db = await Database.open({ schema: schema.build(), adapter: opened.adapter });
  const transport = new FakeTransport();
  const sync = await createSyncRuntime({ db, transport, deviceId: 'browser-smoke' });

  const runs = (await db.queryOne<{ n: number }>('SELECT COUNT(*) AS n FROM c_work_task'))?.n ?? 0;
  transport.seed('C_WORK_TASK', [{ id: `row-${runs + 1}`, data: { WO_NO: 3188, C_QTY_INSTALLED: runs + 1 } }]);
  await sync.pull.pull('c_work_task', { wo_no: 3188 });

  const after = (await db.queryOne<{ n: number }>('SELECT COUNT(*) AS n FROM c_work_task'))?.n ?? 0;
  log(`rows before: ${runs}, after: ${after}`);
  log(after > runs ? 'OK: the pull applied' : 'FAIL: nothing was applied');
  log(after > 1 ? 'OK: data survived a reload' : 'reload the page to check persistence');

  if ('flush' in opened.adapter && typeof (opened.adapter as { flush?: () => Promise<void> }).flush === 'function') {
    await (opened.adapter as { flush: () => Promise<void> }).flush();
  }
}

void main().catch((error) => log(`FAIL: ${String(error)}`));
