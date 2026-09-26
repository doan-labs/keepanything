# KeepAnything Swift Rewrite

Status: approved for execution, 2026-09-26. One plan, one checklist: this file plus
[`features.json`](features.json). Agents start at [Agent protocol](#agent-protocol).

## Goal

Rewrite KeepAnything as a native macOS app in Swift, desktop only, with the same behavior,
library format and look as the Electron app.

**Done means:**

1. Every entry in `features.json` has `"passes": true`.
2. Every end-to-end scenario produces the same result in Swift as in Electron.
3. An existing Electron library opens in the Swift app with no migration step.
4. Every UI surface matches its Electron reference screenshot. A human signs this off.
5. The last Electron update installs the Swift app.

**Non-goals:** iOS, Windows, new features, redesign. Product changes come after parity.

## Decisions

These are settled. Do not reopen them in a session; write a note for review instead.

| Decision | Choice |
| --- | --- |
| Platform | macOS desktop only, minimum macOS 15 |
| Toolchain | Swift 6 language mode, strict concurrency on; the toolchain version on the `macos-26` CI runner, pinned the same on Linux |
| UI | SwiftUI, with AppKit for panels, the status item and drag-watch |
| Distribution | Developer ID, notarized, not sandboxed, Sparkle 2. No Mac App Store |
| Bundle ID | `com.doanlabs.keepanything`, the same as Electron, so its last update can install the Swift app |
| Library | `~/Library/Application Support/KeepAnything` (dev: `.../dev`), the same folder and format |
| Repo | SwiftPM package at the root, thin Xcode project in `App/`, Electron moved to `electron/` |
| Look | The current design, unchanged: same tokens, Instrument Serif, the same Lucide icons (not SF Symbols) |

**Dependencies, four, no others without human approval:**

- [GRDB](https://github.com/groue/GRDB.swift) 7.x: SQLite, WAL, observation. Needs Swift 6.1+. Linux support is community-maintained, so a Linux-only GRDB failure is a note, not a blocker.
- [onnxruntime-swift-package-manager](https://github.com/microsoft/onnxruntime-swift-package-manager) 1.24.x: macOS only (binary from `download.onnxruntime.ai`). Linked only on macOS through a platform condition.
- swift-transformers `Tokenizers`: reads the model's `tokenizer.json`. If it is too heavy or breaks Linux, the fallback is a small WordPiece port (bge-small is a BERT tokenizer). Decide in feature `S-EMB-02`.
- [Sparkle 2](https://sparkle-project.org): app target only.

Everything else comes from the stdlib, Foundation or an Apple framework. zlib is linked as a system library (it exists on macOS and Linux), so ZIP reading is one code path on both.

## The Electron app stays

The Electron app moves to `electron/` and stays in the repo for the whole rewrite, for four jobs:

1. **It is the spec.** Swift ports its behavior; it does not improve on it. It is frozen to fixes.
2. **It generates the expected results.** Parity fixtures, end-to-end scenario results and design references all come from it. Nobody writes an expected value by hand.
3. **It stays runnable.** `cd electron && pnpm run dev`, to compare both apps on a copy of the same library.
4. **It is the fallback.** Until cutover, users run it.

A fix to Electron during the rewrite that changes behavior also regenerates the fixtures in the same commit.

**Deletion:** at cutover, tag the last Electron commit `electron-final`. `electron/` is deleted only after the first Swift release has been in users' hands without a rollback, and only by a human.

## How work is verified

Work is verified end to end. Unit tests exist, but a feature passes only when it works as part of the running app or the headless library, and matches Electron.

### Gates

| Gate | Where | What runs | Used for |
| --- | --- | --- | --- |
| **Linux** | cloud session, and the `linux` CI job | `swift build`, `swift test` without Apple frameworks, `cd electron && pnpm run typecheck && pnpm run test` | fast inner loop for the pure core and the Electron side |
| **macOS** | the `macos` CI job on `macos-26` | everything: full `swift test`, the end-to-end scenarios, `xcodebuild test` (app build and XCUITest), `cd electron && pnpm run build` | the real gate for every feature |
| **Human** | the owner's Mac | signing, notarization, Sparkle keys, the cutover test, design sign-off | features with `"runs_on": "human"` |

A feature passes only when **its own gate** is green **and** CI is green on both jobs for the commit that flips it.

**Regression rule:** `scripts/gate.sh` reads `features.json` and runs the gate of every feature that already passes. CI runs it on every push. A feature that passed and breaks is fixed before any new feature starts.

### End-to-end scenarios

A scenario is a script of user actions against a throwaway library, run headless by both apps, with the results compared.

```
Tests/E2E/
  scenarios/<name>.json      hand-written, the only editable part
  expected/<name>.json       written by the Electron runner, never edited by hand
  compare.json               per-field comparison rules
```

**Scenario format:**

```json
{
  "name": "understand-and-organize",
  "runs_on": "linux",
  "ai": "mock",
  "embeddings": "hash",
  "steps": [
    { "op": "capture.files", "paths": ["notes/inference-providers-notes.md", "notes/weekly-review-2026-08-28.md"] },
    { "op": "capture.text", "text": "Compare GMI Cloud and OpenRouter pricing for MiniMax-M3." },
    { "op": "settle" },
    { "op": "search", "query": "cheap inference providers" },
    { "op": "agent.command", "text": "What am I researching here?" },
    { "op": "snapshot" }
  ]
}
```

`ops` map 1:1 onto the Electron IPC channels (`items.*`, `capture.*`, `collections.*`, `relationships.*`, `search.quick`, `agent.*`, `settings.update`), plus these runner ops:
- `settle`: waits until the pipeline is idle.
- `snapshot`: dumps the library state (items, collections, relationships, suppressions, audit rows, agent runs, FTS rows, job states).
- `advance`: moves the clock.
- `open-library`: opens an existing library directory.

Paths are relative to `tests/fixtures/corpus/files/`.

**Determinism.** Both runners use:
- a manual clock starting at `2026-09-01T00:00:00Z` that advances 1 s per step;
- sequential ids;
- every pipeline lane at capacity 1;
- the mock AI provider, or the scripted one with replies in the scenario;
- hash embeddings on Linux; bge is allowed only in `runs_on: macos` scenarios;
- fake thumbnailer and snapshotter that record calls and write nothing;
- a local HTTP server serving `tests/fixtures/html/` and JSON stubs for URL captures.

With that, the results should be byte-identical, so the default comparison is exact.

**`compare.json`** holds the only allowed exceptions, per JSON path:
- `ignore`: durations, `latencyMs`, absolute paths;
- `float:1e-4`;
- `tokens:0.95`: token-set overlap, only for text from a different extractor, such as PDFKit vs `unpdf`.

**Scenarios whose later steps depend on extracted text** (AI, relationships, collections, search) only capture inputs whose extraction is ported code: text, markdown, code, images, folders, ZIPs and saved HTML. PDFs and live-rendered pages get their own scenarios that stop after extraction, so an extractor difference cannot cascade.

**Runners:**
- **Electron:** `electron/tests/scenarios/run.test.ts`, a Vitest file that runs only with `KEEPANYTHING_SCENARIOS=1`. It composes the real main-process services the way `src/main/index.ts` does, minus Electron, and writes `expected/`. It runs as a Vitest file because the migrations are `?raw` imports and only the Vite transform resolves them. Command: `cd electron && pnpm run scenarios:export`.
- **Swift:** the `KAE2ETests` test target runs every scenario in-process against `KALibrary` and diffs against `expected/`. Command: `swift test --filter KAE2ETests`. `KA_SCENARIO=<name>` runs one.

**Library compatibility:**
- The Electron runner can keep the library directory it produced (`--keep-library`).
- Scenario `library-compat` opens that directory in Swift and must snapshot identically.
- Scenario `schema-guard` must see Swift refuse a newer schema.

### UI end to end

XCUITest in `App/MacUITests`, over a throwaway library.

1. **Seeding:** the app is launched with `-KAScenario <name>`, which runs a scenario into a temp library before the window opens. Debug builds only, like `KEEPANYTHING_E2E`.
2. **Behavior:** each surface has a test that drives it through keyboard, clicks and the pasteboard, then checks the accessibility tree.
   - Examples: capture a file by paste, search from the palette, open detail, trash and restore, Ask, create a collection.
   - Every interactive view has an accessibility identifier: `card-<id>`, `palette-input`, `sidebar-collections`.
3. **Geometry:**
   - Card frames at a 1440×900 window must match the masonry fixture within 1 pt.
   - Sidebar width, titlebar height and toolbar height must equal the tokens.
4. **Screenshots:** each surface in `design/surfaces.json` is captured in both themes.
   - CI builds a side-by-side of reference and Swift for each one, with a pixel-difference score, and uploads them as the `design-review` artifact.
   - The score is reported, not gated.
   - Design sign-off is a human feature for each surface.

## Keeping the design

The Swift app keeps the Electron design. Values are generated, not copied.

1. **Tokens:**
   - `export-parity` writes `tokens.stylex.ts` and `themes.ts` to `Tests/Fixtures/parity/design/tokens.json`:
     - 24 colors in dark and light;
     - 4 shadows;
     - 3 radii, 9 spacing steps, 7 text sizes, 3 weights;
     - 8 motion values, 6 layout values, 7 z-indices.
   - `scripts/gen-theme.swift` generates `Sources/KAUI/Theme+Generated.swift` from it.
   - A test asserts the generated file matches the JSON.
   - Views use `Theme` only; no literal colors, radii or durations.
2. **Themes:** `system | light | dark` from settings. `system` follows the macOS appearance. The accent override stays.
3. **Fonts:**
   - UI text uses the system font, which is the same SF face the Electron stack resolves to.
   - Instrument Serif (Regular and Italic) is bundled from `electron/assets/fonts/`.
   - The serif is used in the same five places: sidebar, empty state, item card, detail and shelf headlines.
4. **Icons:**
   - `export-parity` renders the 25 Lucide icons the renderer uses to SVG, from the `iconNode` data in the installed `lucide-react`. No new package.
   - They go into the asset catalog as vector symbols, with stroke 1.5, round caps and `currentColor`.
   - The 5 animated sidebar icons are ported as SwiftUI shapes from the same paths, with the same motion: ease `(0.16, 1, 0.3, 1)`, 0.42 s perform, 0.32 s release, and 0.014 s under reduced motion.
5. **Layout:**
   - `lib/masonry.ts` is ported verbatim: `TYPE_RATIO`, column count, shortest-column placement, `nearestInDirection`.
   - `export-parity` writes layouts for fixed inputs at several widths, and a Swift test asserts equality.
   - Constants: caption 44, gap 14, min column 220 (comfortable) or 168 (compact).
6. **Motion:**
   - CSS transitions map to SwiftUI animations with the token durations and curves.
   - `@scritto/react` counters map to `.contentTransition(.numericText())`.
   - Everything respects `accessibilityReduceMotion`.
7. **References:**
   - `electron/scripts/capture-references.mjs` opens the real Electron app on the library from scenario `design-seed`.
   - It captures every surface in `design/surfaces.json` in both themes at 1440×900, into `Tests/Fixtures/design/reference/`.
   - It runs on macOS (the `design-reference` CI job, dispatched manually, or the owner's Mac), because Linux lacks the SF fonts.
   - References are regenerated only when the Electron UI changes.

Surfaces, from the renderer's component tree:
- library grid: comfortable, compact, empty;
- item card for each type;
- detail;
- palette: idle and results;
- Ask: running and answered;
- selection bar;
- collections grid, collection header, proposals;
- trash;
- activity;
- settings: each section;
- toasts;
- confirm dialog;
- drop overlay;
- status stack;
- shelf.

## Repo layout

```
keepanything/
  Package.swift                 KeepAnythingKit: every module and test target
  Sources/
    KAModel/ KAStorage/ KACore/ KACapture/ KAExtraction/ KAPreviews/
    KAEmbeddings/ KAAI/ KARetrieval/ KAAgent/ KAPipeline/ KALibrary/ KAUI/
    KATestSupport/              scenario runner, fixture server, fakes (test-only)
  Tests/
    KAModelTests/ ... KALibraryTests/  KAE2ETests/
    Fixtures/parity/            written by electron export-parity, never hand-edited
    Fixtures/design/reference/  Electron reference screenshots
    E2E/                        scenarios, expected results, compare.json
  App/
    KeepAnything.xcodeproj      thin targets, folder-synced groups
    Mac/ MacShare/ MacUITests/ Resources/ Config/
  electron/                     the whole Electron project, frozen
  scripts/gate.sh               runs the gates in features.json
  .github/workflows/ci.yml      linux + macos jobs
  web/ docs/                    unchanged
```

### Targets

| Target | Links | Job |
| --- | --- | --- |
| `KeepAnything` (app) | KALibrary, KAUI, Sparkle | library window, shelf, menubar, palette, settings, drag-watch, inbox watcher; the only process that writes the database |
| `KeepAnythingShare` (appex) | KAModel | writes the shared payload to `<AppGroup>/inbox/<uuid>.json` plus copied files, then exits; never opens the database |
| `KeepAnythingKitTests` | every module | unit, parity and scenario tests (`swift test`) |
| `MacUITests` | the app | XCUITest over a throwaway library |

The app watches `inbox/`, feeds each envelope to the normal capture intake, then deletes it.

### Modules

Each module ports one Electron folder. Keep the TS function names in camelCase Swift, so a port can be read side by side.

| Module | Ports | Linux | Notes |
| --- | --- | --- | --- |
| `KAModel` | `src/shared/` | yes | types, kinds, status table, constants, text helpers, media URLs, layout |
| `KAStorage` | `storage/` | yes | GRDB `DatabasePool`, migrations run verbatim from bundled `.sql`, repositories, object store, paths, reset-data |
| `KACore` | `core/` | yes | item, collection and relationship services, audit, event bus, errors, ids |
| `KACapture` | `capture/` | yes | intake, classify (`mime` → a ported extension table, since UTType doesn't exist on Linux), folder scan, URL canonicalization |
| `KAExtraction` | `extraction/` | partly | ported pure parsers: text, front matter, image-dims, EXIF, ZIP/TAR via zlib, spreadsheet. PDFKit and WKWebView (Readability + Turndown) adapters behind `#if canImport` |
| `KAPreviews` | `previews/` | no | `QLThumbnailGenerator`, WKWebView snapshots, dominant color; fakes in `KATestSupport` |
| `KAEmbeddings` | `ai/embeddings/` | hash only | hash fallback everywhere; ORT + tokenizer on macOS, in an `Embedder` actor that loads lazily |
| `KAAI` | `ai/` | yes | URLSession transport with SSE, `structured`, prompts, schemas, mock and scripted providers |
| `KARetrieval` | `retrieval/` | yes | FTS, vectors, RRF hybrid, query and cue parsing, context cards |
| `KAAgent` | `agent/` | yes | orchestrator, tool loop, understand, organize and consolidate tasks, tools |
| `KAPipeline` | `pipeline/` | yes | graph, queue, scheduler actor with lanes, state, stages |
| `KALibrary` | `ports.ts` + `ipc/handlers` | yes | the one facade the app imports; one async method per IPC channel (48), one `AsyncStream` per push event (10) |
| `KAUI` | `src/renderer/` | no | SwiftUI views, `Theme`, `@Observable` models over GRDB `ValueObservation` |

**Import rules**, checked by a grep in `scripts/gate.sh lint`:
- Only `KAUI` and `App/` import SwiftUI; only `App/` imports AppKit.
- No module reads the environment, `UserDefaults` or the Keychain. `App/` passes values in, as `ports.ts` does.
- Apple-only code sits behind `#if canImport(<Framework>)`, with the Linux branch throwing `KaError.unsupported`.

### Technical mapping

- **Storage:** `node:sqlite` → GRDB. Same `schema_migrations` table. `transaction` + `afterCommit` → `write {}` + post-commit callbacks. The FTS5 tokenizer `porter unicode61 remove_diacritics 2` comes from system SQLite on both platforms. Vectors stay little-endian Float32 blobs, L2-normalized, filtered by `model`.
- **AI:**
  - Transport: `openai-compatible.ts` → URLSession `bytes(for:)` for SSE, with task cancellation in place of `AbortSignal`.
  - Parsing: zod → `Codable` plus `validate() -> [String]`. Structured output keeps the same order: raw parse, then last fenced block, then balanced object, then one retry with the errors.
  - Quirks: strip `<think>`, never persist `reasoning_content`, reject `finish_reason: length`.
  - Provider behavior the ports must keep:
    - `response_format` has no effect.
    - A named `tool_choice` and `tool_choice: none` are both ignored, so the last step is forced with `tools: [finish]` + `tool_choice: required`.
    - Images go as data URIs only.
    - 429 and 5xx get up to 3 retries with jittered backoff, honoring `retry-after` up to 15 s. Timeout is 60 s.
- **Embeddings:** the same `bge-small-en-v1.5` q8 `.onnx` file on ORT, 384-d, cls pooling, normalized, model id `Xenova/bge-small-en-v1.5`. The hash fallback is FNV-1a over lowercase, then NFKD, then `[^a-z0-9]+` tokens.
- **Extraction and previews:** `unpdf` → PDFKit. Readability + Turndown are bundled JS run in an offscreen WKWebView, which also replaces `linkedom`. `qlmanage` → `QLThumbnailGenerator`. BrowserWindow snapshots → WKWebView `takeSnapshot`. WebKit work runs on one `@MainActor` `WebRenderer`.
- **Pipeline:** lanes (io, embed, ai) → `TaskGroup`s with per-lane limits in a `Scheduler` actor. Stages return a `StagePatch`; only the scheduler writes `items.status`; transitions come from `status.next()`; stage bodies stay idempotent.
- **Desktop:**
  - `ka-media:` → file URLs checked with `LibraryPaths.contains`.
  - Secrets: `safeStorage` → Keychain. The API key is re-entered once; nothing is read from Electron's store.
  - Settings: `settings.json` is read as-is.
  - Flags: `KEEPANYTHING_*` → scheme environment, read only in `App/`.
  - Logging: `os.Logger` plus the same redacting file log.
- **UI:**
  - State: zustand stores → `@Observable` models.
  - Windows: cmdk → `NSPanel` + SwiftUI. Shelf → non-activating `NSPanel`. Tray → `NSStatusItem`, positioned from click-event bounds. The `native/drag-watch` sidecar → an in-process global event monitor. Preview → `QLPreviewPanel`.
  - Updates and dialogs: electron-updater → Sparkle. `confirm()` → one `ConfirmModel`.
  - Rules that carry over: anything that interrupts work asks through `ConfirmModel`, motion respects reduced motion, no emoji, no gradients.

**Deleted, not ported:**
- `worker/` and `worker-client`: actors replace them.
- `ipc/` router, envelope and schemas, `preload/`, `ipc-client` and `mock-bridge`: `KALibrary` replaces them.
- `desktop/media-protocol`, `dom-fallback` and `security` (CSP).
- electron-builder, electron-vite and the StyleX build.

## Milestones

`features.json` is the ordered checklist; this is its shape. Each milestone ends with something that runs.

| # | Milestone | Ends with |
| --- | --- | --- |
| M0 | Foundation, Electron side | Electron in `electron/` with the guards; parity fixtures, scenario runner and expected results committed; CI green; references captured |
| M1 | Package, model, storage | `swift test` green on Linux and macOS; Swift opens an Electron-made library |
| M2 | Headless core | every `linux` scenario matches Electron: capture, understand, organize, search, Ask, undo, trash |
| M3 | Apple adapters | PDF, web readability, thumbnails, snapshots, bge embeddings; the `macos` scenarios and the retrieval eval match |
| M4 | App and UI | every surface built, driven by XCUITest, geometry matching; design review artifacts produced |
| M5 | Capture surfaces | shelf, menubar, drag-watch, share extension and inbox, each driven end to end |
| M6 | Release (human) | signed, notarized, Sparkle feed, cutover verified with a dummy app, final Electron release |

## Agent protocol

Rules for a cloud agent running unattended. They override convenience.

### Session start

1. Read this file, `features.json`, the last entries of `docs/swift_rewrite/progress.md`, and `git log --oneline -20`.
2. Run `scripts/gate.sh linux`; after M0, also check the last CI run on `main` (`gh run list --branch main --limit 1`).
   - Red means fixing it is this session's first task.
   - `scripts/gate.sh` and CI exist only after M0. Before that, skip this step.
3. Pick the **first** feature in file order that has `"passes": false`, `"blocked": null`, `runs_on` not `human`, and every id in `depends` passing. Work on one feature at a time.

### Per feature

1. Read every file in the feature's `spec` list, and the Electron unit tests that cover them.
2. Port the tests first: the mirrored unit cases, then the parity-fixture assertions, then the scenario.
3. Port the code until the feature's `gate` passes locally. On Linux, `macos` gates run in CI only.
4. Commit with the message `swift: <id> <title>` and push. Push after every commit, because the VM can be reclaimed and uncommitted work is lost.
5. Wait for CI on that commit: `gh run list --branch "$(git branch --show-current)" --limit 1`, then `gh run watch <id>` or poll `gh run view <id>`. Read failures with `gh run view <id> --log-failed`.
6. When the gate and both CI jobs are green, set `"passes": true`, append a progress entry, commit `swift: <id> passes`, and push.

### Progress entry

Append to `docs/swift_rewrite/progress.md`, newest last:

```
## <date> <feature id> passes|blocked
- What changed (files, one line each).
- Evidence: gate command, CI run URL.
- Notes for the next feature or for review (optional).
```

### Stop rules

- **Three strikes.** The same gate still fails after three distinct fix attempts: set `"blocked"` to a one-line reason, write a progress entry with the failing output, and move to the next eligible feature.
- **Spec questions.** Never edit anything under `Tests/Fixtures/parity/`, `Tests/Fixtures/design/` or `Tests/E2E/expected/`, and never edit `electron/src/`. If the Electron behavior looks wrong, or two parts of the spec disagree, block the feature with `spec question: ...`.
- **Loosening.** A new `compare.json` rule, a skipped test, or a gate made weaker is allowed only with a progress entry marked `REVIEW`, and never for exact-match parity files (prompts, vocab, status table, tokens, masonry).
- **Scope.** No new dependency, no product change, no refactor of Electron, no edit to other features' `passes`. `features.json` edits are limited to `passes`, `blocked` and `notes`.
- **Safety.**
  - Never open the real library under `~/Library/Application Support/KeepAnything`; tests use temp directories.
  - No secrets in code, fixtures, logs or prompts; the mock and scripted providers need none.
  - No AI attribution in commits or PRs.
- **Nothing left:** every remaining feature is passing, blocked or `human`. Stop and write the session summary.

### Session end

Open or update one PR from the session branch to `main`, titled `swift rewrite: <first id>…<last id>`. The body lists:
- features passed, with CI links;
- features blocked, with reasons;
- `REVIEW` items;
- anything the owner has to do.

Enable auto-merge when the repo allows it. Otherwise the owner merges in the morning.

### Cloud limits to plan around

- Cloud sessions are Linux (Ubuntu 24.04, x86_64). Anything touching PDFKit, WebKit, QuickLook, ORT, SwiftUI or Xcode is verified only by the `macos` CI job.
- `git push` works only to the session's own branch. One session at a time, because `features.json` is shared state.
- Commands time out after 10 minutes. Run long jobs in the background and poll.

## Owner setup, before the first session

The owner does this; an agent cannot.

1. **Repo settings** (already in this commit): `.claude/settings.json` turns off commit and PR attribution for cloud sessions, and `.claude/hooks/cloud-setup.sh` installs dependencies at the start of each cloud session.
2. **GitHub:**
   - Install the Claude GitHub App on `doan-labs/keepanything`, which enables CI auto-fix.
   - Protect `main` and require the `linux` and `macos` checks.
   - Allow auto-merge.
   - The token must have the `workflow` scope, or pushes that touch `.github/workflows` fail. With `/web-setup`, run `gh auth refresh -s workflow` first.
3. **Cloud environment at claude.ai/code:**
   - Network: **Custom** with the default list included, plus these hosts:
     ```
     download.swift.org
     nodejs.org
     download.onnxruntime.ai
     huggingface.co
     *.huggingface.co
     *.hf.co
     *.actions.githubusercontent.com
     *.blob.core.windows.net
     ```
     The last two cover CI logs and artifacts. Check them with `curl -I` in the first session.
   - Setup script, pinned to the Swift version the `macos-26` runner reports:
     ```bash
     #!/bin/bash
     set -euo pipefail
     SWIFT=6.2   # match `swift --version` on the macos-26 runner
     if ! command -v swift >/dev/null; then
       apt-get update -qq
       apt-get install -y -qq binutils libcurl4-openssl-dev libxml2-dev libsqlite3-dev zlib1g-dev libstdc++-13-dev pkg-config
       curl -fsSL "https://download.swift.org/swift-$SWIFT-release/ubuntu2404/swift-$SWIFT-RELEASE/swift-$SWIFT-RELEASE-ubuntu24.04.tar.gz" | tar -xz -C /opt
       ln -sf /opt/swift-$SWIFT-RELEASE-ubuntu24.04/usr/bin/* /usr/local/bin/
     fi
     if ! node --version | grep -q '^v24'; then npm i -g n && n 24; fi
     ```
   - Environment variables: `ELECTRON_SKIP_BINARY_DOWNLOAD=1` and `BASH_MAX_TIMEOUT_MS=600000`. No API keys.
4. **Kick off:** `claude --cloud "Execute docs/swift_rewrite/PLAN.md. Follow its Agent protocol."` Start the next session in the morning, after merging.

## Risks

| Risk | Mitigation |
| --- | --- |
| Embeddings drift from the JS vectors | same q8 file on ORT; cosine ≥ 0.999 per chunk gate; fallback is re-embedding under a new model id |
| GRDB breaks on Linux | community support only; a Linux-only failure blocks that Linux gate with a note, and the macOS job stays the authority |
| PDFKit text differs from `unpdf` | PDFs stay out of cascading scenarios; token-overlap comparison in the PDF scenario only |
| Masonry performance at thousands of items | render visible rows only via `onScrollGeometryChange`; `NSCollectionView` fallback |
| Two apps writing one library | schema guard and `library.lock` land in Electron first (M0) |
| Squirrel.Mac refuses the Swift app | verified with a dummy app in M6 before the real cutover; fallback is a final Electron release that links to the download |
| An agent loops on one failure all night | three-strikes rule; one feature at a time; push after every commit |
| CI results unreadable from the cloud | CI log and artifact hosts on the allowlist; if still blocked, the `macos` job writes failing test names into `$GITHUB_STEP_SUMMARY`, read with `gh run view` |

## Open questions

- [ ] `Tokenizers` or a WordPiece port. Decided by `S-EMB-02`.
- [ ] Is re-entering the API key once acceptable, or must the Swift app read Electron's `safeStorage` value?
- [ ] Which Electron fixes during the freeze are worth regenerating fixtures for?
