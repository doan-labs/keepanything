import {
  AGENT_MAX_TOKENS,
  RUN_PROMPT_TOKEN_CEILING,
  STRUCTURED_FAILURE_MESSAGE,
  STRUCTURED_MAX_TOKENS,
  STRUCTURED_MAX_TOKENS_CAP
} from '../../../src/main/ai/structured'
import { LIMITS } from '../../../src/shared/constants'
import { writeJson } from '../lib'

export function exportLimits(): void {
  writeJson('limits.json', {
    LIMITS,
    STRUCTURED_MAX_TOKENS,
    STRUCTURED_MAX_TOKENS_CAP,
    STRUCTURED_FAILURE_MESSAGE,
    AGENT_MAX_TOKENS,
    RUN_PROMPT_TOKEN_CEILING
  })
}
