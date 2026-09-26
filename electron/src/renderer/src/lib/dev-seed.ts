/**
 * Placeholder content for a dev library, dropped through the real capture channels so items go
 * through the actual pipeline. `scripts/seed-library.mjs` does the same from outside for
 * screenshots; this one is the in-app version, reachable from ⌘K in dev builds only.
 *
 * When `dev-seed.data.json` holds a snapshot, the seed turns AI off for the run and writes the
 * recorded understanding afterwards: same library, no provider calls.
 */
import type { CaptureResult } from '../../../shared/types'
import snapshot from './dev-seed.data.json'
import { invoke, type Result } from './ipc-client'

/** One recorded item, positionally aligned with `PLAN`. Regenerate via ⌘K -> library snapshot. */
interface SeedSnapshot {
  label: string
  title: string
  understanding: string | null
  whyUseful: string | null
}

const SNAPSHOT: SeedSnapshot[] = snapshot

const NOTES: [title: string, body: string][] = [
  [
    'Reading list',
    `# Reading list

Placeholder note so the library has a markdown item.

## Queue
- Sample entry one, kept short on purpose.
- Sample entry two, with a second line so the excerpt wraps.
- Sample entry three.
`
  ],
  [
    'Project kickoff',
    `# Project kickoff

## Agenda
1. Scope
2. Milestones
3. Open questions

Longer paragraph so the detail pane has body text to render, and so extraction produces an excerpt
rather than a single line. Nothing here refers to anything real.
`
  ],
  [
    'Weekly summary',
    `# Weekly summary

- Shipped: sample item A
- In progress: sample item B
- Blocked: sample item C

Second paragraph, present so the card preview has more than one line to lay out.
`
  ],
  ['Todo', '- placeholder task one\n- placeholder task two\n- placeholder task three\n']
]

const IMAGES: [name: string, hex: string, w: number, h: number][] = [
  ['Sample wide.png', '#2b4c7e', 1200, 700],
  ['Sample tall.png', '#4a3b6b', 620, 900],
  ['Sample square.png', '#2f6b58', 800, 800]
]

const LINKS = ['https://www.electronjs.org/docs/latest', 'https://vitejs.dev/guide/', 'https://react.dev/learn']

/** Flat colour with a lighter lower band, so thumbnails are distinguishable from each other. */
async function png(hex: string, w: number, h: number): Promise<ArrayBuffer> {
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('no 2d context')
  ctx.fillStyle = hex
  ctx.fillRect(0, 0, w, h)
  ctx.fillStyle = 'rgba(255, 255, 255, 0.12)'
  ctx.fillRect(0, h * 0.58, w, h)
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'))
  if (!blob) throw new Error('toBlob failed')
  return blob.arrayBuffer()
}

/** Capture order is the contract with `SNAPSHOT`: same length, same labels, same positions. */
const PLAN: { label: string; run: () => Promise<Result<CaptureResult>> }[] = [
  ...NOTES.map(([title, text]) => ({
    label: `note:${title}`,
    run: () => invoke('capture:text', { text, title })
  })),
  ...IMAGES.map(([name, hex, w, h]) => ({
    label: `image:${name}`,
    run: async () => invoke('capture:blob', { name, mimeType: 'image/png', bytes: await png(hex, w, h) })
  })),
  ...LINKS.map((url) => ({ label: `link:${url}`, run: () => invoke('capture:url', { url }) }))
]

export const SEED_LABELS: string[] = PLAN.map((p) => p.label)

const TERMINAL = new Set(['READY', 'PARTIAL', 'EXTRACTION_FAILED', 'AI_FAILED'])

/** Poll until every id reaches a terminal status, or the timeout passes (dev seed: never blocks). */
async function settle(ids: string[], timeoutMs = 90_000): Promise<void> {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const r = await invoke('items:list', { view: 'library', limit: 500 })
    const mine = r.ok ? r.data.filter((s) => ids.includes(s.id)) : []
    if (mine.length >= ids.length && mine.every((s) => TERMINAL.has(s.processingStatus))) return
    await new Promise((resolve) => setTimeout(resolve, 400))
  }
}

/** Keeps the placeholder corpus and replays the recorded AI output. Returns items captured. */
export async function seedDevLibrary(): Promise<number> {
  const prefill = SNAPSHOT.length === PLAN.length && SNAPSHOT.every((s, i) => s.label === PLAN[i]?.label)
  const settings = await invoke('settings:get', undefined)
  const aiWasOn = settings.ok && settings.data.aiMode !== 'off'
  if (prefill && aiWasOn) await invoke('settings:update', { ai: 'off' })

  const ids: string[] = []
  for (const step of PLAN) {
    const r = await step.run()
    const id = r.ok ? r.data.items[0]?.id : undefined
    if (id) ids.push(id)
  }

  if (prefill) {
    await settle(ids)
    for (const [i, id] of ids.entries()) {
      const s = SNAPSHOT[i]
      // ponytail: `items:update` marks these as user overrides. Fine for a seed - it also stops
      // the agent from rewriting them the next time AI is on.
      if (s)
        await invoke('items:update', {
          id,
          patch: { title: s.title, understanding: s.understanding ?? undefined, whyUseful: s.whyUseful ?? undefined }
        })
    }
  }
  if (prefill && aiWasOn) await invoke('settings:update', { ai: 'on' })
  return ids.length
}

/** The current library as `dev-seed.data.json`, oldest capture first so it lines up with `PLAN`. */
export async function librarySnapshotSource(): Promise<string> {
  const r = await invoke('items:list', { view: 'library', limit: 500 })
  if (!r.ok) throw new Error(r.error.message)
  const ordered = [...r.data].sort((a, b) => a.capturedAt.localeCompare(b.capturedAt))
  const rows: SeedSnapshot[] = []
  for (const [i, summary] of ordered.entries()) {
    const detail = await invoke('items:get', { id: summary.id })
    const item = detail.ok ? detail.data.item : null
    rows.push({
      label: SEED_LABELS[i] ?? `unknown:${i}`,
      title: item?.title ?? summary.title,
      understanding: item?.understanding ?? null,
      whyUseful: item?.whyUseful ?? null
    })
  }
  return `${JSON.stringify(rows, null, 2)}\n`
}
