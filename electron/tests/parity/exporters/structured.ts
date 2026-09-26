import { extractJson, extractJsonCandidates, repairToolArguments } from '../../../src/main/ai/structured'
import { writeJson } from '../lib'

const CASES: { name: string; input: string }[] = [
  { name: 'bare-json', input: '{"a": 1}' },
  { name: 'fenced-json', input: '```json\n{"a": 1, "b": [2, 3]}\n```' },
  { name: 'fenced-unlabelled', input: '```\n{"a": 1}\n```' },
  { name: 'think-prefix', input: '<think>reasoning here</think>{"a": 1}' },
  { name: 'unclosed-think', input: '<think>still thinking {"a": 1}' },
  { name: 'trailing-prose', input: '{"a": 1}\nHope that helps!' },
  { name: 'leading-prose', input: 'Here you go:\n{"a": 1}' },
  { name: 'multiple-candidates', input: '```json\n{"wrong": true}\n```\nActually: {"right": true}' },
  { name: 'truncated', input: '{"a": [1, 2, 3' },
  { name: 'single-quotes', input: "{'a': 'b'}" },
  { name: 'trailing-commas', input: '{"a": 1, "b": [2, 3,],}' },
  { name: 'unquoted-keys', input: '{a: 1, b_c: "x"}' },
  { name: 'empty', input: '' },
  { name: 'whitespace', input: '   \n  ' },
  { name: 'non-object', input: '[1, 2, 3]' },
  { name: 'garbage', input: 'no json at all' },
  { name: 'nested-prose', input: 'prose {"outer": {"inner": 5}} tail {"second": 2}' },
  { name: 'fenced-then-raw', input: '```json\n{"a": 0}\n```\n{"a": 1}' },
  { name: 'unbalanced-open', input: '{"a": {"b": 2' },
  { name: 'string-with-brace', input: '{"a": "x {not json} y"}' }
]

function extractJsonOrError(input: string): unknown {
  try {
    return { value: extractJson(input) ?? null }
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) }
  }
}

export function exportStructured(): void {
  writeJson('structured.json', {
    cases: CASES.map((c) => ({
      name: c.name,
      input: c.input,
      extractJsonCandidates: extractJsonCandidates(c.input),
      extractJson: extractJsonOrError(c.input),
      repairToolArguments: repairToolArguments(c.input)
    }))
  })
}
