import { buildBagMatch, buildMatch, isStopword, parseQuery, parseTimeCue } from '../../../src/main/retrieval/query'
import type { SearchFilters } from '../../../src/shared/types'
import { writeJson } from '../lib'

const NOW = new Date('2026-09-01T12:00:00Z')

const QUERIES: { query: string; filters?: SearchFilters }[] = [
  { query: 'vllm batching article' },
  { query: 'screenshots from today' },
  { query: 'things I saved yesterday' },
  { query: 'papers from last week' },
  { query: 'notes about fonts' },
  { query: 'the "local inference" article' },
  { query: '3 days ago receipts' },
  { query: 'repos I kept last month' },
  { query: 'a few weeks ago' },
  { query: 'the and or' },
  { query: '' },
  { query: 'type:pdf attention is all you need' },
  { query: 'kind:article since:2026-08-01 inference' },
  { query: 'domain:github.com vllm' },
  { query: 'until:7d screenshots' },
  { query: 'mac app for window tiling' },
  { query: 'youtube talks about attention' },
  { query: 'my notes', filters: { strict: true, types: ['note'] } },
  {
    query: 'inference',
    filters: {
      kinds: ['article'],
      domains: ['example.com'],
      since: '2026-08-01T00:00:00Z',
      until: '2026-09-01T00:00:00Z'
    }
  },
  { query: 'receipt from the other day' },
  { query: 'dataset parquet' }
]

export function exportQuery(): void {
  writeJson('query.json', {
    now: NOW.toISOString(),
    queries: QUERIES.map(({ query, filters }) => ({
      query,
      filters: filters ?? {},
      parsed: parseQuery(query, NOW, filters),
      timeCue: parseTimeCue(query.toLowerCase(), NOW),
      match: buildMatch(parseQuery(query, NOW, filters)),
      matchOr: buildMatch(parseQuery(query, NOW, filters), { mode: 'or' }),
      matchPrefix: buildMatch(parseQuery(query, NOW, filters), { prefixLast: true }),
      matchNoSynonyms: buildMatch(parseQuery(query, NOW, filters), { synonyms: false })
    })),
    timeCues: [
      'today',
      'yesterday',
      'this week',
      'last week',
      'this month',
      'past month',
      'last year',
      'a few weeks ago',
      'couple of days ago',
      'a few months ago',
      'a week ago',
      'one month ago',
      '3 days ago',
      '2 weeks ago',
      '6 months ago',
      'recently',
      'the other day',
      'in august',
      '2025',
      'no cue here'
    ].map((s) => ({ input: s, cue: parseTimeCue(s, NOW) })),
    bagMatch: [
      ['llm serving', 'PagedAttention', 'vllm'],
      ['the and or'],
      ['fonts typography'],
      [],
      [
        'one',
        'two',
        'three',
        'four',
        'five',
        'six',
        'seven',
        'eight',
        'nine',
        'ten',
        'eleven',
        'twelve',
        'thirteen',
        'fourteen',
        'fifteen',
        'sixteen',
        'seventeen',
        'eighteen',
        'nineteen',
        'twenty',
        'twentyone',
        'twentytwo',
        'twentythree',
        'twentyfour',
        'twentyfive'
      ]
    ].map((words) => ({ words, out: buildBagMatch(words) })),
    isStopword: ['the', 'vllm', 'ago', 'thing', 'mac', 'kept', 'inference', 'recently'].map((t) => ({
      token: t,
      out: isStopword(t)
    }))
  })
}
