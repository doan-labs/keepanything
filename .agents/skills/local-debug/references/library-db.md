# Library Database Reference

All queries go through `.agents/skills/local-debug/scripts/ka.sh db [profile] "<sql>"` (read-only,
JSON out). Timestamps are ISO strings (`2026-09-10T16:44:36.200Z`), so they sort and compare as text.
JSON columns (`topics`, `steps`, `usage`, `result`, `before`, `after`) work with `json_extract` and
`json_each`. Full schema: `ka.sh db ".schema items"`.

## Tables

| Table | Holds |
| --- | --- |
| `items` | One row per kept thing. `processing_status`, `processing_error`, AI fields (`understanding`, `why_useful`, `topics`, `ai_confidence`), `deleted_at` (trash), `is_missing` (original gone) |
| `jobs` | Pipeline work per item: `stage`, `lane` (`io`/`embed`/`ai`), `status` (`queued`/`running`/`done`/`failed`/`cancelled`), `attempts`, `run_after` (parked until), `last_error` |
| `agent_runs` | Every agent task (`understand`, `organize`, `consolidate`, `command`): `status`, `model`, `steps` (JSON), `result`, `usage`, `error` |
| `audit_log` | Every agent/user mutation: `actor`, `action`, `entity`, `before`/`after`, `agent_run_id`, `undone_at` |
| `suppressions` | What the user removed, so the agent does not redo it (`kind`, `key`) |
| `relationships`, `collections`, `collection_items` | The graph and collections, each with `created_by`/`added_by` and `agent_run_id` |
| `embeddings` | Chunk vectors: `role` (`summary`/`body`), `model`, `dims` |
| `items_fts` | FTS5 index keyed by `item_id` (UNINDEXED) |

Status flow (`src/shared/status.ts`): `CAPTURED -> EXTRACTING -> EXTRACTED -> EMBEDDING -> UNDERSTANDING
-> RELATING -> READY`, with the outcomes `PARTIAL`, `EXTRACTION_FAILED`, `AI_FAILED`, and `WAITING_FOR_AI` for parked AI work.

## Items

```sql
-- Find an item
select id, type, kind, processing_status, substr(title,1,60) title, captured_at from items
where title like '%invoice%' and deleted_at is null order by captured_at desc limit 10;

-- Latest captures
select id, processing_status, substr(title,1,50) title, captured_at from items order by captured_at desc limit 10;

-- What the agent understood about one item
select understanding, why_useful, topics, ai_confidence, suggested_actions from items where id = '<id>';

-- Originals that moved or were deleted outside the app
select id, substr(title,1,50) title, original_path, missing_checked_at from items where is_missing = 1;
```

## Pipeline jobs

```sql
-- One item's pipeline, in order
select stage, lane, status, attempts, run_after, updated_at, substr(last_error,1,200) error
from jobs where item_id = '<id>' order by created_at;

-- Parked AI jobs (waiting for the provider)
select item_id, stage, attempts, run_after from jobs
where status = 'queued' and run_after > strftime('%Y-%m-%dT%H:%M:%fZ','now');

-- Running jobs, oldest first (a very old one is stuck)
select item_id, stage, lane, updated_at from jobs where status = 'running' order by updated_at;

-- Failure hot spots
select stage, count(*) n, max(updated_at) latest from jobs where status = 'failed' group by 1 order by n desc;
```

## Agent runs

```sql
-- Latest runs with cost
select id, task, status, model, started_at, completed_at,
       json_extract(usage,'$.promptTokens') prompt, json_extract(usage,'$.completionTokens') completion
from agent_runs order by started_at desc limit 10;

-- Steps of one run (what the agent looked at and did)
select s.key n, s.value ->> 'tool' tool, s.value ->> 'kind' kind, s.value ->> 'status' status, s.value ->> 'label' label
from agent_runs r, json_each(r.steps) s where r.id = '<runId>';

-- Runs for one item
select id, task, status, started_at, substr(error,1,160) error from agent_runs where item_id = '<id>' order by started_at desc;
```

## Audit, undo, suppressions

```sql
-- Latest changes by the agent, and whether they were undone
select id, action, entity, entity_id, agent_run_id, created_at, undone_at
from audit_log where actor = 'agent' order by created_at desc limit 20;

-- Everything one run changed
select id, action, entity, entity_id, undone_at from audit_log where agent_run_id = '<runId>';

-- What the user told the agent not to redo
select kind, key, created_at from suppressions order by created_at desc limit 20;
```

Undo goes through IPC, never SQL: `KA_WRITE=1 node .agents/skills/local-debug/scripts/cdp.mjs invoke
agent:undo '{"auditId":"<id>"}'` (or `agent:undoRun` with `runId`). Ask first.

## Graph and collections

```sql
-- Latest relationships, readable
select r.type, substr(a.title,1,40) source, substr(b.title,1,40) target, r.confidence, r.created_by
from relationships r join items a on a.id = r.source_item_id join items b on b.id = r.target_item_id
order by r.created_at desc limit 20;

-- Collections with sizes
select c.name, c.created_by, count(ci.item_id) items from collections c
left join collection_items ci on ci.collection_id = c.id group by c.id order by items desc;
```

## Search and embeddings

```sql
-- Which model wrote the vectors (anything but Xenova/bge-small-en-v1.5 is the hashed fallback)
select model, dims, role, count(*) n from embeddings group by 1,2,3;

-- Live items with no vectors at all
select id, processing_status, substr(title,1,50) title from items i
where deleted_at is null and not exists (select 1 from embeddings e where e.item_id = i.id);

-- Raw FTS hits (lexical half of search only)
select item_id, substr(title,1,50) title, bm25(items_fts) score from items_fts
where items_fts match 'invoice*' order by score limit 10;
```

The ranked result the user sees fuses FTS and vectors. Check it with
`node .agents/skills/local-debug/scripts/cdp.mjs invoke search:quick '{"query":"invoice"}'`.
