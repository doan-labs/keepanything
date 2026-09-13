import * as stylex from '@stylexjs/stylex'
import {
  AlignLeft,
  Check,
  Eye,
  File,
  FileText,
  Folder,
  Image,
  Layers,
  Link,
  type LucideIcon,
  Music,
  Video,
  X
} from 'lucide-react'
import { type DragEvent, useEffect, useRef, useState } from 'react'
import { COPY } from '../../../../../shared/constants'
import { SHELF, type ShelfEdge } from '../../../../../shared/layout'
import { isFailed, isTerminal, STATUS_LABEL } from '../../../../../shared/status'
import type { ItemSummary } from '../../../../../shared/types'
import { hasExternalPayload, isInternalDrag, setInternalDrag, snapshotDrop } from '../../../lib/dnd'
import { type DragPeek, type DragPeekKind, dragPeekLabel, peekDrag } from '../../../lib/drag-peek'
import { ago } from '../../../lib/format'
import { getPathForFile, invoke, isMockBridge, on } from '../../../lib/ipc-client'
import { shelfOutline } from '../../../lib/shelf-outline'
import { shared } from '../../../styles/shared'
import { Dot, Thumb, toneForStatus } from '../../common'
import { styles } from './styles'

const MAX_TILES = 12

/** A settled tile has done its job: it stays long enough to be read, then shows itself out. */
const TILE_SETTLED_MS = 3000

/** Cap for a tile that never settles (failed, or parked with no AI): the shelf is not an inbox. */
const TILE_MAX_MS = 10 * 60_000

/** Matches the tile's exit transition in `styles.ts` (`motion.slow`). */
const TILE_EXIT_MS = 260

/** Tiles leave one after another rather than all in the same frame. */
const TILE_STAGGER_MS = 90

const PEEK_ICON: Record<DragPeekKind, LucideIcon> = {
  link: Link,
  pdf: FileText,
  image: Image,
  video: Video,
  audio: Music,
  text: AlignLeft,
  folder: Folder,
  file: File,
  mixed: Layers
}

/**
 * ShelfView (`?view=shelf`): a notch that grows out of the screen edge. Things dropped here are
 * kept immediately and appear as compact tiles, which retire themselves once the item is
 * understood — the library has it, so the strip empties back to a drop target. Tiles are draggable
 * (internal item drag) and can be Quick-Looked; the strip follows `items:changed` so status
 * settles in place.
 * Main announces `shelf:presence` around every show and hide so the panel can slide in from the
 * edge, and slide back out before the window disappears.
 */
/**
 * Icon and label for what is hovering the shelf. A pair of different things shows both icons,
 * overlapped; anything else shows the one icon for the set. Keyed on the label so a drag that
 * changes shape (rare, but a multi-item drag can grow) replays the pop-in.
 */
function PeekBadge({ peek }: { peek: DragPeek }): React.JSX.Element {
  const label = dragPeekLabel(peek)
  const icons = peek.count === 2 && peek.parts.length === 2 ? peek.parts.map((p) => p.kind) : [peek.kind]
  return (
    <span key={label} {...stylex.props(styles.peekBadge)}>
      {icons.map((kind, i) => {
        const Icon = PEEK_ICON[kind]
        return (
          <span key={kind} {...stylex.props(styles.peekIcon, i > 0 && styles.peekIconStacked)}>
            <Icon size={18} strokeWidth={1.5} />
          </span>
        )
      })}
      <span {...stylex.props(styles.peekLabel)}>{label}</span>
    </span>
  )
}

export function ShelfView(): React.JSX.Element {
  const [items, setItems] = useState<ItemSummary[]>([])
  // The mock never announces presence, so a browser-only dev session shows the shelf straight away.
  const [visible, setVisible] = useState(() => isMockBridge())
  const [edge, setEdge] = useState<ShelfEdge>('right')
  const [over, setOver] = useState(false)
  /** What the drag hovering the shelf looks like; null until something is over it. */
  const [peek, setPeek] = useState<DragPeek | null>(null)
  /** Folder count from the last `shelf:drag`; stays 0 when the sidecar is not running. */
  const draggedFolders = useRef(0)
  const [flash, setFlash] = useState<string | null>(null)
  const flashTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  /** Tiles playing their exit; still in `items` until the transition is over. */
  const [leaving, setLeaving] = useState<string[]>([])
  /** The pointer is on the strip, or a tile has focus: nothing retires under it. */
  const [held, setHeld] = useState(false)

  const say = (message: string): void => {
    setFlash(message)
    if (flashTimer.current) clearTimeout(flashTimer.current)
    flashTimer.current = setTimeout(() => setFlash(null), 1600)
  }

  useEffect(() => {
    const offPresence = on('shelf:presence', (p) => {
      setEdge(p.edge)
      setVisible(p.visible)
      if (!p.visible) {
        setOver(false)
        setPeek(null)
      }
    })
    const offDrag = on('shelf:drag', ({ folders }) => {
      draggedFolders.current = folders
    })
    const offDropped = on('shelf:dropped', ({ result }) => {
      const ids = result.items.map((i) => i.existingId ?? i.id)
      if (ids.length === 0) return
      void invoke('items:list', { view: 'library', sort: 'captured', limit: 40 }).then((r) => {
        if (!r.ok) return
        const fresh = ids.map((id) => r.data.find((i) => i.id === id)).filter((i): i is ItemSummary => Boolean(i))
        // Dropped again while its tile was retiring: it stays.
        setLeaving((prev) => (prev.length === 0 ? prev : prev.filter((id) => !ids.includes(id))))
        setItems((prev) => {
          const map = new Map(prev.map((i) => [i.id, i]))
          for (const f of fresh) map.set(f.id, f)
          return [...map.values()]
            .sort((a, b) => Date.parse(b.capturedAt) - Date.parse(a.capturedAt))
            .slice(0, MAX_TILES)
        })
      })
    })
    const offChanged = on('items:changed', (event) => {
      setItems((prev) => {
        const map = new Map(prev.map((i) => [i.id, i]))
        // Same array back when the event was about items the shelf does not hold: this fires for
        // the whole library, and a new array would restart every tile's retirement timer.
        let touched = false
        for (const s of event.summaries ?? [])
          if (map.has(s.id)) {
            map.set(s.id, s)
            touched = true
          }
        if (event.reason === 'trashed' || event.reason === 'deleted')
          for (const id of event.ids) touched = map.delete(id) || touched
        return touched ? [...map.values()] : prev
      })
    })
    return () => {
      offPresence()
      offDrag()
      offDropped()
      offChanged()
    }
  }, [])

  // A tile is a receipt, not a to-do: once the item is understood it leaves by itself, and nothing
  // outstays TILE_MAX_MS. Held tiles wait — one must never slide out from under a hand reaching
  // for it — and the timers restart when the pointer leaves, so a held tile gets its full beat.
  useEffect(() => {
    if (held || items.length === 0) return
    const timers = items.map((item, i) =>
      setTimeout(
        () => setLeaving((prev) => (prev.includes(item.id) ? prev : [...prev, item.id])),
        (isTerminal(item.processingStatus) ? TILE_SETTLED_MS : TILE_MAX_MS) + i * TILE_STAGGER_MS
      )
    )
    return () => {
      for (const t of timers) clearTimeout(t)
    }
  }, [items, held])

  useEffect(() => {
    if (leaving.length === 0) return
    const timer = setTimeout(() => {
      setItems((prev) => prev.filter((i) => !leaving.includes(i.id)))
      setLeaving([])
    }, TILE_EXIT_MS)
    return () => clearTimeout(timer)
  }, [leaving])

  const onDrop = async (e: DragEvent): Promise<void> => {
    e.preventDefault()
    setOver(false)
    setPeek(null)
    if (isInternalDrag(e.dataTransfer)) return
    const request = snapshotDrop(e.dataTransfer, getPathForFile, 'shelf')
    const result = await invoke('capture:drop', request)
    if (!result.ok) {
      say(COPY.cantReadPage)
      return
    }
    const created = result.data.items.filter((i) => i.status === 'created').length
    const dupes = result.data.items.length - created
    say(created === 0 && dupes > 0 ? 'Already kept.' : created > 1 ? `Saved ${created}.` : COPY.saved)
  }

  const onDragStart = (item: ItemSummary, e: DragEvent): void => {
    setInternalDrag(e.dataTransfer, [item.id])
  }

  const right = edge === 'right'
  return (
    <div
      {...stylex.props(
        styles.dock,
        right ? styles.dockOriginRight : styles.dockOriginLeft,
        visible ? styles.dockIn : right ? styles.dockOutRight : styles.dockOutLeft
      )}
      data-edge={edge}
      onDragOver={(e) => {
        if (isInternalDrag(e.dataTransfer) || !hasExternalPayload(e.dataTransfer)) return
        e.preventDefault()
        e.dataTransfer.dropEffect = 'copy'
        setOver(true)
        const next = peekDrag(e.dataTransfer, draggedFolders.current)
        setPeek((prev) =>
          prev &&
          next &&
          prev.kind === next.kind &&
          prev.count === next.count &&
          prev.parts.length === next.parts.length
            ? prev
            : next
        )
      }}
      onDragLeave={() => {
        setOver(false)
        setPeek(null)
      }}
      onDrop={(e) => void onDrop(e)}
    >
      <svg {...stylex.props(styles.shape)} aria-hidden="true" focusable="false">
        <path d={shelfOutline(edge, true)} {...stylex.props(styles.shapeFill)} />
        <path d={shelfOutline(edge, false)} {...stylex.props(styles.shapeLine, over && styles.shapeLineOver)} />
      </svg>
      <div
        {...stylex.props(
          styles.body(SHELF.fillet, SHELF.body.width),
          right ? styles.bodyRight : styles.bodyLeft,
          visible ? styles.bodyIn : right ? styles.bodyOutRight : styles.bodyOutLeft
        )}
      >
        <div {...stylex.props(styles.strip)}>
          {flash ? (
            <span key={flash} {...stylex.props(styles.flash)}>
              <Check size={12} strokeWidth={2} {...stylex.props(styles.flashIcon)} />
              {flash}
            </span>
          ) : items.length > 0 ? (
            <button type="button" {...stylex.props(shared.hoverFade, styles.clear)} onClick={() => setItems([])}>
              <X size={11} strokeWidth={1.5} />
              Clear
            </button>
          ) : null}
        </div>
        <div {...stylex.props(styles.target, over && styles.targetOver)} aria-label="Drop target">
          <svg {...stylex.props(styles.targetRing)} aria-hidden="true" focusable="false">
            <rect {...stylex.props(styles.targetRingRect, over && styles.targetRingRectOver)} />
          </svg>
          {over ? (
            <>
              <span key="over" {...stylex.props(styles.swapIn)}>
                Let go to keep it
              </span>
              {peek ? <PeekBadge peek={peek} /> : null}
            </>
          ) : items.length === 0 ? (
            <span key="hero" {...stylex.props(styles.targetHero, styles.swapIn)}>
              {COPY.dropHere}
            </span>
          ) : (
            <span key="hint" {...stylex.props(styles.swapIn)}>
              {COPY.dropHint}
            </span>
          )}
        </div>
        <div {...stylex.props(styles.list)} aria-label="Kept from the shelf">
          {items.length === 0 ? (
            <p {...stylex.props(styles.empty)}>Drop files, links or text here while you work.</p>
          ) : null}
          {items.map((i) => {
            const working = !isTerminal(i.processingStatus)
            return (
              <div
                key={i.id}
                {...stylex.props(
                  styles.tile,
                  styles.tileFocus,
                  leaving.includes(i.id) && styles.tileOut,
                  stylex.defaultMarker()
                )}
                draggable
                onDragStart={(e) => onDragStart(i, e)}
                onMouseEnter={() => setHeld(true)}
                onMouseLeave={() => setHeld(false)}
                onFocus={() => setHeld(true)}
                onBlur={() => setHeld(false)}
                // A drag can end with the pointer anywhere; `mouseleave` may never come.
                onDragEnd={() => setHeld(false)}
                onDoubleClick={() => void invoke('items:quickLook', { id: i.id })}
                title="Drag into a collection, or double-click to Quick Look"
                tabIndex={0}
              >
                <span {...stylex.props(styles.thumb)}>
                  <Thumb src={i.thumbnailUrl} fill={i.dominantColor} />
                </span>
                <span {...stylex.props(styles.text)}>
                  <span {...stylex.props(styles.title, shared.ellipsis)}>{i.title}</span>
                  <span {...stylex.props(styles.sub)}>
                    {working || isFailed(i.processingStatus) ? <Dot tone={toneForStatus(i.processingStatus)} /> : null}
                    <span {...stylex.props(shared.ellipsis)}>
                      {working || isFailed(i.processingStatus)
                        ? STATUS_LABEL[i.processingStatus]
                        : `Kept ${ago(i.capturedAt)}`}
                    </span>
                  </span>
                </span>
                <button
                  type="button"
                  {...stylex.props(styles.peek)}
                  aria-label="Quick Look"
                  onClick={() => void invoke(i.type === 'url' ? 'items:openUrl' : 'items:quickLook', { id: i.id })}
                >
                  <Eye size={12} strokeWidth={1.5} />
                </button>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
