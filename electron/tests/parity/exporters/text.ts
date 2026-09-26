import {
  formatBytes,
  formatDuration,
  isProbablyNaturalLanguage,
  normalizeName,
  relativeTime,
  slugify,
  tokenize,
  truncate
} from '../../../src/shared/text'
import { writeJson } from '../lib'

const NOW = '2026-09-01T00:00:00.000Z'
const ago = (ms: number): string => new Date(Date.parse(NOW) - ms).toISOString()

interface Case {
  fn: string
  args: unknown[]
  out: unknown
}

export function exportText(): void {
  const cases: Case[] = []
  const add = (fn: string, args: unknown[], out: unknown): void => {
    cases.push({ fn, args, out })
  }

  for (const [s, n] of [
    ['hello', 10],
    ['hello', 5],
    ['hello world', 6],
    ['hello world', 1],
    ['hello', 0],
    ['a longer title about local inference', 20]
  ] as const)
    add('truncate', [s, n], truncate(s, n))

  for (const s of [
    'mnismt — Visual Direction!',
    '  Résumé 2026.pdf ',
    '---',
    'Local LLM inference notes',
    'Already--dashed  TITLE',
    'Café naïve über',
    ''
  ])
    add('slugify', [s], slugify(s))

  for (const s of [
    '  mnismt:  Visual   Direction!! ',
    'Inference-Research',
    'Things to Read',
    'Ｍacos Apps',
    'MVP — launch (draft)',
    'a   b'
  ])
    add('normalizeName', [s], normalizeName(s))

  for (const iso of [
    NOW,
    ago(30_000),
    ago(60_000),
    ago(5 * 60_000),
    ago(60 * 60_000),
    ago(3 * 3_600_000),
    ago(24 * 3_600_000),
    ago(3 * 86_400_000),
    ago(8 * 86_400_000),
    ago(21 * 86_400_000),
    ago(40 * 86_400_000),
    ago(95 * 86_400_000),
    ago(400 * 86_400_000),
    ago(800 * 86_400_000),
    '2027-01-01T00:00:00.000Z',
    'not a date'
  ])
    add('relativeTime', [iso, NOW], relativeTime(iso, NOW))

  for (const n of [0, 512, 12_300, 2_400_000, 150_000_000, 3_000_000_000, -1, 999, 1_500])
    add('formatBytes', [n], formatBytes(n))

  for (const n of [0, 65_000, 3_725_000, Number.NaN, -1, 600_000, 3_599_000])
    add('formatDuration', [n], formatDuration(n))

  for (const q of [
    'what did I save about vllm?',
    'invoice',
    'show me my screenshots',
    'vllm continuous batching notes',
    'is the library ready?',
    'find the thing about fonts',
    'local inference providers'
  ])
    add('isProbablyNaturalLanguage', [q], isProbablyNaturalLanguage(q))

  for (const s of [
    'Hello, World!',
    'vllm 连续批处理 notes',
    'a-b_c.d e',
    '  multiple   spaces  ',
    'café naïve',
    '123 456'
  ])
    add('tokenize', [s], tokenize(s))

  writeJson('text.json', { nowIso: NOW, cases })
}
