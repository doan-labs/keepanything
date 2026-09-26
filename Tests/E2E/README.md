# E2E scenarios

Hand-written scenarios in `scenarios/<name>.json`, expected output in `expected/<name>.json`
written by `cd electron && pnpm run scenarios:export` and never edited by hand. `compare.json`
lists the only allowed differences between the Electron and Swift runners (`ignore`,
`float:1e-4`, `tokens:0.95`). A rule with a `scenarios` list applies only to those scenarios;
`tokens:0.95` is limited to the scenarios whose text comes from a different extractor (PDF, live pages).

## Ops

Every Electron IPC channel is an op: `{ "op": "capture.files", ... }` calls channel
`capture:files` with the rest of the object as the payload. Runner ops:

- `settle` — loop until the pipeline and the agent are idle.
- `snapshot` — append a full library dump to `results`.
- `advance` `{ "ms": N }` — move the manual clock (it also advances 1 s before every step).
- `open-library` `{ "path": … }` — close and reopen on an existing library dir. `{kept}` means
  the library produced by the scenario named in `library` (rebuilt internally before the run);
  `{prev}` means the previous step's `result.data.path`.
- `bump-schema` / `hold-lock` — set up a too-new schema and a live foreign lock for
  `schema-guard` (each returns `{ "path": <fresh lib dir> }`).
- `keep` `{ "path" }` — copy the current library dir (used internally; `scenarios:keep` keeps
  every scenario's finished library in `Tests/E2E/library/<name>/`, gitignored).

## Placeholders

- `capture.files.paths` entries are relative to `electron/tests/fixtures/corpus/files/`.
- `{fixture}` → `http://fixture` (the runner's local fixture server serves
  `electron/tests/fixtures/html/`; any other host fails deterministically).
- `bytesBase64` on `capture.blob` decodes to `bytes`.
- `{agentRun}` / `{agentRun:<task>}` → the newest `agent_runs` id (organize/consolidate runs use
  real UUIDs, not sequential ids).

## Ids

One `item` counter is shared by intake and the item service, so batch ids and item ids come
from the same sequence in creation order: each `capture.*` call consumes one id for the batch
first, then one per created item — the first `capture.text` produces batch `item-1` and item
`item-2`. Other prefixes: `collection-N`, `rel-N`, `audit-N`, `job-N`, `run-N` (agent command
runs). Organize/consolidate task run ids are real UUIDs and are normalized to `uuid-N` in the
expected files.

## Runs

- `KEEPANYTHING_SCENARIOS=1 vitest run tests/scenarios/run.test.ts` (== `pnpm run scenarios:export`)
- `KA_SCENARIO=<name>` runs one scenario.
- `pnpm run scenarios:keep` additionally writes `Tests/E2E/library/<name>/` for the Swift side.
- `embeddings: "bge"` scenarios are skipped when `build/models/` has no model files.
