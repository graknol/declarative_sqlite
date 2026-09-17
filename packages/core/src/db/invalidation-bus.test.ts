import { describe, it, expect, vi } from 'vitest';
import { InvalidationBus, WriteLog } from './invalidation-bus';

describe('WriteLog', () => {
  it('starts empty', () => {
    expect(new WriteLog().isEmpty()).toBe(true);
  });

  it('collects rows with their scope', () => {
    const log = new WriteLog();
    log.markRow('c_work_task', 'A', { wo_no: 3188 });
    log.markRow('c_work_task', 'B', { wo_no: 3188 });
    const event = log.toEvent();
    expect([...(event.tables.get('c_work_task') ?? new Map()).keys()]).toEqual(['A', 'B']);
  });

  it('a whole-table mark wins over row marks for that table', () => {
    const log = new WriteLog();
    log.markRow('c_work_task', 'A', { wo_no: 3188 });
    log.markTable('c_work_task');
    expect(log.toEvent().tables.get('c_work_task')).toBeNull();
  });
});

describe('InvalidationBus', () => {
  it('delivers events to every subscriber until it unsubscribes', () => {
    const bus = new InvalidationBus();
    const first = vi.fn();
    const second = vi.fn();
    const stop = bus.subscribe(first);
    bus.subscribe(second);

    const log = new WriteLog();
    log.markTable('t');
    bus.emit(log.toEvent());
    stop();
    bus.emit(log.toEvent());

    expect(first).toHaveBeenCalledTimes(1);
    expect(second).toHaveBeenCalledTimes(2);
  });

  it('one listener throwing does not stop the others', () => {
    const bus = new InvalidationBus();
    const good = vi.fn();
    bus.subscribe(() => {
      throw new Error('boom');
    });
    bus.subscribe(good);
    const log = new WriteLog();
    log.markTable('t');
    expect(() => bus.emit(log.toEvent())).not.toThrow();
    expect(good).toHaveBeenCalledTimes(1);
  });
});
