import { describe, expect, it } from 'vitest'
import {
  askMatched,
  askPhase,
  askScanned,
  askStatus,
  evidenceHeader,
  factSpans,
  formatElapsed,
  groupHits,
  hitSnippet,
  noteBodyFor,
  noteTitleFor,
  snippetSpans,
  toolLabel
} from '../../src/renderer/src/lib/palette'
import type { AgentStep, SearchHit } from '../../src/shared/types'

function askStep(n: number, kind: AgentStep['kind'], itemIds: string[], status: AgentStep['status'] = 'ok'): AgentStep {
  return { n, tool: 't', kind, label: '', itemIds, status, durationMs: 1 }
}

function hit(id: string, type: SearchHit['type'], extra: Partial<SearchHit> = {}): SearchHit {
  return {
    id,
    title: id,
    type,
    subtype: null,
    kind: null,
    domain: null,
    capturedAt: '2026-01-01T00:00:00.000Z',
    capturedAgo: 'just now',
    understanding: null,
    evidence: { matchedFields: [] },
    score: 1,
    ...extra
  }
}

describe('groupHits', () => {
  it('groups by type, keeps rank order inside a group and orders groups by their best hit', () => {
    const groups = groupHits([
      hit('a', 'pdf'),
      hit('b', 'url'),
      hit('c', 'markdown'),
      hit('d', 'image'),
      hit('e', 'url')
    ])
    expect(groups.map((g) => g.id)).toEqual(['documents', 'links', 'images'])
    expect(groups[0]?.hits.map((h) => h.id)).toEqual(['a', 'c'])
    expect(groups[1]?.hits.map((h) => h.id)).toEqual(['b', 'e'])
    expect(groups[0]?.label).toBe('Documents')
  })

  it('drops empty groups and maps every type', () => {
    expect(groupHits([])).toEqual([])
    const ids = groupHits([
      hit('n', 'note'),
      hit('f', 'file'),
      hit('v', 'video'),
      hit('u', 'unknown'),
      hit('fo', 'folder')
    ]).map((g) => g.id)
    expect(ids).toEqual(['notes', 'files', 'images'])
  })
})

describe('hitSnippet', () => {
  it('strips the FTS markers from the snippet it shows', () => {
    expect(hitSnippet({ snippet: 'the [[deposit]] is due', understanding: 'x' })).toBe('the deposit is due')
  })

  it('prefers the FTS snippet, then understanding, then domain', () => {
    expect(hitSnippet({ snippet: ' batching ', understanding: 'x', domain: 'y' })).toBe('batching')
    expect(hitSnippet({ understanding: 'An article', domain: 'y' })).toBe('An article')
    expect(hitSnippet({ domain: 'anyscale.com' })).toBe('anyscale.com')
    expect(hitSnippet({ domain: null })).toBe('')
  })
})

describe('toolLabel / formatElapsed', () => {
  it('maps tool ids to short verbs and falls back gracefully', () => {
    expect(toolLabel('search_library')).toBe('Searched')
    expect(toolLabel('read_document')).toBe('Read')
    expect(toolLabel('create_note')).toBe('Wrote')
    expect(toolLabel('finish')).toBe('Answered')
    expect(toolLabel('some_new_tool')).toBe('Some new tool')
  })

  it('formats elapsed time compactly', () => {
    expect(formatElapsed(420)).toBe('0.4s')
    expect(formatElapsed(1000)).toBe('1s')
    expect(formatElapsed(12_400)).toBe('12s')
    expect(formatElapsed(65_000)).toBe('1m 05s')
    expect(formatElapsed(-1)).toBe('0s')
  })
})

describe('evidenceHeader', () => {
  const step = (
    n: number,
    kind: AgentStep['kind'],
    itemIds: string[],
    status: AgentStep['status'] = 'ok'
  ): AgentStep => ({
    n,
    tool: 't',
    kind,
    label: '',
    itemIds,
    status,
    durationMs: 1
  })

  it('counts distinct looked-at and read items from structured steps only', () => {
    const header = evidenceHeader(
      [
        step(1, 'search', ['a', 'b', 'c']),
        step(2, 'read', ['a', 'd']),
        step(3, 'read', ['a'], 'rejected'),
        step(4, 'write', [])
      ],
      { topics: ['inference', 'cost', 'gpu', 'extra'], types: [], timeframe: { label: 'Last month' } }
    )
    expect(header).toBe('Looked at 4 items · Read 2 · 1 change · Theme: inference, cost, gpu · Last month')
  })

  it('is empty when nothing is known', () => {
    expect(evidenceHeader([])).toBe('')
    expect(evidenceHeader([step(1, 'read', ['x'])])).toBe('Looked at 1 item · Read 1')
  })
})

describe('ask run view', () => {
  it('reads the phase off the steps and the result', () => {
    expect(askPhase(undefined)).toBe('scanning')
    expect(askPhase({ status: 'running', steps: [], answered: false })).toBe('scanning')
    expect(askPhase({ status: 'running', steps: [askStep(1, 'search', ['a'])], answered: false })).toBe('scanning')
    expect(askPhase({ status: 'running', steps: [askStep(1, 'read', ['a'])], answered: false })).toBe('reading')
    // A rejected read is not a match, so the strip keeps sweeping.
    expect(askPhase({ status: 'running', steps: [askStep(1, 'read', ['a'], 'rejected')], answered: false })).toBe(
      'scanning'
    )
    expect(askPhase({ status: 'succeeded', steps: [], answered: true })).toBe('answered')
    expect(askPhase({ status: 'cancelled', steps: [], answered: false })).toBe('failed')
  })

  it('separates what was scanned from what was opened, first seen first, without repeats', () => {
    const steps = [askStep(1, 'search', ['a', 'b']), askStep(2, 'inspect', ['b', 'c']), askStep(3, 'read', ['c'])]
    expect(askScanned(steps)).toEqual(['a', 'b', 'c'])
    expect(askMatched(steps)).toEqual(['b', 'c'])
    expect(askScanned([askStep(1, 'search', ['a'], 'rejected')])).toEqual([])
  })

  it('says what is happening in product voice', () => {
    expect(askStatus('scanning', 0)).toBe('Looking through your library')
    expect(askStatus('reading', 1)).toBe('Reading 1 match')
    expect(askStatus('reading', 2)).toBe('Reading 2 matches')
    expect(askStatus('answered', 2)).toBe('Found it in 2 things you kept')
    expect(askStatus('answered', 0)).toBe('Answered')
    expect(askStatus('failed', 0)).toBe('Stopped')
  })
})

describe('highlight spans', () => {
  it('splits a snippet on its FTS markers', () => {
    expect(snippetSpans('a [[deposit]] of two')).toEqual([
      { text: 'a ', hot: false },
      { text: 'deposit', hot: true },
      { text: ' of two', hot: false }
    ])
    expect(snippetSpans('nothing marked')).toEqual([{ text: 'nothing marked', hot: false }])
    expect(snippetSpans('')).toEqual([])
  })

  it('picks out amounts, times and dates in an answer, and nothing else', () => {
    const spans = factSpans('Two months — 2 900 € — and the keys on 14 March at 11:00, at the door.')
    expect(spans.filter((s) => s.hot).map((s) => s.text)).toEqual(['2 900 €', '14 March', '11:00'])
    expect(spans.map((s) => s.text).join('')).toBe(
      'Two months — 2 900 € — and the keys on 14 March at 11:00, at the door.'
    )
    expect(factSpans('Mostly notes about serving cost.')).toEqual([
      { text: 'Mostly notes about serving cost.', hot: false }
    ])
  })

  it('stops highlighting after the cap', () => {
    const spans = factSpans('1 item 2 items 3 items 4 items', 2)
    expect(spans.filter((s) => s.hot)).toHaveLength(2)
    expect(spans.map((s) => s.text).join('')).toBe('1 item 2 items 3 items 4 items')
  })
})

describe('note helpers', () => {
  it('derives a note title and body from the question and answer', () => {
    expect(noteTitleFor('  What am I  researching here?? ')).toBe('What am I researching here')
    expect(noteTitleFor('')).toBe('Answer')
    expect(noteTitleFor('x'.repeat(100))).toHaveLength(72)
    const body = noteBodyFor('Why?', ' Because. ', [{ title: 'A' }, { title: 'B' }])
    expect(body).toBe('# Why\n\nBecause.\n\n## Sources\n\n- A\n- B')
    expect(noteBodyFor('Why?', 'Because.', [])).toBe('# Why\n\nBecause.')
  })
})
