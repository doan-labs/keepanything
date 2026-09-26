import { FETCH_USER_AGENT } from '../../src/main/desktop/dom-fallback'
import type { PushTarget } from '../../src/main/ipc/events'
import type { DesktopActions } from '../../src/main/ipc/handlers/deps'
import type { SchedulerTimer } from '../../src/main/pipeline/scheduler'
import type { PageFetcher, PreviewSize, SnapshotResult, Snapshotter, Thumbnailer } from '../../src/main/ports'
import type { UpdateStatus } from '../../src/shared/types'

/** Every recorded fake call lands here and becomes part of the snapshot. */
export interface FakeLog {
  thumbnailCalls: { op: string; file: string; out: string; maxPx: number }[]
  snapshotCalls: { url: string; out: string }[]
  fetchCalls: { op: string; url: string }[]
  desktopCalls: { op: string; args: unknown }[]
  pushes: { event: string; payload: unknown }[]
}

export function createFakeLog(): FakeLog {
  return { thumbnailCalls: [], snapshotCalls: [], fetchCalls: [], desktopCalls: [], pushes: [] }
}

const NOTHING: PreviewSize | null = null

/** Records every call, writes nothing, always reports "no preview could be made". */
export function createFakeThumbnailer(log: FakeLog): Thumbnailer {
  const record = (op: string, filePath: string, outPath: string, maxPx: number): PreviewSize | null => {
    log.thumbnailCalls.push({ op, file: filePath, out: outPath, maxPx })
    return NOTHING
  }
  return {
    thumbnail: async (filePath, outPath, maxPx) => record('thumbnail', filePath, outPath, maxPx),
    visionImage: async (filePath, outPath, maxPx) => record('visionImage', filePath, outPath, maxPx),
    dominantColorOf: async (imagePath) => {
      log.thumbnailCalls.push({ op: 'dominantColorOf', file: imagePath, out: '', maxPx: 0 })
      return null
    }
  }
}

/** Records every call, writes nothing, always reports "no snapshot". */
export function createFakeSnapshotter(log: FakeLog): Snapshotter {
  return {
    snapshot: async (url, outPath): Promise<SnapshotResult | null> => {
      log.snapshotCalls.push({ url, out: outPath })
      return null
    },
    dispose: () => {}
  }
}

/**
 * `PageFetcher` against the fixture server. `fetchHtml` mirrors the desktop implementation's
 * semantics (browser UA, text only for text-ish content types); `fetchDom` always fails — the
 * real one needs an offscreen `BrowserWindow`, which does not exist outside Electron.
 */
export function createFakePageFetcher(log: FakeLog, fetchImpl: typeof fetch): PageFetcher {
  return {
    async fetchHtml(url) {
      log.fetchCalls.push({ op: 'fetchHtml', url })
      try {
        const response = await fetchImpl(url, {
          headers: {
            'User-Agent': FETCH_USER_AGENT,
            Accept: 'text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8'
          },
          redirect: 'follow'
        })
        const contentType = response.headers.get('content-type') ?? ''
        const html = /text\/|xml|json/.test(contentType) ? await response.text() : ''
        return { status: response.status, finalUrl: response.url || url, contentType, html }
      } catch {
        return null
      }
    },
    async fetchDom(url) {
      log.fetchCalls.push({ op: 'fetchDom', url })
      return null
    }
  }
}

export function createFakeDesktop(log: FakeLog): DesktopActions {
  const record = (op: string, args: unknown): void => {
    log.desktopCalls.push({ op, args })
  }
  return {
    openPath: async (path) => record('openPath', path),
    showItemInFolder: (path) => record('showItemInFolder', path),
    quickLook: async (path) => record('quickLook', path),
    openExternal: async (url) => record('openExternal', url),
    chooseFiles: async () => {
      record('chooseFiles', null)
      return []
    },
    contextMenu: async (kind, ids, collectionId) => {
      record('contextMenu', { kind, ids, collectionId })
      return {}
    },
    noteShelfDrop: () => record('noteShelfDrop', null)
  }
}

export function createFakeUpdater(): { status(): UpdateStatus; check(): Promise<void>; install(): void } {
  const status: UpdateStatus = { state: 'unavailable', version: '0.0.0' }
  return { status: () => status, check: async () => {}, install: () => {} }
}

/** Push target that records every event so it lands in the snapshot. */
export function createFakePushTarget(log: FakeLog): PushTarget {
  return {
    send(channel, payload) {
      log.pushes.push({ event: channel, payload })
    }
  }
}

/**
 * Scheduler timer that never fires: retries, AI resume windows and stage timeouts are all driven
 * by the runner's clock/settle instead of wall-clock, so nothing happens between steps.
 */
export function createNeverTimer(): SchedulerTimer {
  return { setTimeout: () => null, clearTimeout: () => {} }
}
