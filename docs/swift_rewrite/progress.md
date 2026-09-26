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
