---
name: local-debug
description: >-
  Local debugging, troubleshooting and verification for the KeepAnything Electron app. Use this
  skill whenever you need to check what is running, inspect the library database (items, pipeline
  jobs, agent runs, audit log, embeddings), read the app log, find out why an item is stuck or
  failed, or verify a change in the live app window (screenshot, accessibility tree, console, IPC
  calls). Trigger on: "debug", "verify", "check if it works", "test locally", "why is this broken",
  "stuck", "failed", "what's running", "check the db", "check the logs", "screenshot the app",
  "is the pipeline done", post-change verification, or any troubleshooting task. Use it even when
  the user does not say "debug".
allowed-tools:
  - Bash(.agents/skills/local-debug/scripts/*)
  - Bash(node .agents/skills/local-debug/scripts/cdp.mjs:*)
  - Bash(jq:*)
---

# Local Debug & Verification

KeepAnything is one Electron process that opens one of three isolated profiles. Each profile
directory holds `library.db` (SQLite, WAL), `logs/keepanything.log` (JSON lines, already
redacted), `objects/ thumbs/ snapshots/ content/` and `config.json`.

| Profile | Directory | Started by |
| --- | --- | --- |
| `dev` (default) | `~/Library/Application Support/KeepAnything/dev` | `cd electron && pnpm run dev` |
| `e2e` | `$TMPDIR/keepanything-e2e` | `cd electron && pnpm run screenshot`, `seed:library`, `test:e2e` (`KEEPANYTHING_E2E=1`, mock AI) |
| `prod` | `~/Library/Application Support/KeepAnything` | the installed app: the user's real library |

## Rules

- Never read `.env` or `config.json`: they hold provider keys and the encrypted secrets store.
  Provider health is visible in the log (`ai.chat` lines: provider, model, finishReason, latency).
- Never write `library.db`. Only the scheduler writes `items.processing_status`, and agent changes need audit
  rows and suppressions, so state changes go through IPC (`cdp.mjs invoke`), never SQL.
- `prod` is the user's personal library. Ask before reading it (`KA_PROD=1`), and quote as little
  item content as the answer needs.
- `KA_WRITE=1` (mutating IPC channels, `eval`): ask first, and only on `dev` or `e2e`.

## Scripts

```bash
.agents/skills/local-debug/scripts/ka.sh ps                      # always first: instances, profile each has open, CDP port
.agents/skills/local-debug/scripts/ka.sh health [profile]        # status counts, open jobs, failed jobs / items / agent runs
.agents/skills/local-debug/scripts/ka.sh log [profile] [n] [lvl] # last n lines at or above lvl (default 50, warn)
.agents/skills/local-debug/scripts/ka.sh db [profile] "<sql>"    # read-only, JSON; extra args may be dot-commands (".mode box")
.agents/skills/local-debug/scripts/ka.sh path [profile]          # profile directory, for ls on objects/ thumbs/ ...
node .agents/skills/local-debug/scripts/cdp.mjs shot|snap|console|invoke|eval   # the live window, see references/ui.md
```

`ka.sh` reads while the app runs, and also when it is closed (it opens the DB `immutable` then).

## Core Workflow

1. **Detect**: `ka.sh ps`. If the task needs the live UI and no instance shows `listening=9222`,
   ask the user to (re)start dev with `cd electron && pnpm run dev --remoteDebuggingPort 9222`. Do not start a
   second dev instance yourself: the single-instance lock makes it quit while one holds `dev`.
2. **Health**: `ka.sh health`, then `ka.sh log`.
3. **Investigate**: `ka.sh db` with the queries in [references/library-db.md](references/library-db.md).
   Follow one item: `items` -> `jobs` -> `agent_runs` -> `audit_log`, then
   `ka.sh log dev 500 info | grep <itemId>`.
4. **Verify**: DB state first, then the window ([references/ui.md](references/ui.md)). Under
   `cd electron && pnpm run dev`, renderer edits hot-reload and main/preload edits restart the app (same CDP port).
   Finish with `cd electron && pnpm run typecheck && pnpm run test`.

| Investigating... | Read |
| --- | --- |
| Items, pipeline jobs, agent runs, undo, suppressions, search and embeddings | [references/library-db.md](references/library-db.md) |
| The window: screenshots, accessibility tree, console, IPC, built-app captures | [references/ui.md](references/ui.md) |

## Troubleshooting Quick Reference

**More log detail:** `cd electron && KEEPANYTHING_DEBUG=1 pnpm run dev` logs at `debug` level; read it with
`ka.sh log dev 200 debug`. Main-process breakpoints: `cd electron && pnpm run dev --inspect 5858`, then attach
from `chrome://inspect`.

**App will not start, or a new instance quits at once:** another instance holds that profile.
`ka.sh ps`, then `kill <pid>` for an orphan left by a killed dev run.

**Item stuck in `WAITING_FOR_AI`:** the scheduler parked its AI job. `ka.sh log dev 200 info | grep
parking` gives the error `code`; parked jobs retry every 5 minutes. `cdp.mjs invoke settings:get`
shows `aiMode`, `cdp.mjs invoke system:stats` shows `aiStatus`.

**`EXTRACTION_FAILED` / `AI_FAILED` / `PARTIAL`:** `ka.sh health` lists `jobs.last_error` and
`items.processing_error`; then read the log around that `updated_at`. `finishReason: "length"` in
an `ai.chat` line is never parsed: structured calls retry once with double `max_tokens`.

**Weak search results:** check which embedding model wrote the rows (library-db.md). Any `model`
other than `Xenova/bge-small-en-v1.5` is the hashed TF-IDF fallback; `cd electron && pnpm run models:fetch`
restores the real model and the next run re-embeds.

**`embeddings.retry` warning:** the embedding worker restarted and lost its model; the batch is
re-initialised and retried once. Only a following error means embeddings failed.

**No thumbnail:** `qlmanage -t` rejects unsupported types and the stage falls back to `nativeImage`
or none. Check the item's `thumbnail` job and `items.thumbnail_path`.
