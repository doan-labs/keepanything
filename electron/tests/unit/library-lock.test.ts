import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { openDatabase } from '../../src/main/storage/db'
import {
  acquireLibraryLock,
  LOCK_FILE_NAME,
  lockFile,
  processIsAlive,
  readLockOwner
} from '../../src/main/storage/library-lock'

const dirs: string[] = []

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true })
})

function tempLibrary(): string {
  const dir = mkdtempSync(join(tmpdir(), 'ka-lock-'))
  dirs.push(dir)
  return dir
}

const alive = new Set<number>()
const isAlive = (pid: number): boolean => alive.has(pid)
const now = (): string => '2026-01-01T00:00:00.000Z'

describe('acquireLibraryLock', () => {
  it('the first app writes library.lock with its pid and holds it', () => {
    const dir = tempLibrary()
    alive.add(100)
    const lock = acquireLibraryLock(dir, { pid: 100, app: 'electron', version: '0.1.0', isAlive, now })
    expect(lock.readOnly).toBe(false)
    expect(lock.owner).toEqual({ pid: 100, app: 'electron', version: '0.1.0', since: now() })
    expect(lockFile(dir)).toBe(join(dir, LOCK_FILE_NAME))
    expect(JSON.parse(readFileSync(lockFile(dir), 'utf8'))).toEqual(lock.owner)
    expect(readLockOwner(lockFile(dir))).toEqual(lock.owner)

    lock.release()
    expect(existsSync(lockFile(dir))).toBe(false)
    expect(() => lock.release()).not.toThrow()
  })

  it('the second app to start sees a live owner and opens read-only', () => {
    const dir = tempLibrary()
    alive.add(100)
    const first = acquireLibraryLock(dir, { pid: 100, app: 'electron', version: '0.1.0', isAlive, now })
    const second = acquireLibraryLock(dir, { pid: 200, app: 'swift', version: '1.0.0', isAlive, now })
    expect(second.readOnly).toBe(true)
    expect(second.owner).toEqual(first.owner)

    second.release()
    expect(readLockOwner(lockFile(dir))).toEqual(first.owner)
    first.release()
    expect(existsSync(lockFile(dir))).toBe(false)
  })

  it('a stale lock from a dead pid is taken over', () => {
    const dir = tempLibrary()
    writeFileSync(
      lockFile(dir),
      `${JSON.stringify({ pid: 999, app: 'electron', version: '0.0.9', since: '2025-12-31T00:00:00.000Z' })}\n`
    )
    alive.add(300)
    const lock = acquireLibraryLock(dir, { pid: 300, app: 'electron', version: '0.1.0', isAlive, now })
    expect(lock.readOnly).toBe(false)
    expect(readLockOwner(lockFile(dir))).toEqual({ pid: 300, app: 'electron', version: '0.1.0', since: now() })
    expect(existsSync(`${lockFile(dir)}.300.tmp`)).toBe(false)
  })

  it('an unreadable lock file is treated as stale', () => {
    const dir = tempLibrary()
    writeFileSync(lockFile(dir), 'not json')
    alive.add(300)
    expect(readLockOwner(lockFile(dir))).toBeNull()
    const lock = acquireLibraryLock(dir, { pid: 300, isAlive, now })
    expect(lock.readOnly).toBe(false)
    expect(readLockOwner(lockFile(dir))?.pid).toBe(300)
  })

  it('release() leaves a lock that another process took over alone', () => {
    const dir = tempLibrary()
    alive.add(100)
    const first = acquireLibraryLock(dir, { pid: 100, isAlive, now })
    alive.delete(100)
    alive.add(200)
    const second = acquireLibraryLock(dir, { pid: 200, isAlive, now })
    expect(second.readOnly).toBe(false)
    first.release()
    expect(readLockOwner(lockFile(dir))?.pid).toBe(200)
  })

  it('processIsAlive answers for this process and for a pid that cannot exist', () => {
    expect(processIsAlive(process.pid)).toBe(true)
    expect(processIsAlive(2 ** 22 - 1)).toBe(false)
  })
})

describe('read-only database', () => {
  it('openDatabase({ readOnly: true }) reads a migrated library and refuses writes', () => {
    const dir = tempLibrary()
    const file = join(dir, 'library.db')
    const writer = openDatabase(file)
    writer.migrate()
    const version = writer.schemaVersion()
    writer.close()

    const reader = openDatabase(file, { readOnly: true })
    try {
      expect(reader.schemaVersion()).toBe(version)
      expect(reader.raw.prepare('PRAGMA journal_mode').get()).toEqual({ journal_mode: 'wal' })
      expect(() =>
        reader.raw.prepare("INSERT INTO suppressions (kind, key, created_at) VALUES ('x', 'y', '2026-01-01')").run()
      ).toThrow(/readonly/i)
    } finally {
      reader.close()
    }
  })
})
