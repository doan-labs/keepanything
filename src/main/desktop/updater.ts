import type { AppUpdater } from 'electron-updater'
import type { UpdateStatus } from '../../shared/types'
import type { IpcPush } from '../ipc/events'
import type { Logger } from '../ports'

/** What the shell uses of electron-updater; a bare `EventEmitter` with two stubs in tests. */
export type UpdaterEngine = Pick<AppUpdater, 'on' | 'checkForUpdatesAndNotify' | 'quitAndInstall'>

export interface UpdaterActions {
  status(): UpdateStatus
  /** Resolves when the check (not the download) is done. Errors surface as `state: 'error'`. */
  check(): Promise<void>
  install(): void
}

export interface UpdaterOptions {
  /** Null outside packaged builds: there is no app-update.yml, so every action is a no-op. */
  engine: UpdaterEngine | null
  version: string
  push: IpcPush
  logger: Logger
}

/**
 * Mirrors electron-updater's events into one `UpdateStatus` and pushes every change to the
 * renderer. Downloads start on their own (autoDownload); `install` relaunches on the new version.
 */
export function createUpdater({ engine, version, push, logger }: UpdaterOptions): UpdaterActions {
  let current: UpdateStatus = { version, state: engine ? 'idle' : 'unavailable' }
  const set = (next: Omit<UpdateStatus, 'version'>): void => {
    current = { version, ...next }
    push.send('update:status', current)
  }

  if (engine) {
    engine.on('checking-for-update', () => set({ state: 'checking' }))
    engine.on('update-available', (info) => set({ state: 'downloading', latest: info.version, percent: 0 }))
    engine.on('download-progress', (p) =>
      set({ state: 'downloading', latest: current.latest, percent: Math.round(p.percent) })
    )
    engine.on('update-downloaded', (info) => set({ state: 'ready', latest: info.version }))
    engine.on('update-not-available', () => set({ state: 'current' }))
    // Without a listener an emitted 'error' throws out of the updater's internals and takes main down.
    engine.on('error', (error) => {
      logger.warn('update failed', { error })
      // A downloaded update stays installable even if a later check fails.
      if (current.state !== 'ready') set({ state: 'error', error: "Couldn't check for updates." })
    })
  }

  return {
    status: () => current,
    async check() {
      if (!engine) return
      // Rejections are also emitted as 'error', so the listener above already recorded them.
      await engine.checkForUpdatesAndNotify().catch(() => {})
    },
    install() {
      if (current.state === 'ready') engine?.quitAndInstall()
    }
  }
}
