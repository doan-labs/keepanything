import {
  AI_PROVIDER_DEFAULTS,
  AI_PROVIDER_LABEL,
  COPY,
  DEFAULT_BASE_URL,
  DEFAULT_MODEL,
  EMBEDDING_DIMS,
  EMBEDDING_MODEL_ID,
  INTERNAL_DND_MIME,
  MEDIA_SCHEME,
  SKIP_DIR_NAMES,
  SNIPPET_CLOSE,
  SNIPPET_OPEN,
  TEMP_PATH_MARKERS
} from '../../../src/shared/constants'
import { IPC_CHANNEL_LIST, IPC_CHANNELS, IPC_EVENT_LIST, IPC_EVENTS } from '../../../src/shared/ipc'
import {
  isSymmetric,
  KIND_LABEL,
  KINDS,
  RELATIONSHIP_TYPE_IDS,
  RELATIONSHIP_TYPES,
  relationshipLabel
} from '../../../src/shared/kinds'
import { LAYOUT, railAnchorX, SHELF, SHELF_EXIT_MS, SHELF_WINDOW } from '../../../src/shared/layout'
import { MEDIA_ROOTS } from '../../../src/shared/media'
import {
  isFailed,
  isTerminal,
  PROCESSING_STATUSES,
  STAGE_LABEL,
  STATUS_LABEL,
  STICKY_STATUSES,
  USER_STAGES,
  userStageFor
} from '../../../src/shared/status'
import { writeJson } from '../lib'

/** Function-valued COPY entries, sampled on fixed inputs so the vocabulary stays data. */
const copySamples = {
  foundRelated: [COPY.foundRelated(1), COPY.foundRelated(4)],
  alreadyKept: [COPY.alreadyKept('3 days ago')],
  noMatches: [COPY.noMatches('invoice')],
  askReading: [COPY.askReading(1), COPY.askReading(5)],
  askFound: [COPY.askFound(1), COPY.askFound(5)]
}
const copyConstants = Object.fromEntries(Object.entries(COPY).filter(([, v]) => typeof v !== 'function'))

export function exportVocab(): void {
  writeJson('vocab.json', {
    KINDS,
    KIND_LABEL,
    RELATIONSHIP_TYPES,
    RELATIONSHIP_TYPE_IDS,
    symmetric: Object.fromEntries(RELATIONSHIP_TYPE_IDS.map((t) => [t, isSymmetric(t)])),
    relationshipLabel: Object.fromEntries(
      RELATIONSHIP_TYPE_IDS.map((t) => [t, { out: relationshipLabel(t, 'out'), in: relationshipLabel(t, 'in') }])
    ),
    PROCESSING_STATUSES,
    STATUS_LABEL,
    STAGE_LABEL,
    USER_STAGES,
    userStageFor: Object.fromEntries(PROCESSING_STATUSES.map((s) => [s, userStageFor(s) ? userStageFor(s)?.id : null])),
    STICKY_STATUSES,
    isFailed: Object.fromEntries(PROCESSING_STATUSES.map((s) => [s, isFailed(s)])),
    isTerminal: Object.fromEntries(PROCESSING_STATUSES.map((s) => [s, isTerminal(s)])),
    COPY: { ...copyConstants, samples: copySamples },
    SKIP_DIR_NAMES,
    TEMP_PATH_MARKERS,
    DEFAULT_MODEL,
    DEFAULT_BASE_URL,
    AI_PROVIDER_DEFAULTS,
    AI_PROVIDER_LABEL,
    SNIPPET_OPEN,
    SNIPPET_CLOSE,
    EMBEDDING_MODEL_ID,
    EMBEDDING_DIMS,
    MEDIA_SCHEME,
    MEDIA_ROOTS,
    INTERNAL_DND_MIME,
    LAYOUT,
    SHELF,
    SHELF_WINDOW,
    SHELF_EXIT_MS,
    railAnchorX: railAnchorX(),
    IPC_CHANNELS,
    IPC_CHANNEL_LIST,
    IPC_EVENTS,
    IPC_EVENT_LIST
  })
}
