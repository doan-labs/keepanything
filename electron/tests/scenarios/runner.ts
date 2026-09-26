import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createAgentService } from '../../src/main/agent'
import {
  createEmbeddingProvider,
  createHashEmbeddingProvider,
  createMockProvider,
  createOffProvider,
  createScriptedProvider,
  jsonResponse,
  textResponse,
  toolCallResponse
} from '../../src/main/ai'
import { modelFilesPresent } from '../../src/main/ai/embeddings/model-files'
import { EMBEDDING_WORKER_TASKS } from '../../src/main/ai/embeddings/worker-tasks'
import type { ScriptedReply } from '../../src/main/ai/scripted-provider'
import { createIntake } from '../../src/main/capture/intake'
import { createAuditService } from '../../src/main/core/audit'
import { createCollectionService } from '../../src/main/core/collection-service'
import { KaError } from '../../src/main/core/errors'
import { createEventBus } from '../../src/main/core/events'
import { sequentialIds } from '../../src/main/core/ids'
import { createItemService } from '../../src/main/core/item-service'
import { createRelationshipService } from '../../src/main/core/relationship-service'
import { EXTRACTION_WORKER_TASKS } from '../../src/main/extraction/worker-tasks'
import { createIpcPush } from '../../src/main/ipc/events'
import { createHandlers } from '../../src/main/ipc/handlers'
import type { HandlerMap } from '../../src/main/ipc/router'
import { createManualClock, type ManualClock } from '../../src/main/lib/clock'
import { silentLogger } from '../../src/main/lib/logger'
import {
  createMemorySecretStore,
  createSettingsStore,
  openConfigDocument,
  type SettingsStore
} from '../../src/main/lib/settings'
import { createQueue, type Queue } from '../../src/main/pipeline/queue'
import { createScheduler, type Scheduler } from '../../src/main/pipeline/scheduler'
import { STAGES } from '../../src/main/pipeline/stages'
import { createStateApplier } from '../../src/main/pipeline/state'
import type {
  AgentService,
  AIProvider,
  EmbeddingProvider,
  Intake,
  PageFetcher,
  Paths,
  Retrieval,
  StageDeps,
  WorkerClient
} from '../../src/main/ports'
import { createRetrieval } from '../../src/main/retrieval'
import { type Db, openDatabase } from '../../src/main/storage/db'
import { acquireLibraryLock, type LibraryLock } from '../../src/main/storage/library-lock'
import { createObjectStore } from '../../src/main/storage/object-store'
import { buildPaths, configFile, ensureLibraryDirs } from '../../src/main/storage/paths'
import { createRepositories } from '../../src/main/storage/repositories'
import type { IpcErrorCode } from '../../src/shared/ipc'
import {
  createFakeDesktop,
  createFakeLog,
  createFakePageFetcher,
  createFakePushTarget,
  createFakeSnapshotter,
  createFakeThumbnailer,
  createFakeUpdater,
  createNeverTimer,
  type FakeLog
} from './fakes'
import { type FixtureServer, fixtureFetchImpl, startFixtureServer } from './fixture-server'
import { HTML_FIXTURES, MODELS_DIR } from './lib'

/** A scenario file under `Tests/E2E/scenarios/`. */
export interface Scenario {
  name: string
  runs_on: 'linux' | 'macos'
  ai: 'mock' | 'scripted' | 'off'
  embeddings: 'hash' | 'bge'
  /** Replies for the scripted provider (and for `off` scenarios once AI is turned on). */
  replies?: ScriptedReplySpec[]
  /** Scenario whose finished library this one re-opens (library-compat). */
  library?: string
  steps: Record<string, unknown>[]
}

/** JSON form of a scripted reply: `{text}`, `{json}`, `{toolCalls}` or `{throw:{code,message}}`. */
export interface ScriptedReplySpec {
  text?: string
  json?: unknown
  toolCalls?: { name: string; args: unknown; id?: string }[]
  throw?: { code: string; message: string }
}

/** Map scenario JSON replies onto `createScriptedProvider` reply shapes. */
export function scriptedReplies(specs: ScriptedReplySpec[]): ScriptedReply[] {
  return specs.map((spec) => {
    // ScriptedReply's type omits Error even though the provider's dispatch accepts it.
    if (spec.throw) return new KaError(spec.throw.code as IpcErrorCode, spec.throw.message) as unknown as ScriptedReply
    if (spec.toolCalls) return toolCallResponse(spec.toolCalls)
    if (spec.json !== undefined) return jsonResponse(spec.json)
    return textResponse(spec.text ?? '')
  })
}

/** One `worker.call` over the real worker task registry, in-process. */
export function createInProcessWorker(): WorkerClient {
  const tasks = {
    ping: () => 'pong',
    ...EMBEDDING_WORKER_TASKS,
    ...EXTRACTION_WORKER_TASKS
  }
  return {
    call: async <T>(task: string, payload: unknown): Promise<T> => {
      const handler = tasks[task as keyof typeof tasks]
      if (!handler) throw new KaError('NOT_IMPLEMENTED', `Unknown worker task "${task}"`)
      try {
        return (await (handler as (p: unknown, s: AbortSignal) => unknown)(payload, new AbortController().signal)) as T
      } catch (error) {
        throw new KaError('INTERNAL', error instanceof Error ? error.message : String(error))
      }
    },
    terminate: () => {}
  }
}

export interface Boot {
  userData: string
  paths: Paths
  db: Db
  clock: ManualClock
  scheduler: Scheduler
  handlers: HandlerMap
  settings: SettingsStore
  queue: Queue
  intake: Intake
  retrieval: Retrieval
  agent: AgentService
  embeddings: EmbeddingProvider
  pageFetcher: PageFetcher
  fakes: FakeLog
  lock: LibraryLock
  readOnly: boolean
  close(): Promise<void>
}

export interface RunnerOptions {
  aiMode: Scenario['ai']
  replies?: ScriptedReplySpec[]
  /** 'hash' is always available; 'bge' needs the model files. */
  embeddings: 'hash' | 'bge'
  modelsDir?: string
  fixtureServer: FixtureServer
  /** Fresh logger-free clock start. */
  clockStart?: string
}

/**
 * Mirror of `src/main/index.ts` bootstrap minus Electron: real services over a temp userData,
 * manual clock, sequential ids, lane capacity 1, a scheduler timer that never fires (settle
 * drives everything), in-process worker, fixture-server pageFetcher/fetchImpl, and fakes that
 * record instead of writing.
 */
export function boot(userData: string, opts: RunnerOptions): Boot {
  const logger = silentLogger
  const paths = buildPaths(userData, opts.modelsDir ?? MODELS_DIR)
  ensureLibraryDirs(paths)

  const lock = acquireLibraryLock(paths.userData, {
    app: 'electron',
    version: '0.0.0',
    now: () => '2026-09-01T00:00:00.000Z'
  })
  const db = openDatabase(paths.dbFile, { readOnly: lock.readOnly })
  if (!lock.readOnly) db.migrate()
  const clock = createManualClock(opts.clockStart ?? '2026-09-01T00:00:00.000Z')
  const repos = createRepositories(db)
  const events = createEventBus(logger)
  const audit = createAuditService({ db, repos, events, clock, ids: sequentialIds('audit') })
  const queue = createQueue({ jobs: repos.jobs, clock, ids: sequentialIds('job') })
  // One `item` counter shared by intake and the item service: batch ids and item ids come from
  // the same sequence in creation order, so scenario authors can predict every `item-N`.
  const itemIds = sequentialIds('item')
  const items = createItemService({ db, repos, events, clock, audit, pipeline: queue, ids: itemIds })
  const collections = createCollectionService({
    db,
    repos,
    events,
    clock,
    audit,
    ids: sequentialIds('collection')
  })
  const relationships = createRelationshipService({
    db,
    repos,
    events,
    clock,
    audit,
    ids: sequentialIds('rel')
  })
  const objectStore = createObjectStore(paths)
  const worker = createInProcessWorker()
  const fakes = createFakeLog()
  const fetchImpl = fixtureFetchImpl(opts.fixtureServer)
  const pageFetcher = createFakePageFetcher(fakes, fetchImpl)
  const thumbnailer = createFakeThumbnailer(fakes)
  const snapshotter = createFakeSnapshotter(fakes)

  // A fake key for `gmi` makes `settings.update {ai:'on'}` reach `connected`, which is what
  // releases parked AI jobs — the provider itself is whatever the scenario declares.
  const settings = createSettingsStore({
    document: openConfigDocument(configFile(paths)),
    secrets: createMemorySecretStore(),
    env: {
      ...(opts.aiMode === 'mock' || opts.aiMode === 'scripted'
        ? { aiMode: 'mock' as const }
        : { aiMode: 'off' as const }),
      providers: { gmi: { apiKey: 'scenario-key' } }
    },
    paths
  })

  let scripted: AIProvider | null = null
  const buildAi = (): AIProvider => {
    const mode = settings.get().aiMode
    if (mode === 'off') return createOffProvider('gmi', settings.get().model, 'AI is turned off in Settings.')
    switch (opts.aiMode) {
      case 'scripted':
        // One provider per boot so replies are consumed in order, never reset mid-run.
        scripted ??= createScriptedProvider(scriptedReplies(opts.replies ?? []))
        return scripted
      case 'off':
        // `off` scenarios may carry replies for the post-`ai:'on'` phase: the scripted replies
        // answer first (errors included), then the mock provider takes over.
        if (opts.replies && opts.replies.length > 0) {
          scripted ??= (() => {
            const script = createScriptedProvider(scriptedReplies(opts.replies ?? []))
            const mock = createMockProvider({ logger, latencyMs: 0 })
            return {
              id: 'scripted',
              model: 'scripted',
              chat: (req) => (script.remaining() > 0 ? script.chat(req) : mock.chat(req)),
              generateStructured: (schema, req) =>
                script.remaining() > 0 ? script.generateStructured(schema, req) : mock.generateStructured(schema, req)
            }
          })()
          return scripted
        }
        return createOffProvider('gmi', settings.get().model, 'AI is turned off in Settings.')
      default:
        return createMockProvider({ logger, latencyMs: 0 })
    }
  }

  const embeddings =
    opts.embeddings === 'bge'
      ? createEmbeddingProvider({ worker, modelsDir: opts.modelsDir ?? MODELS_DIR, logger })
      : createHashEmbeddingProvider()

  const stageDeps: StageDeps = {
    worker,
    events,
    pageFetcher,
    thumbnailer,
    snapshotter,
    objectStore,
    ai: buildAi(),
    embeddings,
    fetchImpl,
    repos: repos as unknown as Record<string, unknown>
  }
  const retrieval = createRetrieval({ db, repos, embeddings, logger, clock })
  const agent = createAgentService({
    db,
    repos,
    retrieval,
    ai: () => stageDeps.ai as AIProvider,
    items,
    collections,
    relationships,
    audit,
    events,
    clock,
    logger,
    paths,
    objectStore,
    queue,
    ids: sequentialIds('run')
  })
  Object.assign(stageDeps, { retrieval, agent, collections, relationships, queue })

  const state = createStateApplier({ db, repos, queue, clock, logger })
  const scheduler = createScheduler({
    db,
    repos,
    queue,
    state,
    stages: STAGES,
    deps: stageDeps,
    paths,
    logger,
    clock,
    events,
    lanes: { io: 1, embed: 1, ai: 1 },
    timer: createNeverTimer()
  })
  const intake = createIntake({
    db,
    items,
    collections,
    pipeline: queue,
    objectStore,
    settings: () => settings.get(),
    clock,
    logger,
    worker,
    // Shared with the item service: batch ids and item ids come from the same `item` counter.
    ids: itemIds,
    tmpDir: '/tmp/x'
  })

  const push = createIpcPush(() => [createFakePushTarget(fakes)])
  const syncAiLane = (): void => {
    const status = settings.aiStatus()
    if (status === 'off' || status === 'unconfigured') scheduler.pauseAi()
    else scheduler.resumeAi()
  }
  settings.onChange(() => {
    stageDeps.ai = buildAi()
    syncAiLane()
  })

  const handlers = createHandlers({
    items,
    collections,
    relationships,
    audit,
    repos,
    queue,
    settings,
    objectStore,
    paths,
    clock,
    logger,
    desktop: createFakeDesktop(fakes),
    updater: createFakeUpdater(),
    push,
    intake,
    retrieval,
    agent,
    ai: () => stageDeps.ai as AIProvider,
    embeddings,
    testConnection: async () => ({ ok: false, model: 'mock', latencyMs: 0, error: 'unavailable' }),
    resetData: async () => {},
    onSettingsChanged: syncAiLane
  })

  syncAiLane()
  scheduler.start()

  return {
    userData,
    paths,
    db,
    clock,
    scheduler,
    handlers,
    settings,
    queue,
    intake,
    retrieval,
    agent,
    embeddings,
    pageFetcher,
    fakes,
    lock,
    readOnly: lock.readOnly,
    async close() {
      await scheduler.stop()
      db.close()
      lock.release()
    }
  }
}

/** Temp userData root for a scenario run. */
export function makeUserData(tag: string): string {
  return mkdtempSync(join(tmpdir(), `ka-scenario-${tag}-`))
}

export function removeUserData(dir: string): void {
  rmSync(dir, { recursive: true, force: true })
}

/** bge model availability for `embeddings: "bge"` scenarios. */
export function bgeAvailable(modelsDir = MODELS_DIR): boolean {
  return modelFilesPresent(modelsDir)
}

export async function createFixtureServer(): Promise<FixtureServer> {
  return startFixtureServer(HTML_FIXTURES)
}
