import type { FakeLog } from './fakes'

/**
 * Dump the whole library state for a scenario snapshot. Everything comes out of `db.raw` so the
 * file shows exactly what is stored. Lists are ordered; absolute paths are rewritten to
 * `{library}/…`, `{corpus}/…`, `{fixture}` markers by the caller's `relativize` pass, and
 * remaining UUID-shaped strings become `uuid-N` in first-seen order (agent task runs call
 * `uuid()` directly — agent_runs.id, audit_log.agent_run_id, collection_items.agent_run_id and
 * relationships.agent_run_id are the fields that need it).
 */
export interface SnapshotContext {
  raw: { prepare(sql: string): { all(...args: unknown[]): unknown[] } }
  fakes: FakeLog
  settings: unknown
}

interface TableSpec {
  /** Output key. */
  key: string
  sql: string
}

const TABLES: TableSpec[] = [
  { key: 'items', sql: 'SELECT * FROM items ORDER BY id' },
  { key: 'fts', sql: 'SELECT * FROM items_fts ORDER BY item_id' },
  { key: 'collections', sql: 'SELECT * FROM collections ORDER BY id' },
  { key: 'collectionItems', sql: 'SELECT * FROM collection_items ORDER BY collection_id, item_id' },
  { key: 'relationships', sql: 'SELECT * FROM relationships ORDER BY id' },
  { key: 'suppressions', sql: 'SELECT * FROM suppressions ORDER BY kind, key' },
  { key: 'audit', sql: 'SELECT * FROM audit_log ORDER BY id' },
  // Insertion order, not id: run ids are real UUIDs, so ordering by id scrambles every run.
  { key: 'agentRuns', sql: 'SELECT * FROM agent_runs ORDER BY rowid' },
  { key: 'jobs', sql: 'SELECT * FROM jobs ORDER BY id' }
]

export function takeSnapshot(ctx: SnapshotContext): Record<string, unknown> {
  const state: Record<string, unknown> = {}
  for (const { key, sql } of TABLES) {
    state[key] = ctx.raw.prepare(sql).all()
  }
  state.settings = ctx.settings
  state.thumbnailCalls = ctx.fakes.thumbnailCalls
  state.snapshotCalls = ctx.fakes.snapshotCalls
  state.fetchCalls = ctx.fakes.fetchCalls
  state.desktopCalls = ctx.fakes.desktopCalls
  state.pushes = ctx.fakes.pushes
  return state
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/**
 * Determinism pass over the whole expected document: absolute path prefixes become markers and
 * UUID-shaped strings become `uuid-N` (shared mapping, so the same run id stays consistent
 * across agent_runs / audit_log / collection_items).
 */
export function normalizeDocument(doc: unknown, prefixes: { find: string; marker: string }[]): unknown {
  const uuids = new Map<string, number>()
  const map = new Map(prefixes.map((p) => [p.find, p.marker]))

  const visit = (value: unknown): unknown => {
    if (typeof value === 'string') {
      if (UUID_RE.test(value)) {
        if (!uuids.has(value)) uuids.set(value, uuids.size + 1)
        return `uuid-${uuids.get(value)}`
      }
      let v = value
      // Longest prefix first so nested roots (userData inside tmpdir) win.
      for (const [find, marker] of [...map.entries()].sort((a, b) => b[0].length - a[0].length)) {
        if (v === find) v = marker
        else if (v.startsWith(`${find}/`)) v = `${marker}/${v.slice(find.length + 1)}`
        else if (v.includes(`${find}/`)) v = v.split(`${find}/`).join(`${marker}/`)
      }
      // mkdtemp suffixes are random per run; timings inside JSON columns are wall-clock.
      return v
        .replace(/ka-(scenario|keep)-[\w-]+/g, (m) => `${m.replace(/-[A-Za-z0-9]+$/, '')}-X`)
        .replace(/\\?"?(durationMs|latencyMs)\\?":\s*\d+/g, '"$1":0')
    }
    if (Array.isArray(value)) return value.map(visit)
    if (value !== null && typeof value === 'object') {
      const out: Record<string, unknown> = {}
      for (const [k, v] of Object.entries(value)) {
        // `pid` in lock-owner records is a real process id; timings are wall-clock.
        out[k] = (k === 'pid' || k === 'durationMs' || k === 'latencyMs') && typeof v === 'number' ? 0 : visit(v)
      }
      return out
    }
    return value
  }
  return visit(doc)
}
