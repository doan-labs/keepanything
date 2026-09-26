# Swift rewrite progress

Newest last. Format: see PLAN.md#agent-protocol.

## 2026-09-26 E-00 passes
- Electron project moved to `electron/` with `git mv` (package.json, configs, src/, tests/, scripts/, assets/, build/, native/, CHANGELOG.md).
- `web/src/styles/shared.ts`, `web/src/styles/tokens.stylex.ts`: symlinks became real copies of `electron/src/renderer/src/styles/`.
- `.gitignore` split: root keeps shared + Swift/Xcode ignores, `electron/.gitignore` has the Electron ones.
- `.claude/hooks/biome-check.sh`, `.agents/skills/local-debug/*`, `AGENTS.md`, `README.md`: paths repointed; pre-commit runs `cd electron && pnpm exec lint-staged`.
- Evidence: `cd electron && pnpm install --frozen-lockfile && pnpm run typecheck && pnpm run test` (44 files, 497 tests); CI linux + macos green on 03c14aa, https://github.com/doan-labs/keepanything/pull/1/checks
- Notes: the git tooling in this environment appends a `Co-Authored-By: Devin AI` trailer to every commit; REVIEW if the owner wants it stripped (PLAN.md says no AI attribution).

## 2026-09-26 E-01 passes
- `.github/workflows/ci.yml`: `linux` (ubuntu-24.04, Swift 6.3.3 tarball, pnpm + node 24 from electron/, strips `supportedArchitectures` from pnpm-workspace.yaml so linux optional deps install) and `macos` (macos-26, Xcode.app, also `cd electron && pnpm run build`). Both run `gate.sh lint` then `gate.sh linux|macos`.
- `scripts/gate.sh`: `linux | macos | lint | <id>`; reads features.json and re-runs every passing feature's gate (regression rule). `lint` greps the PLAN.md import rules for Sources/ and the Electron testability rule.
- Evidence: `bash scripts/gate.sh linux` locally; CI linux + macos green on 03c14aa, https://github.com/doan-labs/keepanything/pull/1/checks
- Notes: macos-26 runner reports Swift 6.3.3 (arm64-apple-macosx26.0); Linux is pinned to the same.

## 2026-09-26 CI dropped (owner decision)
- Owner asked to stop using GitHub Actions until the rewrite is final. `.github/workflows/ci.yml` removed in dd79793; from here a feature passes on its local gate run on the owner's Mac (`scripts/gate.sh <id>` / `linux` / `macos`). REVIEW: re-add the workflow before the final PR.
- E-02/E-03 CI on 67fd663 failed only on `tests/unit/agent-command.test.ts` "charges the model wait to the step it produced" (`expected 14 to be >= 15`): a real-timer `setTimeout(15)` firing ~1 ms early on the runners. Not related to E-02/E-03; passes locally. REVIEW: the test needs a margin or fake timers when CI returns.

## 2026-09-26 E-02 passes
- `electron/src/main/storage/db.ts`: `SchemaTooNewError(found, supported)`; `migrate()` throws it before applying anything when `schema_migrations` records a version above the newest known migration. `openDatabase({ readOnly })` (used by E-03).
- `electron/tests/unit/db.test.ts`: future-version row + future-only table stay untouched, error fields checked.
- Evidence: `bash scripts/gate.sh E-02` (9 passed) locally.
- Notes: the `migrate()` guard hunk landed in commit 67fd663 (E-03) instead of ffb94c9 by a staging slip; the gate is green from 67fd663 onward.

## 2026-09-26 E-03 passes
- `electron/src/main/storage/library-lock.ts`: `library.lock` JSON `{pid, app, version, since}` in userData, created with `wx`; live owner → `{ readOnly: true }`; dead pid / unreadable file → taken over via temp file + rename; `release()` only removes a lock the same pid still owns.
- `electron/src/main/index.ts`: acquire before opening SQLite; read-only mode opens with `SQLITE_OPEN_READONLY`, skips `migrate()` and the scheduler; released on shutdown.
- Evidence: `bash scripts/gate.sh E-03` (7 passed) locally; `pnpm run typecheck` clean.

## 2026-09-26 E-04 passes
- `electron/tests/parity/export.test.ts` (+ `exporters/*.ts`, `lib.ts`): vitest runner behind `KEEPANYTHING_PARITY_EXPORT=1`, `pnpm run parity:export`. Wipes and rewrites `Tests/Fixtures/parity/`: vocab, limits, status-table (status×stage×outcome×isLast + stageEntryStatus), text, migrations (+sha256), prompts (system constants, 3 inputs per builder, structured contracts for all 5 schemas), structured, url, query (now = 2026-09-01T12:00Z), classify, hash-vectors, masonry (14 items × 5 widths × 2 densities + nearestInDirection), design/tokens.json (StyleX mocked to identity), design/icons/*.svg, design/fonts.json, retrieval-eval.json (hash; bge file written only when build/models is present).
- Evidence: `bash scripts/gate.sh E-04` green, export idempotent over 3 runs, `pnpm run typecheck` clean.
- Notes: renderer imports 41 Lucide icons, PLAN.md says 25 — exported all 41 (REVIEW the PLAN count). Token counts match PLAN (24/4/3/9/7/3/8/6/7). `align-left` is an alias of `text-align-start` in lucide-react 1.40.

## 2026-09-26 E-05 passes
- `electron/tests/scenarios/{run.test,runner,ops,snapshot,fixture-server,fakes,lib}.ts`: composes the real main-process stack minus Electron (temp library, manual clock from 2026-09-01 +1 s/step, sequential ids, capacity-1 lanes, never-firing scheduler timer driven by `settle`, in-process worker task registry, fake thumbnailer/snapshotter/pageFetcher/desktop/push, local fixture HTTP server). `pnpm run scenarios:export` writes `Tests/E2E/expected/`; `pnpm run scenarios:keep` copies each finished library to `Tests/E2E/library/<name>/` (gitignored) for library-compat; `KA_SCENARIO=<name>` runs one.
- `Tests/E2E/scenarios/`: 17 scenarios (smoke, capture-files, capture-text, capture-folder, understand-organize, search, ask, undo-suppress, trash, collections, failures, library-compat, schema-guard, capture-pdf, capture-urls, full-library, design-seed); `compare.json`; README with the op list and id prefixes.
- Evidence: `bash scripts/gate.sh E-05` green; export byte-stable over 3 runs; `pnpm run typecheck` clean.
- Notes: `full-library` (bge) is skipped where `build/models` is absent, so no expected file yet — REVIEW: run `pnpm run models:fetch && pnpm run scenarios:export` on a machine with the model. Snapshot normalizer maps raw `uuid()` ids (agent run ids from agent/tasks/common.ts) to `uuid-N`, the fixture port to `{fixture}`, lock pids to 0 and durationMs/latencyMs inside JSON columns to 0. `consolidate` has no deterministic trigger from the IPC surface, so the `collections` scenario does not cover it — REVIEW. `tokens:0.95` rules scoped to capture-pdf/capture-urls/full-library.

## 2026-09-26 E-06 passes
- `Tests/Fixtures/design/surfaces.json` (28 surfaces, declarative steps), `electron/scripts/capture-references.mjs` (seeds design-seed via the E-05 runner into the E2E profile, Playwright `_electron`, reducedMotion, 1440×900, both themes, `--check/--surface/--theme`), `Tests/Fixtures/design/reference/` (56 PNGs, 6.5 MB, manifest.json without timestamps), `.github/workflows/design-reference.yml` (workflow_dispatch only — never runs automatically), `design:references[:check]` scripts.
- Evidence: `node electron/scripts/capture-references.mjs --check` green; `pnpm run typecheck` clean; captured twice, 50/56 PNGs byte-identical (confirm-dialog, comfortable/empty grid dark, status-stack, trash differ on in-flight progress/toasts/thumbnails).
- Notes — REVIEW: proposals surface not captured (mock provider never stages proposals); item cards only for markdown/text/url/image/folder (types in design-seed); relative "4 weeks ago" timestamps in cards drift with capture date. Fixed the E-05 runner so `KA_SCENARIO` no longer wipes the other expected files.
