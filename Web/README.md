# Embedded workspace

React + TypeScript + Vite, using the MIT ReUI Kanban, Data Grid, Gantt and Event Calendar primitives on shadcn Base UI (Nova). Swift owns persistence, event identity, source data and credentials. This directory only renders snapshots and sends a bounded command contract.

```sh
npm ci
npm test
npm run lint
npm run build
```

`dist/` is copied to `Syllapace.app/Contents/Resources/Workspace/`. Relative asset paths and a strict CSP keep the release offline. `postbuild` collects local dependency license texts and rejects development-fixture markers in the generated JavaScript.

For an isolated synthetic development preview: `npm run dev`, then `http://127.0.0.1:5173/?preview=1`. Optional query values are `view=kanban|gantt|calendar`, `lang=zh`, `theme=dark`, and `empty=1`. The preview module is guarded by `import.meta.env.DEV` and eliminated from production. It never reads the user's archive or credentials.

## Bridge

The native shell calls `window.syllapace.receive(snapshot)`. Its promise resolves after two animation frames so native capture waits for React rendering. `workspace.ready` also receives the current snapshot. Older revisions are ignored.

Commands use `window.webkit.messageHandlers.workspace.postMessage({id, method, payload})` and receive `{ok, snapshot?, error?}`. Exact DTOs and command payloads live in `src/workspace/types.ts`; Swift validates these again. Changes send the expected event revision and render the authoritative native reply. Error feedback offers retry, and source text is never HTML.

## View semantics

- List and Calendar show the same scoped academic events; Calendar includes only dated records.
- Kanban shows submission tasks with independent `todo`, `doing`, and `done` progress. Urgency is derived from the source deadline; it is never a fourth progress status.
- Gantt defaults to deadline/exam milestones and user-created work plans; the Classes filter also shows real meeting intervals. No project start or duration is invented. Resizing a plan's start changes `plannedStart` only, never a Canvas deadline.
- Date-only values remain calendar dates in the event timezone. A same-day work plan is normalized to that timezone's start of day. Timed deadlines remain exact instants and use the same local display timezone in every view. The calendar opens around 09:00.

The narrowly scoped DST coordinate correction to the vendored calendar is documented in [REUI-PATCHES.md](REUI-PATCHES.md).

Native-window screenshots are the release acceptance evidence. DOM tests exercise the bridge, view switching and stale responses; they do not establish macOS visual correctness.

## Licenses

`LICENSE.reui.md` contains ReUI's MIT notice. The build copies it and installed runtime dependency notices into `dist/THIRD_PARTY_NOTICES.txt`. No paid ReUI blocks, templates or Motion Icons are included in this public source tree.
