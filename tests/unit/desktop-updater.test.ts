import { EventEmitter } from 'node:events'
import { describe, expect, it, vi } from 'vitest'
import { createUpdater, type UpdaterEngine } from '../../src/main/desktop/updater'
import { silentLogger } from '../../src/main/lib/logger'
import type { UpdateStatus } from '../../src/shared/types'

function harness() {
  const emitter = new EventEmitter()
  const quitAndInstall = vi.fn()
  const checkForUpdatesAndNotify = vi.fn(async () => null)
  const engine = Object.assign(emitter, { quitAndInstall, checkForUpdatesAndNotify }) as unknown as UpdaterEngine
  const pushed: UpdateStatus[] = []
  const updater = createUpdater({
    engine,
    version: '0.2.0',
    push: { send: (_event, payload) => pushed.push(payload as UpdateStatus) },
    logger: silentLogger
  })
  return { emitter, quitAndInstall, checkForUpdatesAndNotify, pushed, updater }
}

describe('updater', () => {
  it('is unavailable without an engine and every action is a no-op', async () => {
    const updater = createUpdater({
      engine: null,
      version: '0.2.0',
      push: { send: () => {} },
      logger: silentLogger
    })
    expect(updater.status()).toEqual({ version: '0.2.0', state: 'unavailable' })
    await updater.check()
    updater.install()
  })

  it('walks check -> download -> ready and only then installs', async () => {
    const { emitter, quitAndInstall, checkForUpdatesAndNotify, pushed, updater } = harness()
    expect(updater.status().state).toBe('idle')
    updater.install()
    expect(quitAndInstall).not.toHaveBeenCalled()

    await updater.check()
    expect(checkForUpdatesAndNotify).toHaveBeenCalledOnce()
    emitter.emit('checking-for-update')
    emitter.emit('update-available', { version: '0.2.1' })
    emitter.emit('download-progress', { percent: 41.6 })
    expect(updater.status()).toEqual({ version: '0.2.0', state: 'downloading', latest: '0.2.1', percent: 42 })
    emitter.emit('update-downloaded', { version: '0.2.1' })
    expect(updater.status()).toMatchObject({ state: 'ready', latest: '0.2.1' })
    expect(pushed.map((p) => p.state)).toEqual(['checking', 'downloading', 'downloading', 'ready'])

    updater.install()
    expect(quitAndInstall).toHaveBeenCalledOnce()
  })

  it('reports errors but keeps a downloaded update installable', () => {
    const { emitter, updater } = harness()
    emitter.emit('error', new Error('offline'))
    expect(updater.status()).toMatchObject({ state: 'error', error: "Couldn't check for updates." })
    emitter.emit('update-downloaded', { version: '0.2.1' })
    emitter.emit('error', new Error('offline'))
    expect(updater.status().state).toBe('ready')
    emitter.emit('update-not-available')
    expect(updater.status().state).toBe('current')
  })
})
