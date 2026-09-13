import * as stylex from '@stylexjs/stylex'
import { type KeyboardEvent, useEffect, useRef } from 'react'
import { useConfirm } from '../../../state/confirm'
import { Button } from '../button'
import { Kbd } from '../kbd'
import { styles } from './styles'

/**
 * The one confirm sheet, driven by `confirm()` in `state/confirm`. Mounted once at the app root above
 * the palette; Escape and the scrim answer "no", Enter answers "yes". Focus goes back where it was.
 */
export function ConfirmDialog(): React.JSX.Element | null {
  const pending = useConfirm((s) => s.pending)
  const settle = useConfirm((s) => s.settle)
  const sheet = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!pending) return
    const before = document.activeElement
    sheet.current?.focus()
    return () => {
      if (before instanceof HTMLElement && before.isConnected) before.focus()
    }
  }, [pending])

  if (!pending) return null

  const onKeyDown = (e: KeyboardEvent): void => {
    if (e.key !== 'Escape' && e.key !== 'Enter') return
    e.preventDefault()
    e.stopPropagation()
    settle(e.key === 'Enter')
  }

  return (
    <div
      {...stylex.props(styles.scrim)}
      role="presentation"
      onMouseDown={(e) => e.target === e.currentTarget && settle(false)}
    >
      <div
        ref={sheet}
        tabIndex={-1}
        {...stylex.props(styles.sheet)}
        role="alertdialog"
        aria-modal="true"
        aria-label={pending.title}
        onKeyDown={onKeyDown}
      >
        <h2 {...stylex.props(styles.title)}>{pending.title}</h2>
        {pending.body ? <p {...stylex.props(styles.body)}>{pending.body}</p> : null}
        <div {...stylex.props(styles.row)}>
          <Button variant="quiet" onClick={() => settle(false)}>
            {pending.cancelLabel ?? 'Cancel'} <Kbd>esc</Kbd>
          </Button>
          <Button variant={pending.danger ? 'danger' : 'primary'} onClick={() => settle(true)}>
            {pending.confirmLabel ?? 'Confirm'} <Kbd>↩</Kbd>
          </Button>
        </div>
      </div>
    </div>
  )
}
