import {
  next,
  PROCESSING_STATUSES,
  type ProcessingStatus,
  STAGE_LABEL,
  stageEntryStatus
} from '../../../src/shared/status'
import type { Stage } from '../../../src/shared/types'
import { writeJson } from '../lib'

const STAGES = Object.keys(STAGE_LABEL) as Stage[]
const OUTCOMES = ['ok', 'partial', 'failed'] as const

export function exportStatusTable(): void {
  const transitions: unknown[] = []
  for (const status of PROCESSING_STATUSES) {
    for (const stage of STAGES) {
      for (const outcome of OUTCOMES) {
        for (const isLast of [false, true]) {
          transitions.push({
            status,
            stage,
            outcome,
            isLast,
            next: next(status, stage, outcome, isLast ? { isLast: true } : {})
          })
        }
      }
    }
  }
  const entry: unknown[] = []
  for (const stage of STAGES) {
    for (const current of [undefined, ...PROCESSING_STATUSES] as (ProcessingStatus | undefined)[]) {
      entry.push({ stage, current: current ?? null, status: stageEntryStatus(stage, current) })
    }
  }
  writeJson('status-table.json', { transitions, stageEntryStatus: entry })
}
