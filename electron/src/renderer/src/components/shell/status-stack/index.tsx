import * as stylex from '@stylexjs/stylex'
import { useEffect, useRef } from 'react'
import { useShallow } from 'zustand/react/shallow'
import { runOutcome } from '../../../lib/activity'
import { undoRun } from '../../../lib/agent-actions'
import { count } from '../../../lib/format'
import { describeError } from '../../../lib/ipc-client'
import { askMatched, askPhase, askStatus } from '../../../lib/palette'
import { useLibrary } from '../../../state/library'
import { selectActiveRuns, useRuns } from '../../../state/runs'
import { useToasts } from '../../../state/toasts'
import { useUi } from '../../../state/ui'
import { shared } from '../../../styles/shared'
import { Dot, ToastStack } from '../../common'
import { styles } from './styles'

/**
 * Announces finished background runs (organize / understand) as toasts, once each: the final
 * line comes only from real results ("Linked to 4 things · Added to 1 collection.").
 */
function useRunAnnouncements(): void {
  const runs = useRuns((s) => s.runs)
  const announced = useRef<Set<string>>(new Set())
  const push = useToasts((s) => s.push)
  const openRun = useUi((s) => s.openRun)
  const paletteOpen = useUi((s) => s.modalStack.some((m) => m.kind === 'palette'))
  useEffect(() => {
    for (const run of Object.values(runs)) {
      if (run.status === 'running' || announced.current.has(run.runId)) continue
      announced.current.add(run.runId)
      if (run.status === 'cancelled') continue
      if (run.task === 'command') {
        if (paletteOpen) continue
        if (run.status === 'failed')
          push({
            text: run.error ? describeError(run.error) : "That didn't work.",
            action: { label: 'Show', run: () => openRun(run.runId) }
          })
        else if (run.result?.task === 'command' && run.result.kind === 'note' && run.result.noteId) {
          const noteId = run.result.noteId
          push({
            text: 'Wrote a note from your selection.',
            action: {
              label: 'Show',
              run: () => useUi.getState().openDetail(noteId, noteId)
            }
          })
        } else if (run.result?.task === 'command' && (run.result.appliedCount ?? 0) > 0 && run.undoable) {
          // Item actions that applied their own changes: Undo reverts the whole run.
          push({
            text: 'Answer ready.',
            detail: `Applied ${count(run.result.appliedCount ?? 0, 'change')}.`,
            action: { label: 'Undo', run: () => undoRun(run.runId) },
            secondary: { label: 'Show', run: () => openRun(run.runId) }
          })
        } else push({ text: 'Answer ready.', action: { label: 'Show', run: () => openRun(run.runId) } })
        continue
      }
      if (run.task === 'understand') continue
      const line = runOutcome(run)
      if (!line || run.status === 'failed') continue
      const itemId = run.itemId
      const show = itemId
        ? { label: 'Show' as const, run: () => useUi.getState().openDetail(itemId, itemId) }
        : undefined
      push({
        text: line,
        ...(itemId ? { detail: useLibrary.getState().byId[itemId]?.title } : {}),
        // Organize / relate / consolidate runs that wrote something get Undo for the whole run.
        ...(run.undoable
          ? { action: { label: 'Undo' as const, run: () => undoRun(run.runId) }, ...(show ? { secondary: show } : {}) }
          : show
            ? { action: show }
            : {})
      })
    }
  }, [runs, push, openRun, paletteOpen])
}

/**
 * An Ask still running after its palette was closed — opening an item from the run closes it, and the
 * answer would otherwise arrive out of nowhere. Clicking steps back into the run. Only `command`
 * runs: understand / organize work stays quiet in Activity.
 */
function LiveAsk(): React.JSX.Element | null {
  const active = useRuns(useShallow(selectActiveRuns))
  const openRun = useUi((s) => s.openRun)
  const paletteOpen = useUi((s) => s.modalStack.some((m) => m.kind === 'palette'))
  const run = active.filter((r) => r.task === 'command').at(-1)
  if (!run || paletteOpen) return null
  return (
    <button type="button" {...stylex.props(styles.live)} onClick={() => openRun(run.runId)} title="Back to the search">
      <Dot tone="processing" />
      <span {...stylex.props(shared.ellipsis)}>
        {askStatus(askPhase({ status: run.status, steps: run.steps, answered: false }), askMatched(run.steps).length)}
      </span>
    </button>
  )
}

/** Bottom-right: the live Ask, finished-run announcements and action feedback. */
export function StatusStack(): React.JSX.Element {
  useRunAnnouncements()
  return (
    <div {...stylex.props(styles.stack)} aria-live="polite">
      <ToastStack />
      <LiveAsk />
    </div>
  )
}
