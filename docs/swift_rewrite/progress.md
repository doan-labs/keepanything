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
