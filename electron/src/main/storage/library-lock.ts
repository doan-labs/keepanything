import { closeSync, openSync, readFileSync, renameSync, unlinkSync, writeFileSync, writeSync } from 'node:fs'
import { join } from 'node:path'

/**
 * `library.lock` sits next to `library.db` and names the process that may write. Any app that
 * opens the library (Electron today, Swift later) uses the same JSON shape, so both sides agree
 * on who holds it: `{ "pid": 123, "app": "electron", "version": "0.1.0", "since": "<ISO>" }`.
 */
export interface LockOwner {
  pid: number
  app: string
  version: string
  since: string
}

export interface LibraryLock {
  /** False when this process holds `library.lock`; true when another live process does. */
  readonly readOnly: boolean
  /** The process that holds the lock (this one unless `readOnly`). */
  readonly owner: LockOwner
  /** Remove the file if this process still owns it. Safe to call twice. */
  release(): void
}

export interface AcquireLockOptions {
  pid?: number
  app?: string
  version?: string
  now?: () => string
  /** Liveness probe, `process.kill(pid, 0)` by default. */
  isAlive?: (pid: number) => boolean
}

export const LOCK_FILE_NAME = 'library.lock'

export function lockFile(userData: string): string {
  return join(userData, LOCK_FILE_NAME)
}

export function processIsAlive(pid: number): boolean {
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === 'EPERM'
  }
}

export function readLockOwner(file: string): LockOwner | null {
  let text: string
  try {
    text = readFileSync(file, 'utf8')
  } catch {
    return null
  }
  try {
    const parsed: unknown = JSON.parse(text)
    if (typeof parsed !== 'object' || parsed === null) return null
    const record = parsed as Record<string, unknown>
    if (typeof record.pid !== 'number' || !Number.isInteger(record.pid) || record.pid <= 0) return null
    return {
      pid: record.pid,
      app: typeof record.app === 'string' ? record.app : 'unknown',
      version: typeof record.version === 'string' ? record.version : '',
      since: typeof record.since === 'string' ? record.since : ''
    }
  } catch {
    return null
  }
}

/**
 * Take `library.lock` for this process. First writer wins via `O_EXCL`; a lock whose pid is dead
 * (or whose file is unreadable) is stale and taken over; a lock whose pid is alive leaves the
 * caller read-only.
 */
export function acquireLibraryLock(userData: string, options: AcquireLockOptions = {}): LibraryLock {
  const file = lockFile(userData)
  const isAlive = options.isAlive ?? processIsAlive
  const mine: LockOwner = {
    pid: options.pid ?? process.pid,
    app: options.app ?? 'electron',
    version: options.version ?? '',
    since: (options.now ?? (() => new Date().toISOString()))()
  }
  const payload = `${JSON.stringify(mine)}\n`

  const held = (): LibraryLock => ({
    readOnly: false,
    owner: mine,
    release: () => {
      const current = readLockOwner(file)
      if (current === null || current.pid !== mine.pid) return
      try {
        unlinkSync(file)
      } catch {
        // already gone
      }
    }
  })

  try {
    const fd = openSync(file, 'wx')
    try {
      writeSync(fd, payload)
    } finally {
      closeSync(fd)
    }
    return held()
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error
  }

  const existing = readLockOwner(file)
  if (existing !== null && existing.pid !== mine.pid && isAlive(existing.pid)) {
    return { readOnly: true, owner: existing, release: () => {} }
  }

  // Stale (dead pid, or unreadable): replace atomically so a concurrent reader never sees a torn file.
  const temp = `${file}.${mine.pid}.tmp`
  writeFileSync(temp, payload)
  renameSync(temp, file)
  return held()
}
