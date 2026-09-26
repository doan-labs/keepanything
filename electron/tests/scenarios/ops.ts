import { cpSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { isKaError } from '../../src/main/core/errors'
import { describeIssues, schemaFor } from '../../src/main/ipc/schemas'
import { openDatabase, SchemaTooNewError } from '../../src/main/storage/db'
import { LOCK_FILE_NAME } from '../../src/main/storage/library-lock'
import { buildPaths, ensureLibraryDirs } from '../../src/main/storage/paths'
import type { IpcChannel } from '../../src/shared/ipc'
import { CORPUS_FILES } from './lib'
import type { Boot, RunnerOptions } from './runner'
import { boot, makeUserData, removeUserData } from './runner'
import { normalizeDocument, takeSnapshot } from './snapshot'

/** Envelope shape recorded under `steps[i].result` in the expected file. */
export type StepResult = { ok: true; data: unknown } | { ok: false; error: { code: string; message: string } } | null

export interface RunContext {
  current: Boot | null
  opts: RunnerOptions
  /** Absolute paths that get rewritten to markers in the expected file. */
  pathMarkers: { find: string; marker: string }[]
  results: Record<string, unknown>[]
  /** userData dirs created during the run (cleaned up by the caller). */
  ownedTempDirs: string[]
  /** The previous step's result, for `{prev}` placeholders. */
  lastResult?: StepResult
}

const SENDER = { senderId: 1 }

/** Same dispatch the router runs: zod validation -> handler -> envelope (minus the sender check). */
async function dispatch(ctx: RunContext, op: string, payload: unknown): Promise<StepResult> {
  const b = ctx.current
  if (!b) return { ok: false, error: { code: 'INTERNAL', message: 'No library open' } }
  const channel = op.replace('.', ':') as IpcChannel
  let schema: ReturnType<typeof schemaFor>
  try {
    schema = schemaFor(channel)
  } catch {
    return { ok: false, error: { code: 'VALIDATION', message: `Unknown channel "${channel}"` } }
  }
  // Empty payload: `empty` schemas want undefined, object schemas with all-optional fields want {}.
  const isEmpty = payload && typeof payload === 'object' && !Array.isArray(payload) && Object.keys(payload).length === 0
  let parsed = schema.safeParse(payload)
  if (isEmpty && !parsed.success) parsed = schema.safeParse(undefined)
  if (!parsed.success) return { ok: false, error: { code: 'VALIDATION', message: describeIssues(parsed.error) } }
  try {
    const handler = b.handlers[channel] as (p: unknown, c: { senderId: number }) => unknown
    const data = await handler(parsed.data, SENDER)
    return { ok: true, data }
  } catch (error) {
    if (isKaError(error)) return { ok: false, error: { code: error.code, message: error.message } }
    return { ok: false, error: { code: 'INTERNAL', message: error instanceof Error ? error.message : String(error) } }
  }
}

const flush = async (): Promise<void> => {
  await new Promise((r) => setImmediate(r))
  await new Promise((r) => setImmediate(r))
}

/** Number of jobs the scheduler could still claim (queued and due, or running). */
function pendingJobs(b: Boot): number {
  const now = b.clock.nowIso()
  const sql = b.scheduler.aiPaused()
    ? "SELECT count(*) AS n FROM jobs WHERE status = 'running' OR (status = 'queued' AND lane != 'ai' AND (run_after IS NULL OR run_after <= ?))"
    : "SELECT count(*) AS n FROM jobs WHERE status = 'running' OR (status = 'queued' AND (run_after IS NULL OR run_after <= ?))"
  const row = b.db.raw.prepare(sql).get(now) as { n: number }
  return row.n
}

/** Agent command runs in flight (they are not pipeline jobs). */
function runningAgentRuns(b: Boot): number {
  const row = b.db.raw.prepare("SELECT count(*) AS n FROM agent_runs WHERE status = 'running'").get() as {
    n: number
  }
  return row.n
}

/** Loop `scheduler.tick()` until the pipeline and the agent are idle (wall-clock bound). */
async function settle(ctx: RunContext): Promise<StepResult> {
  const b = ctx.current
  if (!b) return { ok: false, error: { code: 'INTERNAL', message: 'No library open' } }
  const deadline = Date.now() + 120_000
  while (Date.now() < deadline) {
    await b.scheduler.tick()
    await flush()
    if (b.scheduler.running() === 0 && pendingJobs(b) === 0 && runningAgentRuns(b) === 0) {
      return { ok: true, data: null }
    }
    // Give running async work real time: iterations are cheap, a first-time pdf.js import is not.
    await new Promise((r) => setTimeout(r, 10))
  }
  const stuck = b.db.raw
    .prepare(
      "SELECT id, item_id, stage, lane, status, attempts, run_after, last_error FROM jobs WHERE status IN ('queued','running') ORDER BY id"
    )
    .all()
  throw new Error(`settle did not reach idle in 120s; stuck jobs: ${JSON.stringify(stuck)}`)
}

function snapshot(ctx: RunContext): StepResult {
  const b = ctx.current
  if (!b) return { ok: false, error: { code: 'INTERNAL', message: 'No library open' } }
  const state = takeSnapshot({ raw: b.db.raw, fakes: b.fakes, settings: b.settings.get() })
  ctx.results.push(state)
  return { ok: true, data: null }
}

/**
 * Rebind payloads: `capture.files` paths are relative to `tests/fixtures/corpus/files/`,
 * `{fixture}` stands for `http://fixture` (rewritten to the server inside the runner so stored
 * URLs stay deterministic), and `bytesBase64` decodes to `bytes` for `capture.blob`.
 */
function rebind(ctx: RunContext, op: string, args: Record<string, unknown>): Record<string, unknown> {
  const out = { ...args }
  if (op === 'capture.files' && Array.isArray(out.paths)) {
    out.paths = out.paths.map((p) => join(CORPUS_FILES, String(p)))
  }
  const agentRun = (task: string | null): string | null => {
    const b = ctx.current
    if (!b) return null
    const row = (
      task
        ? b.db.raw
            .prepare('SELECT id FROM agent_runs WHERE task = ? ORDER BY started_at DESC, id DESC LIMIT 1')
            .get(task)
        : b.db.raw.prepare('SELECT id FROM agent_runs ORDER BY started_at DESC, id DESC LIMIT 1').get()
    ) as { id: string } | undefined
    return row?.id ?? null
  }
  for (const key of Object.keys(out)) {
    const v = out[key]
    if (typeof v !== 'string') continue
    if (v === '{prev}') {
      const data = ctx.lastResult?.ok === true ? (ctx.lastResult.data as { path?: string }) : null
      out[key] = data?.path ?? v
      continue
    }
    const runMatch = /^\{agentRun(?::(\w+))?\}$/.exec(v)
    if (runMatch) {
      out[key] = agentRun(runMatch[1] ?? null) ?? v
      continue
    }
    if (v.startsWith('{fixture}')) out[key] = `http://fixture${v.slice('{fixture}'.length)}`
  }
  if (op === 'capture.blob' && typeof out.bytesBase64 === 'string') {
    out.bytes = Uint8Array.from(Buffer.from(out.bytesBase64, 'base64'))
    delete out.bytesBase64
  }
  return out
}

const RUNNER_OPS = new Set(['settle', 'snapshot', 'advance', 'open-library', 'bump-schema', 'hold-lock', 'keep'])

export function isRunnerOp(op: string): boolean {
  return RUNNER_OPS.has(op)
}

async function openLibrary(ctx: RunContext, dir: string): Promise<StepResult> {
  if (ctx.current) await ctx.current.close()
  ctx.current = null
  try {
    const b = boot(dir, ctx.opts)
    ctx.current = b
    ctx.pathMarkers.push({ find: dir, marker: '{library}' })
    return { ok: true, data: { readOnly: b.readOnly, owner: b.lock.owner } }
  } catch (error) {
    if (error instanceof SchemaTooNewError) {
      return { ok: false, error: { code: 'SCHEMA_TOO_NEW', message: error.message } }
    }
    if (isKaError(error)) return { ok: false, error: { code: error.code, message: error.message } }
    return { ok: false, error: { code: 'INTERNAL', message: error instanceof Error ? error.message : String(error) } }
  }
}

/** Create a fully migrated, empty library at `dir` (fresh dir must not exist inside a boot). */
function createFreshLibrary(dir: string): void {
  const paths = buildPaths(dir)
  ensureLibraryDirs(paths)
  const db = openDatabase(paths.dbFile)
  db.migrate()
  db.close()
}

/** One step. Returns the recorded result; never throws for IPC errors. */
export async function runOp(ctx: RunContext, step: Record<string, unknown>): Promise<StepResult> {
  const op = String(step.op)
  const args = { ...step }
  delete args.op
  const bound = rebind(ctx, op, args)

  switch (op) {
    case 'settle':
      return settle(ctx)
    case 'snapshot':
      return snapshot(ctx)
    case 'advance':
      ctx.current?.clock.advance(Number(args.ms ?? 0))
      return { ok: true, data: null }
    case 'open-library': {
      const dir = String(bound.path ?? '')
      if (!dir.startsWith('/'))
        return { ok: false, error: { code: 'VALIDATION', message: 'open-library needs an absolute path' } }
      return openLibrary(ctx, dir)
    }
    case 'keep': {
      // Copy the finished library so `open-library`/library-compat can re-open it.
      const b = ctx.current
      if (!b) return { ok: false, error: { code: 'INTERNAL', message: 'No library open' } }
      const dest = String(bound.path)
      cpSync(b.paths.userData, dest, { recursive: true })
      return { ok: true, data: { path: dest } }
    }
    case 'bump-schema': {
      // Fresh library, migrated, then marked with a schema version this build does not know.
      const dir = makeUserData('schema-guard')
      ctx.ownedTempDirs.push(dir)
      createFreshLibrary(dir)
      const db = openDatabase(buildPaths(dir).dbFile)
      const latest = (db.raw.prepare('SELECT max(version) AS v FROM schema_migrations').get() as { v: number }).v
      db.raw
        .prepare('INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)')
        .run(latest + 1, '2026-09-01T00:00:00.000Z')
      db.close()
      return { ok: true, data: { path: dir } }
    }
    case 'hold-lock': {
      // Another live process (this one) holds the lock: writes a live-pid lock file.
      const dir = makeUserData('hold-lock')
      ctx.ownedTempDirs.push(dir)
      createFreshLibrary(dir)
      writeFileSync(
        join(dir, LOCK_FILE_NAME),
        `${JSON.stringify({ pid: process.pid, app: 'other', version: '9.9.9', since: '2026-09-01T00:00:00.000Z' })}\n`
      )
      return { ok: true, data: { path: dir } }
    }
    default:
      return dispatch(ctx, op, bound)
  }
}

/** Drop temp dirs the run created (never the scenario's own library when keeping). */
export function cleanupTemps(ctx: RunContext): void {
  for (const dir of ctx.ownedTempDirs) removeUserData(dir)
}

export { normalizeDocument }
