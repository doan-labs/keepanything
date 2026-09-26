import { createHash } from 'node:crypto'
import { mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'

/** Parity fixture root (`Tests/Fixtures/parity` at the repo root). */
export const OUT = resolve(__dirname, '../../../Tests/Fixtures/parity')

const README = 'Written by `cd electron && pnpm run parity:export`. Never hand-edited.\n'

/** Wipe the output tree so removed fixtures do not linger, then recreate it with the README. */
export function resetOut(): void {
  rmSync(OUT, { recursive: true, force: true })
  mkdirSync(OUT, { recursive: true })
  writeFileSync(join(OUT, 'README.md'), README)
}

/** `JSON.stringify(value, null, 2) + '\n'`; keys stay in insertion order. */
export function writeJson(relPath: string, value: unknown): void {
  const file = join(OUT, relPath)
  mkdirSync(dirname(file), { recursive: true })
  writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`)
}

/** Byte copy into the output tree. */
export function writeFile(relPath: string, content: string | Uint8Array): void {
  const file = join(OUT, relPath)
  mkdirSync(dirname(file), { recursive: true })
  writeFileSync(file, content)
}

export function sha256(content: string | Uint8Array): string {
  return createHash('sha256').update(content).digest('hex')
}

/** Deterministic comparator (never localeCompare). */
export const cmp = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0)
