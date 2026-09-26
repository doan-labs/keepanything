import { existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

/** `Tests/E2E/` at the repo root (scenarios/, expected/, compare.json, optional library/). */
export const E2E_ROOT = resolve(__dirname, '../../../Tests/E2E')
export const SCENARIOS_DIR = resolve(E2E_ROOT, 'scenarios')
export const EXPECTED_DIR = resolve(E2E_ROOT, 'expected')
/** Drop corpus: `capture.files` paths in scenarios are relative to this. */
export const CORPUS_FILES = resolve(__dirname, '../fixtures/corpus/files')
export const CORPUS_ROOT = resolve(__dirname, '../fixtures/corpus')
/** Static pages served by the fixture server. */
export const HTML_FIXTURES = resolve(__dirname, '../fixtures/html')
/** Embedding model files, same location the dev app uses. */
export const MODELS_DIR = resolve(__dirname, '../../build/models')

const README = 'Written by `cd electron && pnpm run scenarios:export`. Never hand-edited.\n'

export function writeText(absPath: string, text: string): void {
  mkdirSync(dirname(absPath), { recursive: true })
  writeFileSync(absPath, text)
}

export function writeJson(name: string, value: unknown): void {
  writeText(resolve(EXPECTED_DIR, name), `${JSON.stringify(value, null, 2)}\n`)
}

/** Scenario names on disk, sorted with a plain byte comparator. */
export function scenarioFiles(): string[] {
  if (!existsSync(SCENARIOS_DIR)) return []
  return readdirSync(SCENARIOS_DIR)
    .filter((f) => f.endsWith('.json'))
    .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
}

/** Recreate `expected/` and drop the never-edited README next to it. */
export function resetExpected(): void {
  rmSync(EXPECTED_DIR, { recursive: true, force: true })
  mkdirSync(EXPECTED_DIR, { recursive: true })
  writeText(resolve(EXPECTED_DIR, 'README.md'), README)
}
