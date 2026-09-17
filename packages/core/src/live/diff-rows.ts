function sameValues(a: Record<string, unknown>, b: Record<string, unknown>): boolean {
  const aKeys = Object.keys(a);
  const bKeys = Object.keys(b);
  if (aKeys.length !== bKeys.length) return false;
  for (const key of aKeys) {
    if (!(key in b)) return false;
    if (!Object.is(a[key], b[key])) return false;
  }
  return true;
}

/**
 * Compares a fresh query result with the previous snapshot. Rows that are
 * unchanged — same key, same columns, same values — are carried over by
 * reference, so a React list re-renders only the rows that actually moved.
 * `changed` is false when the whole result is identical in order and content,
 * which is what lets a live query stay silent after a pull that wrote nothing
 * it cares about. Rows are matched by position first and by key second, so a
 * result with duplicate keys still diffs sensibly.
 */
export function diffRows<T extends Record<string, unknown>>(
  previous: T[],
  next: T[],
  key: string,
): { rows: T[]; changed: boolean } {
  if (previous.length === next.length) {
    let identical = true;
    const rows: T[] = new Array(next.length);
    for (let i = 0; i < next.length; i++) {
      const before = previous[i] as T;
      const after = next[i] as T;
      if (before !== undefined && before[key] === after[key] && sameValues(before, after)) {
        rows[i] = before;
      } else {
        rows[i] = after;
        identical = false;
      }
    }
    if (identical) return { rows: previous, changed: false };
    return { rows, changed: true };
  }

  const byKey = new Map<string, T[]>();
  for (const row of previous) {
    const id = String(row[key]);
    const bucket = byKey.get(id);
    if (bucket) bucket.push(row);
    else byKey.set(id, [row]);
  }

  const rows = next.map((row) => {
    const candidates = byKey.get(String(row[key]));
    const match = candidates?.find((candidate) => sameValues(candidate, row));
    return match ?? row;
  });

  return { rows, changed: true };
}
