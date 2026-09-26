# KeepAnything Swift Rewrite Plan (macOS)

Status: proposed, 2026-09-26.

## Summary

KeepAnything is rewritten as a native macOS app in Swift, desktop only. The Electron app is frozen to fixes and deleted at cutover.

**Why:** capture has to be a reflex. Native gives instant launch, a menubar and shelf that stay resident at little cost, a real share extension, and Quick Look.

**What does not change:** the agent behavior, schema, prompts, retrieval weights and library format. The Electron app is the spec; the rewrite ports it and does not redesign it.

**Done means:**

- Feature parity: capture (drag, shelf, menubar, paste, share extension), extraction, understanding, relationships, collections, Ask, multi-item commands, trash, settings, undo.
- An existing Electron library opens in the Swift app with no migration step.
- Retrieval eval parity on `eval-queries.json`, and the unit suite ported for every core module.
- The last Electron update installs the Swift app, and `electron/` is removed from the repo.

## Decisions

These are settled; everything below assumes them.

| Decision | Choice | Why |
| --- | --- | --- |
| Platform | macOS desktop only | Mac is the focus; no iOS, no Windows |
| Minimum OS | macOS 15 | `onScrollGeometryChange` for the virtualized masonry, current SwiftUI APIs |
| Language | Swift 6, strict concurrency on from day one | turning it on later means redoing every module |
| UI | SwiftUI, with AppKit for panels, the status item and drag-watch | native feel; AppKit where SwiftUI has gaps |
| Distribution | Developer ID, not sandboxed, notarized, Sparkle 2 | opens existing libraries in place; no Mac App Store |
| Bundle ID | `com.doanlabs.keepanything` (same as Electron) | lets the last Electron update install the Swift app |
| Library location | `~/Library/Application Support/KeepAnything` (dev: `.../dev`) | same folder Electron uses today |
| Repo shape | Swift package at the root, Xcode project in `App/`, Electron moved to `electron/` | standard SwiftPM layout; removing Electron later is one `git rm` |

**Dependencies (four):**

- [GRDB](https://github.com/groue/GRDB.swift): SQLite access, WAL, observation.
- onnxruntime (SwiftPM package): runs the same bge-small q8 model file as today.
- swift-transformers `Tokenizers`: reads the model's `tokenizer.json`.
- [Sparkle 2](https://sparkle-project.org): updates, app target only.

Everything else is an Apple framework.

## Repo layout

The Swift package is the repo root, following SwiftPM's fixed `Sources/` + `Tests/` layout. The Xcode project in `App/` stays thin and references the root package as a local package, the same shape as Point-Free's isowords.

```
keepanything/
  Package.swift                KeepAnythingKit, every module
  Sources/
    KAModel/ KAStorage/ KACore/ KACapture/ KAExtraction/ KAPreviews/
    KAEmbeddings/ KAAI/ KARetrieval/ KAAgent/ KAPipeline/ KALibrary/ KAUI/
  Tests/
    KAModelTests/ ... KALibraryTests/
    Fixtures/parity/           written by electron/scripts/export-parity.ts
  App/
    KeepAnything.xcodeproj     thin targets, Xcode 16 folder-synced groups
    Mac/                       app target: windows, menubar, shelf, drag-watch, Sparkle
    MacShare/                  share extension target
    MacUITests/                XCUITest smoke test
    Resources/                 assets, Instrument Serif, JS bundles (Readability, Turndown)
    Config/                    xcconfigs, entitlements, Info.plists
  electron/                    entire Electron project, frozen
    package.json pnpm-lock.yaml src/ tests/ scripts/ native/ assets/ build/
    electron.vite.config.ts electron-builder.yml AGENTS.md (current rules)
  web/  video/  docs/          unchanged
  AGENTS.md                    rewritten for the Swift codebase
```

**The move to `electron/` is one mechanical commit.** It fixes these in the same commit:

1. `web/src/styles/tokens.stylex.ts` and `shared.ts` are symlinks into `src/renderer/src/styles/`. Make them real files, since Electron is deleted at cutover.
2. CI, release scripts and `.claude/skills/local-debug` point at root paths; repoint them.
3. The pre-commit hook (simple-git-hooks + lint-staged) moves with `electron/package.json`, or gets reinstalled at the root.
4. AGENTS.md and README commands become `cd electron && pnpm ...`.

Gate: `cd electron && pnpm run typecheck && pnpm run test && pnpm run build` pass, and `pnpm run package:mac` still produces a DMG.

## Package modules

Each module ports exactly one folder under `electron/src/main/`. A port task reads: port folder X into module KAX until its parity fixtures pass.

| Module | Ports from | Depends on | Apple frameworks |
| --- | --- | --- | --- |
| `KAModel` | `src/shared/` (types, kinds, status, constants, text, media) | none | Foundation |
| `KAStorage` | `storage/` (db, migrations, repositories, object-store, paths, reset-data) | Model, GRDB | none |
| `KACore` | `core/` (item, collection, relationship services; audit; events; ids) | Model, Storage | none |
| `KACapture` | `capture/` (intake, classify, folder, url) | Model, Storage, Core | UniformTypeIdentifiers |
| `KAExtraction` | `extraction/` + `url/` adapters (pdf, text, image, archive, spreadsheet, folder, content) | Model | PDFKit, WebKit, Compression, ImageIO |
| `KAPreviews` | `previews/` (thumbnails, snapshot, color) | Model | QuickLookThumbnailing, WebKit |
| `KAEmbeddings` | `ai/embeddings/` (model, hash fallback) | Model, onnxruntime, Tokenizers | Accelerate |
| `KAAI` | `ai/` (client, messages, structured, prompts, schemas, mock and scripted providers) | Model | none (URLSession) |
| `KARetrieval` | `retrieval/` (fts, vectors, hybrid, query, context) | Model, Storage, Embeddings | Accelerate |
| `KAAgent` | `agent/` (orchestrator, tasks, tools) | all above | none |
| `KAPipeline` | `pipeline/` (graph, queue, scheduler, state, stages) | all above | none |
| `KALibrary` | `ports.ts` + `ipc/handlers` | all above | none |
| `KAUI` | shared views from `src/renderer/` | Library | SwiftUI |

**Import rules:**

1. Only `KAUI` and the app targets import SwiftUI; only the app targets import AppKit. A CI grep over `Sources/` enforces it.
2. No module reads the environment, `UserDefaults` or the Keychain. The app target passes those values in, as `ports.ts` does today.
3. `KALibrary` is the only module the app imports. It replaces the IPC router, the envelope and the preload bridge.

## Targets

Two shipping targets and two test targets. The app is the only process that writes to the database.

| Target | Links | Job |
| --- | --- | --- |
| `KeepAnything` (Mac app) | KALibrary, KAUI, Sparkle | library window, shelf, menubar, palette, settings, drag-watch, inbox watcher |
| `KeepAnythingShare` (appex) | KAModel | serializes the share payload to `<AppGroup>/inbox/<uuid>.json` plus copied files, then exits |
| `KeepAnythingKitTests` | all modules | unit, parity and eval tests (`swift test`) |
| `MacUITests` | the app | XCUITest smoke test over a throwaway library |

**Share extension flow:**

1. The extension is sandboxed, so it can only write to the App Group container.
2. It never opens the database; it writes one JSON envelope and any files to `inbox/`.
3. The app watches `inbox/` and feeds each envelope to the normal capture intake, then deletes it.

## Technical mapping

Every Node or Electron dependency maps to an Apple framework or one of the four packages. Nothing needs a subprocess or a worker.

### Storage

- `node:sqlite` → GRDB `DatabasePool` in WAL mode.
- Migration `.sql` files run verbatim from bundle resources, recorded in the same `schema_migrations` table.
- System SQLite includes FTS5, JSON1 and the `porter unicode61 remove_diacritics 2` tokenizer, so no custom SQLite build.
- `transaction()` + `afterCommit` → GRDB `write {}` with post-commit callbacks.
- Object store keeps the `objects/`, `thumbs/`, `snapshots/`, `content/` layout.

### AI

- `openai-compatible.ts` → URLSession with `bytes(for:)` for SSE. Task cancellation replaces `AbortSignal`.
- zod schemas → `Codable` structs plus a `validate() -> [String]` per schema.
- `structured.ts` ports as control flow: last fenced block, balanced-object fallback, decode, validate, one retry carrying the errors.
- Strip `<think>` blocks, never persist `reasoning_content`, reject `finish_reason: length`.
- Mock and scripted providers port too; the tests and deterministic AI modes depend on them.

### Embeddings

- onnxruntime runs the same `bge-small-en-v1.5` q8 `.onnx` file; `Tokenizers` reads its `tokenizer.json`.
- Vectors stay little-endian Float32 blobs, L2-normalized, with `model = 'Xenova/bge-small-en-v1.5'`.
- Hash fallback ports as-is: FNV-1a over lowercase, then NFKD, then `[^a-z0-9]+` tokens.
- An `Embedder` actor owns the session and loads it lazily, so an idle app does not hold the model.

### Extraction

- `unpdf` → PDFKit for text and page count.
- Readability + Turndown: bundle both JS files and run them in an offscreen WKWebView. This also replaces `linkedom`.
- `archive.ts` and `spreadsheet.ts` read ZIP central directories with the Compression framework (raw deflate).
- `mime` → `UTType`; image dimensions → ImageIO.

### Previews

- `qlmanage` → `QLThumbnailGenerator`.
- Offscreen BrowserWindow snapshots → WKWebView `takeSnapshot`.
- WebKit work runs on a `@MainActor` `WebRenderer` that reuses one or two web views.

### Pipeline

- Lanes (io, embed, ai) → `TaskGroup`s with per-lane concurrency limits inside a `Scheduler` actor.
- Stages return a `StagePatch`; only the scheduler writes status; transitions come from `status.next()`.
- Stage bodies stay idempotent, so a crash mid-stage reruns safely.

### Security and settings

- The `ka-media:` scheme → file URLs, checked with `LibraryPaths.contains(url)` before any view loads them.
- `safeStorage` secrets → Keychain. The API key is re-entered once; Electron's encrypted value is not read.
- `settings.json` (non-secret) is read as-is.
- `KEEPANYTHING_*` flags → Xcode scheme environment, read only in the app target.
- The logger keeps redacting key-like values; `os.Logger` plus the existing file log in `logs/`.

## UI mapping

The renderer's behavior and proportions carry over; its implementation is rebuilt in SwiftUI, with AppKit where SwiftUI falls short.

| Electron | Swift |
| --- | --- |
| zustand stores (`state/*.ts`) | `@Observable` models fed by GRDB `ValueObservation` |
| `lib/masonry.ts` | position math ported verbatim; only rows in view render, via `onScrollGeometryChange`. Fallback: `NSCollectionView` |
| per-type cards (`library/item-card/`) | one SwiftUI view per item type in `KAUI` |
| cmdk palette | `NSPanel` + SwiftUI `TextField` and list; Ask streams through an `AsyncStream` |
| shelf window | non-activating `NSPanel` hosting SwiftUI |
| tray + `positioning.ts` | `NSStatusItem`; positioning from the click event's bounds |
| `native/drag-watch` sidecar | in-process global event monitor plus the drag pasteboard |
| item preview | Quick Look through `QLPreviewPanel` |
| StyleX tokens | a `Theme` struct with the values from `tokens.stylex.ts`; Instrument Serif bundled |
| `@scritto/react` | `.contentTransition(.numericText())` |
| Lucide icons | SF Symbols |
| `motion` | SwiftUI animations, gated on `accessibilityReduceMotion` |
| `confirm()` | one `ConfirmModel` driving `.confirmationDialog` |
| toasts, activity, settings, trash, collections | SwiftUI views over `KALibrary` |
| electron-updater | Sparkle 2, appcast on GitHub Releases |

**Rules that carry over:** anything that interrupts work in progress asks through `ConfirmModel`; motion respects reduced motion; colors, radii and durations come only from `Theme`; no emoji, no gradients.

## Contract with Electron

TS stays the source of truth until cutover. Swift proves parity against fixtures that TS generates; nothing is hand-copied.

### Parity fixtures

`electron/scripts/export-parity.ts` writes into `Tests/Fixtures/parity/`:

1. Migration SQL (copied), vocab, limits and the status table as JSON.
2. Rendered prompts: every `build*Messages` function over fixture inputs.
3. Structured-output cases (raw model text to parsed result or errors), URL canonicalization, cue parsing, capture classification.
4. Hash vectors, and bge vectors for the eval corpus.
5. The retrieval eval: `eval-queries.json` to expected rankings.

CI re-runs the export and fails on any diff. Swift tests assert equality against the files.

### Coexistence

Both apps can find the same library, so these land in Electron before any Swift code touches a real one:

- `migrate()` in `storage/db.ts` refuses a schema newer than it knows. Today it silently opens it.
- `library.lock` in the library folder, honored by both apps. The second app to start opens read-only.
- Schema changes land in Electron's migrations folder first; the export copies them; both apps run the same SQL.
- Electron is frozen to fixes. A fix that changes behavior also regenerates the fixtures.

## Testing

A module counts as ported when its parity fixtures and its mirrored unit tests pass.

| Layer | Tool | Pass bar |
| --- | --- | --- |
| Unit | Swift Testing, one test target per module, mirroring `tests/unit` (e.g. `services.test.ts` → `KACoreTests`) | all ported cases green |
| Parity | fixture tests per module | byte-equal output (prompts, vocab, canonical URLs, cues, hash vectors) |
| Embeddings | fixture test on the eval corpus | cosine ≥ 0.999 per chunk against the JS vectors |
| Retrieval eval | port of `retrieval-eval.test.ts` | identical rankings on `eval-queries.json` |
| Live AI | opt-in test against GMI, like `ai-gmi-live.test.ts` | runs only with a key set |
| UI smoke | XCUITest over a throwaway library | launch, capture a file, search, open detail |

**Before finishing any change:** `swift test` for the package and the XCUITest smoke test when touching UI. Electron keeps its own `pnpm run typecheck && pnpm run test`.

## Phases

Ten phases in dependency order; each ends runnable and has a gate. Phases 3 and 4 run in parallel once 2 is done. Retrieval (5) comes before the agent (6) because the agent's tools call retrieval.

| # | Work | Done when |
| --- | --- | --- |
| 0 | Move Electron to `electron/`; schema guard; `library.lock`; `export-parity.ts` | Electron gate passes from `electron/`; Electron refuses a v4 database; fixtures committed |
| 1 | Spikes: ORT embeddings; MiniMax tool calling over SSE; Readability in WKWebView | all three pass on real data (cosine ≥ 0.999; a streamed tool call; clean markdown from saved HTML) |
| 2 | Xcode project, package skeleton, `KAModel`, `KAStorage`, CI | a copy of your real library opens read-only; repository tests pass |
| 3 | UI track: read-only library window, masonry, per-type cards, detail | you can browse your real library in the Swift app |
| 4 | `KACore`, `KACapture`, `KAExtraction`, `KAPreviews` | drag-in and paste capture work end to end; extraction fixtures pass |
| 5 | `KAEmbeddings`, `KARetrieval` | search works in the app; retrieval eval passes |
| 6 | `KAAI`, `KAAgent`, `KAPipeline` | understanding, relationships, collections, undo and suppressions match the fixtures |
| 7 | Palette, Ask streaming, multi-item commands, collections, trash, activity, settings | parity checklist complete |
| 8 | Shelf, menubar, drag-watch, share extension, inbox | every capture surface works |
| 9 | Signing, notarization, Sparkle, cutover | an Electron user updates straight into the Swift app; `electron/` removed |

### Cutover

1. Squirrel.Mac (behind electron-updater) replaces the whole `.app` when the signature and bundle ID match. The Swift app matches both.
2. The last Electron release points its feed at a zip of the Swift app. Users update once and land in the Swift app with their library intact.
3. Verify this in phase 1 with a dummy Swift app signed with the same identity, so cutover is not a surprise.
4. From then on Sparkle handles updates from the same GitHub Releases.

## Deleted, not ported

These exist only because of Electron and have no Swift counterpart.

- `worker/` and `lib/worker-client.ts`: replaced by actors.
- `ipc/` (router, envelope, schemas), `preload/`, and the renderer's `ipc-client.ts` and `mock-bridge.ts`: replaced by `KALibrary`. SwiftUI previews use in-memory mock data.
- `desktop/media-protocol.ts`, `dom-fallback.ts` and `security.ts` (CSP): no web content left to police.
- `native/drag-watch`: moves in-process.
- electron-builder, electron-vite and StyleX build config: removed at cutover with the rest of `electron/`.

## Conventions

The root `AGENTS.md` is rewritten around these rules; `electron/AGENTS.md` keeps today's rules for fixes.

1. The Electron behavior is the spec. Port it, do not improve it; product changes come after parity.
2. One TS folder maps to one module; a port is done when its fixtures and mirrored tests pass.
3. Only `KAUI` and the app targets import SwiftUI; only the app targets import AppKit.
4. Schema and prompt changes land in TS first, then get exported. Never hand-edit fixtures.
5. Agent writes go through audited services, stay undoable, and user removals write suppressions.
6. Secrets live in the Keychain, never in logs, fixtures, prompts or the repo.
7. Kebab-case stays for the Electron side; Swift files use UpperCamelCase, one primary type per file.
8. Comments follow today's rule: only what the signature cannot say (units, invariants, external quirks).

## Risks and open questions

The biggest risk is the freeze: no new features ship until the Swift app reaches parity.

| Risk | Mitigation |
| --- | --- |
| Embedding output drifts from the JS vectors | same q8 file on ORT; cosine ≥ 0.999 gate in phase 1; re-embed under a new model id if it fails |
| Masonry performance with thousands of items | render only visible rows; `NSCollectionView` fallback |
| Two apps writing one library | schema guard and `library.lock` land in phase 0 |
| Squirrel.Mac refuses to install the Swift app | verified in phase 1 with a dummy app; fallback is a final Electron release that links to the new download |
| Readability output differs in WKWebView | fixture comparison on saved HTML in the phase 1 spike |

**Open questions:**

- [ ] Tokenizer: swift-transformers `Tokenizers`, or a small WordPiece port if the package is too heavy? Decide in the phase 1 spike.
- [ ] Does the Swift app need to read Electron's `safeStorage` key, or is re-entering the API key once acceptable?
- [ ] Which Electron fixes during the freeze are worth regenerating fixtures for?
- [ ] Mac App Store: this plan assumes never, since sandboxing breaks opening existing libraries in place.
