# Browser smoke check

Run once per release, and after any change to `src/adapters/`. Node tests cover
everything else; this is the only proof that OPFS and the IndexedDB snapshot
work in a real browser.

## Run it

```bash
cd packages/core
npx vite examples/browser-smoke --open
```

## What must happen

| Browser | Expected `backend:` line | Expected on reload |
|---|---|---|
| Chrome/Edge 108+ | `opfs` | the row count grows every reload |
| Firefox 111+ | `opfs` | the row count grows every reload |
| Safari 17+ (macOS/iPadOS) | `opfs` | the row count grows every reload |
| Safari 16 | `indexeddb` (with an OPFS warning) | the row count grows every reload |
| Private window / storage blocked | `memory` with the "not persistent" warning | the count restarts at 1 |

A `FAIL:` line, a `backend: memory` where the table above expects otherwise, or a
count that restarts on reload is a release blocker. Record the browser, the
version and the `backend:` line in the release notes.
