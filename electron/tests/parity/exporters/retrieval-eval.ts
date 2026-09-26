import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { join, resolve } from 'node:path'
import {
  createEmbeddingProvider,
  createEmbeddingWorkerTasks,
  createHashEmbeddingProvider,
  modelFilesPresent
} from '../../../src/main/ai'
import { createManualClock } from '../../../src/main/lib/clock'
import { silentLogger } from '../../../src/main/lib/logger'
import type { EmbeddingProvider, WorkerClient } from '../../../src/main/ports'
import { createRetrieval } from '../../../src/main/retrieval'
import type { ItemSubtype, ItemType, Kind } from '../../../src/shared/types'
import { createHarness } from '../../unit/helpers/harness'
import { writeJson } from '../lib'

interface Fixture {
  id: string
  type: ItemType
  subtype?: ItemSubtype
  path?: string
  url?: string
  kind: Kind
  title: string
  topics: string[]
  entities: string[]
  captureOffsetDays: number
  children?: string[]
}

interface EvalQuery {
  id: string
  query: string
  style: string
  k?: number
  expected: string[]
}

interface Manifest {
  fixtures: Fixture[]
}
interface Queries {
  defaultK: number
  queries: EvalQuery[]
}

const FIXTURES = resolve(__dirname, '../../fixtures/corpus')
const MODELS_DIR = resolve(__dirname, '../../../build/models')
/** Fixed base for captureOffsetDays and every `clock.now()` the retrieval reads. */
const BASE = '2026-09-01T00:00:00.000Z'

function readText(path: string): string | null {
  const abs = join(FIXTURES, path)
  if (!existsSync(abs) || statSync(abs).isDirectory()) return null
  if (/\.(md|txt|csv|py|yaml|jsonl|json)$/i.test(path)) return readFileSync(abs, 'utf8').slice(0, 60_000)
  return null
}

/** Seed + rank, copied from tests/unit/retrieval-eval.test.ts with a fixed clock at BASE. */
async function rank(
  embeddings: EmbeddingProvider
): Promise<{ id: string; query: string; k: number; ranked: string[] }[]> {
  const manifest = JSON.parse(readFileSync(join(FIXTURES, 'manifest.json'), 'utf8')) as Manifest
  const queries = JSON.parse(readFileSync(join(FIXTURES, 'eval-queries.json'), 'utf8')) as Queries
  const h = createHarness()
  const clock = createManualClock(BASE)
  const retrieval = createRetrieval({ db: h.db, repos: h.repos, embeddings, logger: silentLogger, clock })
  await retrieval.warm()

  const now = clock.now().getTime()
  const idOf = new Map<string, string>()
  for (const f of manifest.fixtures) {
    const capturedAt = new Date(now - f.captureOffsetDays * 86_400_000).toISOString()
    const text = f.path ? readText(f.path) : null
    const domain = f.url ? new URL(f.url).hostname.replace(/^www\./, '') : null
    const hints = [...f.topics.map((t) => t.replace(/-/g, ' ')), ...f.entities]
    const item = h.item({
      type: f.type,
      subtype: f.subtype ?? null,
      kind: f.kind,
      title: f.title,
      url: f.url ?? null,
      domain,
      topics: f.topics.map((t) => t.replace(/-/g, ' ')),
      entities: f.entities,
      retrievalHints: hints,
      extractedText: text,
      excerpt: text ? text.replace(/\s+/g, ' ').slice(0, 280) : null,
      capturedAt,
      createdAt: capturedAt,
      processingStatus: 'READY',
      metadata: domain ? { siteName: domain } : {}
    })
    idOf.set(f.id, item.id)
    if (f.type === 'folder' && f.path) {
      const dir = join(FIXTURES, f.path)
      for (const name of existsSync(dir) ? readdirSync(dir) : []) {
        const child = h.item({
          type: /\.(md|txt)$/.test(name) ? (name.endsWith('.md') ? 'markdown' : 'text') : 'file',
          title: name,
          parentItemId: item.id,
          extractedText: readText(`${f.path}/${name}`),
          capturedAt,
          processingStatus: 'READY'
        })
        await retrieval.embedBody(child.id)
        await retrieval.indexItem(child.id)
      }
    }
    await retrieval.embedBody(item.id)
    await retrieval.indexItem(item.id)
  }
  const fixtureOf = new Map([...idOf].map(([fid, id]) => [id, fid]))

  const out: { id: string; query: string; k: number; ranked: string[] }[] = []
  for (const q of queries.queries) {
    const k = q.k ?? queries.defaultK
    const results = await retrieval.quickSearch(q.query, { limit: 10 })
    out.push({ id: q.id, query: q.query, k, ranked: results.map((r) => fixtureOf.get(r.id) ?? '?') })
  }
  h.close()
  return out
}

export async function exportRetrievalEval(): Promise<void> {
  writeJson('retrieval-eval.json', {
    model: 'local-hash',
    base: BASE,
    queries: await rank(createHashEmbeddingProvider())
  })

  // bge only when the model files exist locally, so machines without them produce the same tree.
  if (!modelFilesPresent(MODELS_DIR)) return
  const tasks = createEmbeddingWorkerTasks()
  const worker: WorkerClient = {
    call: async <T>(task: string, payload: unknown): Promise<T> => {
      const handler = tasks[task]
      if (!handler) throw new Error(`unknown worker task ${task}`)
      return (await handler(payload, new AbortController().signal)) as T
    },
    terminate: () => {}
  }
  const local = createEmbeddingProvider({ worker, modelsDir: MODELS_DIR, logger: silentLogger })
  await local.ready()
  if (local.backend() !== 'local') return
  writeJson('retrieval-eval-bge.json', { model: local.model, base: BASE, queries: await rank(local) })
}
