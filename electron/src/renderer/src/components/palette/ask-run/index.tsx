import Scritto from '@scritto/react'
import * as stylex from '@stylexjs/stylex'
import { ArrowLeft, Search } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useShallow } from 'zustand/react/shallow'
import { COPY } from '../../../../../shared/constants'
import type { AgentSource } from '../../../../../shared/types'
import { count, typeLabel } from '../../../lib/format'
import { describeError, invoke } from '../../../lib/ipc-client'
import {
  askMatched,
  askPhase,
  askScanned,
  askStatus,
  confirmStop,
  evidenceHeader,
  factSpans,
  formatElapsed,
  noteBodyFor,
  noteTitleFor,
  snippetSpans,
  type TextSpan
} from '../../../lib/palette'
import { useLibrary } from '../../../state/library'
import type { RunState } from '../../../state/runs'
import { useToasts } from '../../../state/toasts'
import { useUi } from '../../../state/ui'
import { shared } from '../../../styles/shared'
import { Button, Dot, Kbd, ProposalList, Thumb } from '../../common'
import { styles } from './styles'

/** Tiles in the scan strip. Past this the strip stops being the library and starts being wallpaper. */
const STRIP_MAX = 16
/** One pass of the scan head across the strip; must match `tileWave`'s duration. */
const WAVE_MS = 1500
const MAX_CARDS = 4
/** Word stagger for revealed text, and the point past which the rest of a long answer lands together. */
const WORD_STEP_MS = 18
const WORD_MAX_MS = 700

/** Milliseconds since `since`, ticking while `active`. */
function useElapsed(since: number | null, active: boolean): number {
  const [now, setNow] = useState(Date.now())
  useEffect(() => {
    if (!active) return
    const t = setInterval(() => setNow(Date.now()), 200)
    return () => clearInterval(t)
  }, [active])
  return since ? Math.max(0, now - since) : 0
}

/** Words with their trailing space kept, so wrapping is exactly what it would be in one string. */
function words(text: string): string[] {
  return text.split(/(?<=\s)(?=\S)/)
}

/**
 * Text landing word by word: each one resolves out of a blur on a short stagger, capped so a long
 * answer still finishes in under a second.
 */
function Spans({ spans, hot }: { spans: TextSpan[]; hot: 'mark' | 'fact' }): React.JSX.Element {
  let at = 0
  let n = 0
  return (
    <>
      {spans.map((span) => {
        const start = at
        at += span.text.length
        return (
          <span key={start} {...stylex.props(span.hot && (hot === 'mark' ? styles.mark : styles.fact))}>
            {words(span.text).map((word) => {
              const key = start + n
              const delay = Math.min(n * WORD_STEP_MS, WORD_MAX_MS)
              n += 1
              return (
                <span key={key} {...stylex.props(styles.word, styles.wordDelay(delay))}>
                  {word}
                </span>
              )
            })}
          </span>
        )
      })}
    </>
  )
}

interface ScanStripProps {
  /** Item ids the run has touched so far, first seen first. */
  scanned: string[]
  matched: string[]
  running: boolean
  onOpen: (id: string) => void
}

/**
 * The library as a filmstrip with a head running over it: what "looking through everything" looks
 * like. The tiles are real items, the counter is the real total, and matches stay lit behind the head.
 */
function ScanStrip({ scanned, matched, running, onOpen }: ScanStripProps): React.JSX.Element {
  const order = useLibrary(useShallow((s) => s.order))
  const byId = useLibrary((s) => s.byId)
  const [hovered, setHovered] = useState<string | null>(null)
  const ids = useMemo(() => {
    const base = order.slice(0, STRIP_MAX)
    return [...base, ...matched.filter((id) => byId[id] && !base.includes(id))].slice(0, STRIP_MAX + 4)
  }, [order, matched, byId])
  const total = Math.max(order.length, scanned.length)
  const seen = Math.min(scanned.length, total)
  const title = hovered ? (byId[hovered]?.title ?? COPY.askScanCaption) : COPY.askScanCaption
  return (
    <div>
      <div {...stylex.props(styles.strip)}>
        {ids.map((id, i) => {
          const item = byId[id]
          const lit = matched.includes(id)
          const hover = hovered === id
          return (
            <button
              key={id}
              type="button"
              onClick={() => onOpen(id)}
              onMouseEnter={() => setHovered(id)}
              onMouseLeave={() => setHovered((h) => (h === id ? null : h))}
              aria-label={item?.title ?? 'An item'}
              {...stylex.props(
                styles.tile,
                scanned.includes(id) && styles.tileSeen,
                running && !lit && !hover && styles.tileWave,
                running && !lit && !hover && styles.tileDelay(Math.round((i / ids.length) * WAVE_MS)),
                lit && styles.tileLit,
                hover && styles.tileHover
              )}
            >
              <Thumb
                src={item?.thumbnailUrl ?? item?.faviconUrl ?? null}
                fill={item?.dominantColor}
                fit={item?.thumbnailUrl ? 'cover' : 'contain'}
              />
            </button>
          )
        })}
      </div>
      <div {...stylex.props(styles.track)}>
        <div {...stylex.props(styles.fill(total > 0 ? Math.max(3, Math.round((seen / total) * 100)) : 3))} />
      </div>
      <div {...stylex.props(styles.caption)}>
        <span {...stylex.props(styles.captionText, shared.ellipsis)}>{title}</span>
        <Scritto {...stylex.props(styles.counter)} value={`${seen} / ${total}`} trend={1} />
      </div>
    </div>
  )
}

interface MatchCardProps {
  itemId: string
  /** Raw FTS snippet for the asked question (with `[[match]]` markers), when the query found this item. */
  snippet: string | undefined
  why: string
  /** Title only: a citation in a long list, where the quotes would bury the answer. */
  quiet: boolean
  delayMs: number
  onOpen: (id: string) => void
}

/** One thing the run opened: its thumbnail, its title, and the line the answer came from. */
function MatchCard({ itemId, snippet, why, quiet, delayMs, onOpen }: MatchCardProps): React.JSX.Element {
  const item = useLibrary((s) => s.byId[itemId])
  const spans = useMemo(() => {
    if (snippet?.trim()) return snippetSpans(snippet.trim())
    const fallback = why.trim() || item?.understanding?.trim() || item?.excerpt?.trim() || ''
    return fallback ? [{ text: fallback.replace(/\s+/g, ' '), hot: false }] : []
  }, [snippet, why, item?.understanding, item?.excerpt])
  const quote = useMemo(() => spans.map((s) => s.text).join(''), [spans])
  const where =
    item && item.type === 'pdf' && item.pageCount ? count(item.pageCount, 'page') : item ? typeLabel(item) : ''
  return (
    <button
      type="button"
      onClick={() => onOpen(itemId)}
      {...stylex.props(styles.match, quiet && styles.matchQuiet, styles.matchDelay(delayMs))}
    >
      <span {...stylex.props(styles.matchThumb, quiet && styles.matchThumbQuiet)}>
        <Thumb src={item?.thumbnailUrl ?? null} fill={item?.dominantColor} />
      </span>
      <span {...stylex.props(styles.matchBody)}>
        <span {...stylex.props(styles.matchHead)}>
          <span {...stylex.props(styles.matchTitle, shared.ellipsis)}>{item?.title ?? 'An item'}</span>
          {where ? <span {...stylex.props(styles.matchWhere)}>{where}</span> : null}
        </span>
        {quote && !quiet ? (
          <span {...stylex.props(styles.quote)}>
            <Spans spans={spans} hot="mark" />
          </span>
        ) : null}
      </span>
    </button>
  )
}

function AnswerText({ answer }: { answer: string }): React.JSX.Element {
  const spans = useMemo(() => factSpans(answer), [answer])
  return (
    <p {...stylex.props(styles.answer, shared.selectable)}>
      <Spans spans={spans} hot="fact" />
    </p>
  )
}

export interface AskRunProps {
  run: RunState | undefined
  question: string
  /** FTS snippets for the asked question by item id, so a match can quote the line that matched. */
  snippets: Map<string, string>
  onOpenItem: (id: string) => void
  onRetry: (() => void) | null
  onBack: () => void
  /** Null when follow-ups are not supported (template/action runs, or no prior answer). */
  onFollowUp: ((text: string) => void) | null
}

/**
 * The Ask run: the question, one live status line, the library being swept, the matches it opened
 * with the lines they matched on, and the answer typing in under them.
 */
export function AskRun({
  run,
  question,
  snippets,
  onOpenItem,
  onRetry,
  onBack,
  onFollowUp
}: AskRunProps): React.JSX.Element {
  const [followUp, setFollowUp] = useState('')
  const [saving, setSaving] = useState(false)
  const push = useToasts((s) => s.push)
  const byId = useLibrary((s) => s.byId)
  const openDetail = useUi((s) => s.openDetail)
  const closePalette = useUi((s) => s.closePalette)

  const running = run?.status === 'running'
  const answer = run?.result && run.result.task === 'command' ? run.result : null
  const steps = run?.steps ?? []
  const phase = askPhase(run ? { status: run.status, steps, answered: Boolean(answer) } : undefined)
  const scanned = useMemo(() => askScanned(steps), [steps])
  const matched = useMemo(() => askMatched(steps), [steps])
  const cards: AgentSource[] =
    answer && answer.sources.length > 0
      ? answer.sources
      : matched.slice(0, MAX_CARDS).map((itemId) => ({ itemId, role: 'supporting', why: '' }))
  const live = useElapsed(run?.startedAt ?? null, Boolean(running))
  const elapsed = run && !running && run.endedAt ? run.endedAt - run.startedAt : live
  const evidence = run ? evidenceHeader(steps, answer?.cues) : ''

  const stop = async (): Promise<void> => {
    if (run && (await confirmStop())) void invoke('agent:cancel', { runId: run.runId })
  }

  const submitFollowUp = (): void => {
    const text = followUp.trim()
    if (!text || !onFollowUp) return
    setFollowUp('')
    onFollowUp(text)
  }

  const saveAsNote = async (): Promise<void> => {
    if (!answer?.answer) return
    setSaving(true)
    const sources = answer.sources.map((s) => ({ title: byId[s.itemId]?.title ?? 'An item' }))
    const r = await invoke('capture:text', {
      text: noteBodyFor(question, answer.answer, sources),
      title: noteTitleFor(question)
    })
    setSaving(false)
    if (!r.ok) {
      push({ text: describeError(r.error) })
      return
    }
    const id = r.data.items[0]?.id
    push({
      text: 'Saved as a note.',
      action: id
        ? {
            label: 'Show',
            run: () => {
              closePalette()
              openDetail(id, id)
            }
          }
        : undefined
    })
  }

  return (
    <>
      <button type="button" {...stylex.props(styles.head)} onClick={onBack} title="Back to search">
        <Search size={16} strokeWidth={1.5} />
        <span {...stylex.props(styles.question, shared.ellipsis)}>{question}</span>
        <Kbd>esc</Kbd>
      </button>

      <div {...stylex.props(styles.status)} role="status" aria-live="polite">
        <Dot tone={phase === 'answered' ? 'ok' : phase === 'failed' ? 'failed' : 'processing'} />
        <span {...stylex.props(shared.ellipsis)}>
          {phase === 'failed' && run?.status === 'failed'
            ? run.error
              ? describeError(run.error)
              : 'That did not work.'
            : askStatus(phase, answer ? answer.sources.length : matched.length)}
        </span>
        <Scritto {...stylex.props(styles.time)} value={formatElapsed(elapsed)} trend={1} />
      </div>

      <div {...stylex.props(styles.body)}>
        {phase === 'scanning' ? (
          <ScanStrip scanned={scanned} matched={matched} running={Boolean(running) || !run} onOpen={onOpenItem} />
        ) : null}

        {cards.length > 0 && phase !== 'scanning' ? (
          <div {...stylex.props(styles.matches)}>
            {cards.map((source, i) => (
              <MatchCard
                key={source.itemId}
                itemId={source.itemId}
                snippet={snippets.get(source.itemId)}
                why={source.why}
                // Once the answer is in, only the sources it leans on keep their quote: the rest are
                // citations, and four quotes would push the answer off the bottom of the dialog.
                quiet={phase === 'answered' && cards.length > 2 && source.role !== 'primary'}
                // Small on purpose: a card holds its slot while it waits, so a long stagger is a hole.
                delayMs={i * 45}
                onOpen={onOpenItem}
              />
            ))}
          </div>
        ) : null}

        {cards.length > 0 && phase !== 'scanning' && (answer || phase === 'reading') ? (
          <>
            <div {...stylex.props(styles.divider)} />
            <span {...stylex.props(shared.eyebrow)}>{answer?.kind === 'note' ? 'Note' : 'Answer'}</span>
          </>
        ) : null}

        {phase === 'reading' ? (
          <div {...stylex.props(styles.skeleton)} aria-hidden="true">
            <div {...stylex.props(styles.bar(74, 0))} />
            <div {...stylex.props(styles.bar(48, 220))} />
          </div>
        ) : null}

        {answer?.kind === 'note' && answer.noteId ? (
          <button
            type="button"
            {...stylex.props(styles.noteCard)}
            onClick={() => answer.noteId && onOpenItem(answer.noteId)}
          >
            <span {...stylex.props(styles.noteTitle, shared.ellipsis)}>{byId[answer.noteId]?.title ?? 'New note'}</span>
            <span {...stylex.props(styles.noteOpen)}>Open</span>
          </button>
        ) : answer ? (
          <AnswerText answer={answer.answer ?? COPY.askNothing} />
        ) : null}

        {answer && evidence ? <p {...stylex.props(styles.evidence)}>{evidence}</p> : null}

        {run?.status === 'cancelled' ? <p {...stylex.props(styles.error)}>Stopped.</p> : null}

        {run && answer ? (
          <ProposalList
            runId={run.runId}
            proposals={answer.proposals ?? []}
            appliedCount={answer.appliedCount ?? 0}
            undoable={run.undoable}
          />
        ) : null}
      </div>

      {onFollowUp ? (
        <div {...stylex.props(styles.followUp)}>
          <input
            type="text"
            {...stylex.props(styles.followUpInput)}
            value={followUp}
            onChange={(e) => setFollowUp(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault()
                submitFollowUp()
              }
            }}
            placeholder="Ask a follow-up…"
            aria-label="Ask a follow-up"
          />
          <Kbd>↩</Kbd>
        </div>
      ) : null}

      <div {...stylex.props(styles.footer)}>
        <Button small variant="quiet" onClick={onBack} aria-label="Back to search">
          <ArrowLeft size={14} strokeWidth={1.5} />
          Back
        </Button>
        <span {...stylex.props(styles.footerSpacer)} />
        {running && run ? (
          <Button small variant="quiet" onClick={() => void stop()}>
            Cancel
          </Button>
        ) : (
          <>
            {answer ? <span {...stylex.props(styles.provenance, shared.ellipsis)}>{COPY.askAnswered}</span> : null}
            {onRetry ? (
              <Button small variant="quiet" onClick={onRetry}>
                Retry
              </Button>
            ) : null}
            {answer?.kind === 'answer' && answer.answer ? (
              <Button small onClick={() => void saveAsNote()} disabled={saving}>
                {saving ? 'Saving…' : 'Save as note'}
              </Button>
            ) : null}
          </>
        )}
      </div>
    </>
  )
}
