import * as stylex from '@stylexjs/stylex'
import { Command } from 'cmdk'
import { ClipboardCopy, CornerDownLeft, Layers, Plus, Search, Settings, Sprout, SquareStack } from 'lucide-react'
import { type ReactNode, useEffect, useMemo, useRef, useState } from 'react'
import { useShallow } from 'zustand/react/shallow'
import { COPY } from '../../../../../shared/constants'
import type { AgentCommandRequest } from '../../../../../shared/ipc'
import type { SearchHit } from '../../../../../shared/types'
import {
  buildAskAboutSelection,
  buildFollowUp,
  buildSelectionCommand,
  commandsFor,
  type PriorTurn
} from '../../../lib/commands'
import { librarySnapshotSource, seedDevLibrary } from '../../../lib/dev-seed'
import { count } from '../../../lib/format'
import { describeError, invoke } from '../../../lib/ipc-client'
import { addToCollection } from '../../../lib/library-actions'
import { groupHits, hitSnippet } from '../../../lib/palette'
import { useCollections } from '../../../state/collections'
import { useLibrary } from '../../../state/library'
import { useRuns } from '../../../state/runs'
import { useToasts } from '../../../state/toasts'
import { useUi } from '../../../state/ui'
import { shared } from '../../../styles/shared'
import { Kbd, Thumb } from '../../common'
import { AskRun } from '../ask-run'
import { styles } from './styles'

function Heading({ children }: { children: ReactNode }): React.JSX.Element {
  return <span {...stylex.props(styles.heading)}>{children}</span>
}

/**
 * CommandPalette (⌘K): instant local hits grouped by type, an "Ask" row for natural language,
 * multi-item commands over the current selection, and the run view (steps -> answer with sources).
 */
export function CommandPalette(): React.JSX.Element {
  const closePalette = useUi((s) => s.closePalette)
  const openDetail = useUi((s) => s.openDetail)
  const openSettings = useUi((s) => s.openSettings)
  const pushModal = useUi((s) => s.push)
  const initialQuery = useUi((s) => s.paletteQuery)
  const initialRunId = useUi((s) => s.paletteRunId)
  const recent = useLibrary(
    useShallow((s) =>
      s.order
        .slice(0, 5)
        .map((id) => s.byId[id])
        .filter((i): i is NonNullable<typeof i> => i !== undefined)
    )
  )
  const selection = useLibrary((s) => s.selection)
  const collections = useCollections((s) => s.list)
  const push = useToasts((s) => s.push)
  const [query, setQuery] = useState(initialRunId ? '' : initialQuery)
  const [question, setQuestion] = useState(initialRunId ? initialQuery : '')
  const [active, setActive] = useState('')
  const [hits, setHits] = useState<SearchHit[]>([])
  const [searching, setSearching] = useState(false)
  const [runId, setRunId] = useState<string | null>(initialRunId)
  const [lastRequest, setLastRequest] = useState<AgentCommandRequest | null>(null)
  const [mode, setMode] = useState<'search' | 'addToCollection'>('search')
  const [askError, setAskError] = useState<string | null>(null)
  const [snippets, setSnippets] = useState<Map<string, string>>(new Map())
  const [busy, setBusy] = useState<'' | 'seed' | 'snapshot'>('')
  const [confirmCancel, setConfirmCancel] = useState(false)
  const run = useRuns((s) => (runId ? s.runs[runId] : undefined))
  const inputRef = useRef<HTMLInputElement>(null)
  const seq = useRef(0)
  const openedIntoRun = useRef(Boolean(initialRunId))
  const selected = useMemo(() => [...selection], [selection])

  useEffect(() => {
    if (!runId) inputRef.current?.focus()
  }, [runId, mode])

  useEffect(() => {
    const q = query.trim()
    if (!q || mode !== 'search') {
      setHits([])
      setSearching(false)
      return
    }
    const mine = ++seq.current
    setSearching(true)
    const t = setTimeout(() => {
      void invoke('search:quick', { query: q, limit: 8 }).then((r) => {
        if (mine !== seq.current) return
        setHits(r.ok ? r.data : [])
        setSearching(false)
      })
    }, 50)
    return () => clearTimeout(t)
  }, [query, mode])

  const groups = useMemo(() => groupHits(hits), [hits])
  const trimmed = query.trim()
  // Follow-ups only after a free-form Ask that produced an answer; `run` belongs to `lastRequest`
  // because `start` sets both, so the pair is always consistent.
  const priorTurn: PriorTurn | null =
    lastRequest &&
    !lastRequest.itemIds &&
    !lastRequest.template &&
    run?.status === 'succeeded' &&
    run.result?.task === 'command' &&
    run.result.kind === 'answer' &&
    run.result.answer
      ? { question: lastRequest.question, answer: run.result.answer }
      : null

  const start = async (request: AgentCommandRequest): Promise<void> => {
    setAskError(null)
    setConfirmCancel(false)
    setLastRequest(request)
    setQuestion(request.question)
    // The same local FTS the list above runs, kept for the run view: it gives every match the line
    // of its own text that the question matched on.
    void invoke('search:quick', { query: request.question, limit: 12 }).then((r) => {
      const found = new Map<string, string>()
      if (r.ok) for (const hit of r.data) if (hit.snippet) found.set(hit.id, hit.snippet)
      setSnippets(found)
    })
    const result = await invoke('agent:command', request)
    if (result.ok) setRunId(result.data.runId)
    else setAskError(describeError(result.error))
  }

  const ask = (): void => {
    if (!trimmed) return
    void start(selected.length > 0 ? buildAskAboutSelection(trimmed, selected) : { question: trimmed })
  }

  const open = (id: string): void => {
    closePalette()
    openDetail(id, id)
  }

  // Leaving a live run throws away work that is already paid for, so the first press only arms the
  // confirm in the footer and the second one is the one that stops it.
  const back = (): void => {
    if (run?.status === 'running' && !confirmCancel) {
      setConfirmCancel(true)
      return
    }
    setConfirmCancel(false)
    if (run && run.status === 'running') void invoke('agent:cancel', { runId: run.runId })
    if (openedIntoRun.current) {
      closePalette()
      return
    }
    setRunId(null)
  }

  const onKeyDown = (e: React.KeyboardEvent): void => {
    if (e.key === 'Enter' && !runId && mode === 'search' && trimmed) {
      // ⌘↩ always asks. Plain ↩ only when the settled search left nothing to open, so a hit is
      // never traded for a paid run while results are still in flight.
      const nothingToOpen = !searching && hits.length === 0 && selected.length === 0
      if (e.metaKey || nothingToOpen) {
        e.preventDefault()
        e.stopPropagation()
        ask()
        return
      }
    }
    if (e.key !== 'Escape') return
    e.stopPropagation()
    if (runId) {
      back()
      return
    }
    if (mode === 'addToCollection') {
      setMode('search')
      setQuery('')
      return
    }
    closePalette()
  }

  const addSelectedTo = async (collectionId: string): Promise<void> => {
    const ok = await addToCollection(collectionId, selected)
    if (ok) closePalette()
  }

  const seed = async (): Promise<void> => {
    setBusy('seed')
    try {
      const n = await seedDevLibrary()
      closePalette()
      push({ text: n > 0 ? `Seeded ${count(n, 'item')}.` : 'Nothing seeded.' })
    } catch (e) {
      push({ text: `Seed failed: ${String(e)}` })
    }
    setBusy('')
  }

  const copySnapshot = async (): Promise<void> => {
    setBusy('snapshot')
    try {
      const source = await librarySnapshotSource()
      try {
        await navigator.clipboard.writeText(source)
        push({ text: 'Snapshot copied. Run: pbpaste > src/renderer/src/lib/dev-seed.data.json' })
      } catch {
        // Chromium wants user activation for a clipboard write, and the IPC round-trips above
        // outlive the keypress that started this. Fall back to a download.
        const a = document.createElement('a')
        a.href = URL.createObjectURL(new Blob([source], { type: 'text/plain' }))
        a.download = 'dev-seed.data.json'
        a.click()
        push({ text: 'Snapshot saved to ~/Downloads/dev-seed.data.json' })
      }
      closePalette()
    } catch (e) {
      push({ text: `Snapshot failed: ${String(e)}` })
    }
    setBusy('')
  }

  const createAndAdd = async (): Promise<void> => {
    const r = await useCollections.getState().create(trimmed)
    if (!r.ok) {
      push({ text: describeError(r.error) })
      return
    }
    await addSelectedTo(r.data.id)
  }

  const itemProps = (value: string): ReturnType<typeof stylex.props> =>
    stylex.props(styles.item, active === value && styles.itemActive)
  const filteredCollections =
    mode === 'addToCollection'
      ? collections.filter((c) => !trimmed || c.name.toLowerCase().includes(trimmed.toLowerCase()))
      : []
  const commands = commandsFor(selected.length)

  return (
    <div
      {...stylex.props(styles.scrim)}
      role="presentation"
      onMouseDown={(e) => e.target === e.currentTarget && closePalette()}
    >
      <Command
        {...stylex.props(styles.dialog)}
        label="Search anything"
        shouldFilter={false}
        onKeyDown={onKeyDown}
        loop
        value={active}
        onValueChange={setActive}
      >
        {runId ? (
          <AskRun
            run={run}
            question={question}
            snippets={snippets}
            onOpenItem={open}
            onRetry={lastRequest ? () => void start(lastRequest) : null}
            onBack={back}
            confirmingCancel={confirmCancel}
            onKeepGoing={() => setConfirmCancel(false)}
            onFollowUp={priorTurn ? (text) => void start(buildFollowUp(text, priorTurn)) : null}
          />
        ) : (
          <>
            <div {...stylex.props(styles.inputRow)}>
              {mode === 'addToCollection' ? (
                <span {...stylex.props(styles.modeChip)}>
                  <Layers size={12} strokeWidth={1.5} />
                  Add {count(selected.length, 'item')} to
                </span>
              ) : (
                <Search size={16} strokeWidth={1.5} />
              )}
              <Command.Input
                ref={inputRef}
                {...stylex.props(styles.input)}
                value={query}
                onValueChange={setQuery}
                placeholder={mode === 'addToCollection' ? 'Find or create a collection…' : 'Search anything, or ask…'}
              />
              {mode === 'search' && !trimmed ? <Kbd>esc</Kbd> : null}
            </div>
            {mode === 'search' && trimmed ? (
              <button type="button" {...stylex.props(styles.askBar)} onClick={ask}>
                <span {...stylex.props(styles.iconCell)}>
                  <CornerDownLeft size={16} strokeWidth={1.5} />
                </span>
                <span {...stylex.props(shared.ellipsis)}>
                  {selected.length > 0
                    ? `Ask about the ${count(selected.length, 'selected item')}: ${trimmed}`
                    : `Ask: ${trimmed}`}
                </span>
                <Kbd>⌘↩</Kbd>
              </button>
            ) : null}
            <Command.List {...stylex.props(styles.list)}>
              {askError ? <p {...stylex.props(styles.empty)}>{askError}</p> : null}

              {mode === 'addToCollection' ? (
                <Command.Group heading={<Heading>Collections</Heading>}>
                  {filteredCollections.map((c) => (
                    <Command.Item
                      key={c.id}
                      value={`col-${c.id}`}
                      {...itemProps(`col-${c.id}`)}
                      onSelect={() => void addSelectedTo(c.id)}
                    >
                      <span {...stylex.props(styles.iconCell)}>
                        <Layers size={14} strokeWidth={1.5} />
                      </span>
                      <span {...stylex.props(styles.text)}>
                        <span {...stylex.props(shared.ellipsis)}>{c.name}</span>
                        {c.description ? (
                          <span {...stylex.props(styles.sub, shared.ellipsis)}>{c.description}</span>
                        ) : null}
                      </span>
                      <span {...stylex.props(styles.meta)}>{count(c.count, 'item')}</span>
                    </Command.Item>
                  ))}
                  {trimmed && !collections.some((c) => c.name.toLowerCase() === trimmed.toLowerCase()) ? (
                    <Command.Item value="col-new" {...itemProps('col-new')} onSelect={() => void createAndAdd()}>
                      <span {...stylex.props(styles.iconCell)}>
                        <Plus size={14} strokeWidth={1.5} />
                      </span>
                      <span {...stylex.props(shared.ellipsis)}>Create “{trimmed}”</span>
                      <span {...stylex.props(styles.meta)}>New collection</span>
                    </Command.Item>
                  ) : null}
                  {filteredCollections.length === 0 && !trimmed ? (
                    <p {...stylex.props(styles.empty)}>No collections yet. Type a name to create one.</p>
                  ) : null}
                </Command.Group>
              ) : trimmed.length === 0 ? (
                <>
                  {selected.length > 0 ? (
                    <Command.Group heading={<Heading>{count(selected.length, 'item')} selected</Heading>}>
                      {commands.map((c) => (
                        <Command.Item
                          key={c.template}
                          value={`sel-${c.template}`}
                          {...itemProps(`sel-${c.template}`)}
                          onSelect={() => void start(buildSelectionCommand(c.template, selected))}
                        >
                          <span {...stylex.props(styles.iconCell)}>
                            <SquareStack size={14} strokeWidth={1.5} />
                          </span>
                          <span {...stylex.props(shared.ellipsis)}>{c.label} selected</span>
                          <span {...stylex.props(styles.meta)}>{c.producesNote ? 'Makes a note' : 'Answer'}</span>
                        </Command.Item>
                      ))}
                      <Command.Item
                        value="sel-add"
                        {...itemProps('sel-add')}
                        onSelect={() => setMode('addToCollection')}
                      >
                        <span {...stylex.props(styles.iconCell)}>
                          <Layers size={14} strokeWidth={1.5} />
                        </span>
                        <span {...stylex.props(shared.ellipsis)}>Add to collection…</span>
                      </Command.Item>
                    </Command.Group>
                  ) : null}
                  {recent.length > 0 ? (
                    <Command.Group heading={<Heading>Recent</Heading>}>
                      {recent.map((i) => (
                        <Command.Item
                          key={i.id}
                          value={`recent-${i.id}`}
                          {...itemProps(`recent-${i.id}`)}
                          onSelect={() => open(i.id)}
                        >
                          <span {...stylex.props(styles.thumb)}>
                            <Thumb src={i.thumbnailUrl} fill={i.dominantColor} />
                          </span>
                          <span {...stylex.props(styles.text)}>
                            <span {...stylex.props(shared.ellipsis)}>{i.title}</span>
                            {i.understanding ? (
                              <span {...stylex.props(styles.sub, shared.ellipsis)}>{i.understanding}</span>
                            ) : null}
                          </span>
                        </Command.Item>
                      ))}
                    </Command.Group>
                  ) : null}
                  <Command.Group heading={<Heading>Try asking</Heading>}>
                    {[
                      'What am I researching here?',
                      'What did I save this week?',
                      'Find that mac app I saved recently'
                    ].map((q) => (
                      <Command.Item
                        key={q}
                        value={`suggest-${q}`}
                        {...itemProps(`suggest-${q}`)}
                        onSelect={() => setQuery(q)}
                      >
                        <span {...stylex.props(styles.iconCell)}>
                          <CornerDownLeft size={14} strokeWidth={1.5} />
                        </span>
                        <span {...stylex.props(shared.ellipsis)}>{q}</span>
                      </Command.Item>
                    ))}
                    <Command.Item
                      value="suggest-settings"
                      {...itemProps('suggest-settings')}
                      onSelect={() => {
                        closePalette()
                        openSettings()
                      }}
                    >
                      <span {...stylex.props(styles.iconCell)}>
                        <Settings size={14} strokeWidth={1.5} />
                      </span>
                      <span {...stylex.props(shared.ellipsis)}>Settings</span>
                      <span {...stylex.props(styles.meta)}>⌘,</span>
                    </Command.Item>
                  </Command.Group>
                  {import.meta.env.DEV ? (
                    <Command.Group heading={<Heading>Dev</Heading>}>
                      <Command.Item value="dev-seed" {...itemProps('dev-seed')} onSelect={() => void seed()}>
                        <span {...stylex.props(styles.iconCell)}>
                          <Sprout size={14} strokeWidth={1.5} />
                        </span>
                        <span {...stylex.props(shared.ellipsis)}>Seed sample data</span>
                        <span {...stylex.props(styles.meta)}>
                          {busy === 'seed' ? 'Keeping…' : 'Notes, images, links'}
                        </span>
                      </Command.Item>
                      <Command.Item
                        value="dev-snapshot"
                        {...itemProps('dev-snapshot')}
                        onSelect={() => void copySnapshot()}
                      >
                        <span {...stylex.props(styles.iconCell)}>
                          <ClipboardCopy size={14} strokeWidth={1.5} />
                        </span>
                        <span {...stylex.props(shared.ellipsis)}>Copy library snapshot</span>
                        <span {...stylex.props(styles.meta)}>
                          {busy === 'snapshot' ? 'Reading…' : 'Records the AI output for reseeding'}
                        </span>
                      </Command.Item>
                    </Command.Group>
                  ) : null}
                </>
              ) : (
                <>
                  {groups.map((g) => (
                    <Command.Group key={g.id} heading={<Heading>{g.label}</Heading>}>
                      {g.hits.map((h) => (
                        <Command.Item
                          key={h.id}
                          value={`hit-${h.id}`}
                          {...itemProps(`hit-${h.id}`)}
                          onSelect={() => open(h.id)}
                        >
                          <span {...stylex.props(styles.thumb)}>
                            <Thumb src={h.thumbnailUrl ?? null} />
                          </span>
                          <span {...stylex.props(styles.text)}>
                            <span {...stylex.props(shared.ellipsis)}>{h.title}</span>
                            <span {...stylex.props(styles.sub, shared.ellipsis)}>{hitSnippet(h)}</span>
                          </span>
                          <span {...stylex.props(styles.meta)}>{h.capturedAgo}</span>
                        </Command.Item>
                      ))}
                    </Command.Group>
                  ))}
                  {hits.length === 0 ? <p {...stylex.props(styles.empty)}>{COPY.noMatches(trimmed)}</p> : null}
                </>
              )}
            </Command.List>
            {mode === 'search' ? (
              <div {...stylex.props(styles.footer)}>
                <span>
                  <Kbd>↑↓</Kbd> move · <Kbd>↩</Kbd> open
                </span>
                <span {...stylex.props(styles.footerSpacer)} />
                <button
                  type="button"
                  {...stylex.props(styles.meta)}
                  onClick={() => {
                    closePalette()
                    pushModal({ kind: 'dialog', id: 'newCollection' })
                  }}
                >
                  New collection
                </button>
              </div>
            ) : null}
          </>
        )}
      </Command>
    </div>
  )
}
