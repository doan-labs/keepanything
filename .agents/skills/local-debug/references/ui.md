# UI Verification

| Need | Use |
| --- | --- |
| Check a change in the running dev app (real dev library, hot reload) | `cdp.mjs` against `pnpm run dev --remoteDebuggingPort 9222` |
| Layout of every card state, no library at all | the renderer in headless Chromium with the mock bridge |
| A clean, repeatable capture (seeded content, 1440x900, forced theme, native chrome) | `pnpm run screenshot` |
| A check that should keep running | a Playwright `_electron` test in `tests/e2e/` |

Screenshots go in `.artifacts/` (gitignored). Read the PNG after capturing it; a written file proves nothing.

## Live dev window (`cdp.mjs`)

Pre-flight: `.agents/skills/local-debug/scripts/ka.sh ps` shows `listening=9222` on the dev pid.
If it does not, ask the user to restart dev with `pnpm run dev --remoteDebuggingPort 9222`
(electron-vite passes the port in dev only, so it never reaches a packaged build).

```bash
node .agents/skills/local-debug/scripts/cdp.mjs snap                 # accessibility tree: headings, buttons, cards, states
node .agents/skills/local-debug/scripts/cdp.mjs shot                 # -> .artifacts/live.png
node .agents/skills/local-debug/scripts/cdp.mjs console 15           # console + page errors while the user reproduces
node .agents/skills/local-debug/scripts/cdp.mjs invoke items:list '{"view":"library","limit":5}'
node .agents/skills/local-debug/scripts/cdp.mjs invoke items:get '{"id":"<id>"}'
node .agents/skills/local-debug/scripts/cdp.mjs invoke jobs:status
node .agents/skills/local-debug/scripts/cdp.mjs invoke search:quick '{"query":"invoice"}'
KA_VIEW=shelf node .agents/skills/local-debug/scripts/cdp.mjs snap   # the Shelf window
```

- `invoke` returns the `IpcEnvelope`: `{ ok: true, data }` or `{ ok: false, error }`. Payloads are
  zod-validated in main, so a wrong shape comes back as an error, not a crash. Channel payloads are
  in `src/shared/ipc.ts` (`IpcRequestMap`).
- Read channels run freely. Every other channel (`items:trash`, `capture:*`, `settings:update`,
  `agent:command`, `settings:testConnection`, ...) and `eval` need `KA_WRITE=1` after the user agrees.
- `shot` captures web contents only: no traffic lights, and no vibrancy behind the translucent
  sidebar. Use `pnpm run screenshot` when the native chrome matters.
- Prefer `snap` to `shot` for structural checks: it is cheaper, and its names are what Playwright
  selects by (`getByRole('button', { name: 'Settings' })` in `scripts/screenshot.mjs`).

### Before/after a change

```bash
node .agents/skills/local-debug/scripts/cdp.mjs shot .artifacts/before.png
node .agents/skills/local-debug/scripts/cdp.mjs snap > .artifacts/before.txt
# edit: renderer files hot-reload; main/preload edits restart the app (check ka.sh ps for the new pid)
node .agents/skills/local-debug/scripts/cdp.mjs shot .artifacts/after.png
node .agents/skills/local-debug/scripts/cdp.mjs snap | diff .artifacts/before.txt -
```

## Renderer with the mock bridge

With no preload bridge, the renderer falls back to `createMockBridge()` (`src/renderer/src/lib/mock-fixtures.ts`):
about 18 fixture items covering every card state, collections and activity. Nothing touches a library.
Take the renderer port from `ka.sh ps` (`renderer-port=`):

```bash
pnpm exec playwright screenshot --viewport-size=1440,900 --wait-for-timeout=1500 \
  "http://localhost:<renderer-port>/?view=library" .artifacts/mock.png
```

Use `?view=shelf` for the Shelf. There is no vibrancy here either, and IPC calls answer from the fixtures.

## Built app (`pnpm run screenshot`)

Builds, launches against the `e2e` profile, seeds placeholder content into an empty library, sets
the window to 1440x900 and captures with `screencapture` (falling back to the page capture without
Screen Recording permission). Output: `.artifacts/screenshot.png`.

```bash
pnpm run screenshot                                # dark, seeded library
pnpm run screenshot -- --theme light               # -> .artifacts/screenshot-light.png
pnpm run screenshot -- --empty --reset             # empty state on a fresh profile
pnpm run screenshot -- --palette "invoice"         # the Cmd+K palette with a query typed
pnpm run screenshot -- --settings --settings-section "Provider"
pnpm run screenshot -- --activity
```

It uses the `e2e` profile, so do not run it while `pnpm run test:e2e` is running.
