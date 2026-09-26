import { cpSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { CORPUS_FILES, HTML_FIXTURES, resetExpected, SCENARIOS_DIR, scenarioFiles, writeJson } from './lib'
import { cleanupTemps, normalizeDocument, type RunContext, runOp, type StepResult } from './ops'
import {
  bgeAvailable,
  createFixtureServer,
  makeUserData,
  type RunnerOptions,
  removeUserData,
  type Scenario
} from './runner'

const enabled = process.env.KEEPANYTHING_SCENARIOS === '1'
const only = process.env.KA_SCENARIO
/** `scenarios:keep` sets this; kept libraries land in `<dir>/<name>/` (gitignored). */
const keepRoot = process.env.KEEPANYTHING_KEEP_LIBRARY ? resolve(process.env.KEEPANYTHING_KEEP_LIBRARY) : null

/** Replay another scenario's steps against a fresh library (for `open-library {kept}`). */
async function replayToKeep(
  name: string,
  server: Awaited<ReturnType<typeof createFixtureServer>>,
  keepDir: string
): Promise<void> {
  const scenario = JSON.parse(readFileSync(join(SCENARIOS_DIR, `${name}.json`), 'utf8')) as Scenario
  const userData = makeUserData(`keep-${name}`)
  const ctx: RunContext = {
    current: null,
    opts: {
      aiMode: scenario.ai,
      ...(scenario.replies ? { replies: scenario.replies } : {}),
      embeddings: scenario.embeddings,
      fixtureServer: server
    },
    pathMarkers: [],
    results: [],
    ownedTempDirs: []
  }
  const { boot } = await import('./runner')
  ctx.current = boot(userData, ctx.opts)
  try {
    for (const step of scenario.steps) {
      await runOp(ctx, step)
    }
    rmSync(keepDir, { recursive: true, force: true })
    cpSync(userData, keepDir, { recursive: true })
  } finally {
    await ctx.current?.close()
    cleanupTemps(ctx)
    removeUserData(userData)
  }
}

async function runScenario(file: string): Promise<'ok' | 'skipped'> {
  const scenario = JSON.parse(readFileSync(join(SCENARIOS_DIR, file), 'utf8')) as Scenario
  if (scenario.embeddings === 'bge' && !bgeAvailable()) {
    console.log(`[scenarios] skip ${scenario.name}: bge model files not present`)
    return 'skipped'
  }
  const server = await createFixtureServer()
  const userData = makeUserData(scenario.name)
  const opts: RunnerOptions = {
    aiMode: scenario.ai,
    ...(scenario.replies ? { replies: scenario.replies } : {}),
    embeddings: scenario.embeddings,
    fixtureServer: server
  }
  const ctx: RunContext = {
    current: null,
    opts,
    pathMarkers: [
      { find: CORPUS_FILES, marker: '{corpus}' },
      { find: HTML_FIXTURES, marker: '{fixture-html}' },
      { find: tmpdir(), marker: '{tmp}' },
      { find: userData, marker: '{library}' },
      // The fixture server picks a random port; stored URLs/pages reference it verbatim.
      { find: server.baseUrl, marker: '{fixture}' }
    ],
    results: [],
    ownedTempDirs: [userData]
  }

  const { boot } = await import('./runner')
  const steps: { op: string; input: Record<string, unknown>; result: StepResult }[] = []
  try {
    // library-compat: rebuild the named scenario's library into a temp keep dir first.
    if (scenario.library) {
      const keepDir = mkdtempSync(join(tmpdir(), `ka-keep-${scenario.name}-`))
      ctx.ownedTempDirs.push(keepDir)
      await replayToKeep(scenario.library, server, keepDir)
    }
    ctx.current = boot(userData, opts)
    for (const raw of scenario.steps) {
      const step = { ...raw }
      // The library-compat kept dir is a runner placeholder, not a literal path.
      if (step.op === 'open-library' && step.path === '{kept}' && scenario.library) {
        step.path = ctx.ownedTempDirs[ctx.ownedTempDirs.length - 1]
      }
      ctx.current?.clock.advance(1000)
      const input = { ...step }
      delete input.op
      const result = await runOp(ctx, step)
      ctx.lastResult = result
      steps.push({ op: String(step.op), input, result })
    }
    if (keepRoot) {
      const dest = join(keepRoot, scenario.name)
      rmSync(dest, { recursive: true, force: true })
      if (ctx.current) cpSync(ctx.current.paths.userData, dest, { recursive: true })
    }
  } finally {
    await ctx.current?.close()
    cleanupTemps(ctx)
    server.close()
  }

  const doc = normalizeDocument(
    {
      name: scenario.name,
      runsOn: scenario.runs_on,
      ai: scenario.ai,
      embeddings: scenario.embeddings,
      steps,
      results: ctx.results
    },
    ctx.pathMarkers
  )
  writeJson(`${scenario.name}.json`, doc)
  return 'ok'
}

describe.skipIf(!enabled)('e2e scenarios', () => {
  if (!only) resetExpected()
  for (const file of scenarioFiles()) {
    const name = file.replace(/\.json$/, '')
    it.skipIf(Boolean(only) && only !== name)(name, async () => {
      expect(await runScenario(file)).toBeDefined()
    })
  }
})
