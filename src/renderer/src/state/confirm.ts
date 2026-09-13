import { create } from 'zustand'

export interface ConfirmRequest {
  title: string
  body?: string
  /** Defaults to "Confirm". */
  confirmLabel?: string
  /** Defaults to "Cancel". */
  cancelLabel?: string
  /** Red confirm button for actions that throw work away. */
  danger?: boolean
}

interface ConfirmState {
  pending: ConfirmRequest | null
  resolve: ((ok: boolean) => void) | null
  ask: (req: ConfirmRequest) => Promise<boolean>
  settle: (ok: boolean) => void
}

export const useConfirm = create<ConfirmState>((set, get) => ({
  pending: null,
  resolve: null,
  ask(req) {
    // A second ask while one is open answers the first with "no" rather than stacking dialogs.
    get().resolve?.(false)
    return new Promise<boolean>((resolve) => set({ pending: req, resolve }))
  },
  settle(ok) {
    const { resolve } = get()
    set({ pending: null, resolve: null })
    resolve?.(ok)
  }
}))

/** Ask before interrupting or discarding anything in progress. Resolves false on Escape or scrim click. */
export function confirm(req: ConfirmRequest): Promise<boolean> {
  return useConfirm.getState().ask(req)
}
