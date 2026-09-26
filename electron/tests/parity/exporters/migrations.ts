import { readdirSync, readFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { MIGRATIONS } from '../../../src/main/storage/db'
import { sha256, writeFile, writeJson } from '../lib'

const MIGRATIONS_DIR = resolve(__dirname, '../../../src/main/storage/migrations')

export function exportMigrations(): void {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort()
  for (const file of files) {
    writeFile(`migrations/${file}`, readFileSync(join(MIGRATIONS_DIR, file)))
  }
  writeJson(
    'migrations.json',
    MIGRATIONS.map((m) => ({
      version: m.version,
      name: m.name,
      file: `${m.name}.sql`,
      sha256: sha256(m.sql)
    }))
  )
}
