// Exposes named workers on `window.h` for Playwright. OPFS sync access handles
// exist only in workers, so every op runs in one: "db" plays the app's
// database worker, "other" a second tab or worker on the same origin.
import type { Op, OpResult } from './ops';

const workers = new Map<string, Worker>();
let nextId = 0;
const pending = new Map<number, (r: OpResult) => void>();

const h = {
  start(name: string): void {
    const worker = new Worker(new URL('./worker.ts', import.meta.url), { type: 'module' });
    worker.onmessage = (e: MessageEvent<{ id: number; result: OpResult }>) => {
      pending.get(e.data.id)?.(e.data.result);
      pending.delete(e.data.id);
    };
    workers.set(name, worker);
  },
  call(name: string, op: Op, ...args: unknown[]): Promise<OpResult> {
    const worker = workers.get(name);
    if (!worker) return Promise.resolve({ ok: false, message: `worker ${name} not started` });
    const id = nextId++;
    return new Promise((resolve) => {
      pending.set(id, resolve);
      worker.postMessage({ id, op, args });
    });
  },
  stop(name: string): void {
    workers.get(name)?.terminate();
    workers.delete(name);
  },
};

(window as unknown as { h: typeof h }).h = h;
document.body.dataset['ready'] = '1';
