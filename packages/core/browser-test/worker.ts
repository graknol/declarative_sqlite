// A dedicated worker that holds the OPFS pool, like an app's database worker.
import { ops, type Op } from './ops';

self.onmessage = async (event: MessageEvent<{ id: number; op: Op; args: unknown[] }>) => {
  const { id, op, args } = event.data;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const result = await (ops[op] as (...a: any[]) => Promise<unknown>)(...args);
  self.postMessage({ id, result });
};
