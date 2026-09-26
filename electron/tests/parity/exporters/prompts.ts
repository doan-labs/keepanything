import {
  buildCommandMessages,
  buildConsolidateMessages,
  buildConsolidateRequest,
  buildFolderMessages,
  buildFolderRequest,
  buildOrganizeBatchMessages,
  buildOrganizeBatchRequest,
  buildOrganizeMessages,
  buildOrganizeRequest,
  buildUnderstandMessages,
  buildUnderstandRequest,
  COLLECTION_RULES,
  COMMAND_SYSTEM_PROMPT,
  CONSOLIDATE_SYSTEM_PROMPT,
  type CommandInput,
  type ConsolidateInput,
  FINISH_TOOL_NAME,
  FOLDER_SYSTEM_PROMPT,
  FORCE_FINISH_MESSAGE,
  type FolderInput,
  KIND_RULES,
  NO_TOOL_CALL_MESSAGE,
  ORGANIZE_SYSTEM_PROMPT,
  type OrganizeBatchInput,
  type OrganizeInput,
  RELATIONSHIP_RULES,
  UNDERSTAND_SYSTEM_PROMPT,
  type UnderstandInput,
  VOICE_RULES
} from '../../../src/main/ai/prompts'
import { finishToolSpec } from '../../../src/main/ai/prompts/finish'
import { IDENTITY, KIND_LIST, RELATIONSHIP_CATALOG } from '../../../src/main/ai/prompts/voice'
import {
  commandFinishSchema,
  consolidatePlanSchema,
  folderUnderstandingSchema,
  organizePlanSchema,
  understandingSchema
} from '../../../src/main/ai/schemas'
import { buildStructuredContract, messagesWithContract } from '../../../src/main/ai/structured'
import type { ChatRequest, StructuredSchema } from '../../../src/main/ports'
import { writeJson } from '../lib'

const LONG_TEXT = `Inference batching notes. ${'The scheduler batches prefill and decode separately. '.repeat(400)}`

const minimalUnderstand: UnderstandInput = { title: 'vllm', type: 'url' }
const fullUnderstand: UnderstandInput = {
  title: 'vllm: Easy, Fast, and Cheap LLM Serving',
  type: 'url',
  subtype: 'github_repo',
  url: 'https://github.com/vllm-project/vllm',
  domain: 'github.com',
  mimeType: 'text/html',
  metadata: { stars: 60_000, language: 'Python', siteName: 'GitHub' },
  text: 'vllm is a serving engine for LLMs built around PagedAttention and continuous batching.',
  images: ['data:image/jpeg;base64,AAAA'],
  children: [
    { title: 'README.md', kind: 'docs', understanding: 'Install and quickstart guide.' },
    { title: 'notes.md', kind: null, understanding: null }
  ],
  capturedAt: '2026-08-20T09:30:00.000Z'
}
const longUnderstand: UnderstandInput = { ...minimalUnderstand, text: LONG_TEXT }

const minimalOrganize: OrganizeInput = {
  item: { id: 'i1', title: 'vllm', type: 'url' },
  candidates: [],
  collections: []
}
const fullOrganize: OrganizeInput = {
  item: {
    id: 'i1',
    title: 'vllm serving notes',
    type: 'note',
    subtype: null,
    kind: 'note',
    domain: null,
    capturedAgo: '2 days ago',
    topics: ['llm serving', 'batching'],
    entities: ['vllm', 'PagedAttention'],
    understanding: 'Notes comparing serving engines for local inference.',
    whyUseful: 'Reference when picking a serving stack.'
  },
  candidates: [
    {
      id: 'c1',
      title: 'vllm GitHub repo',
      type: 'url',
      kind: 'library',
      domain: 'github.com',
      capturedAgo: '3 weeks ago',
      topics: ['llm serving'],
      understanding: 'Serving engine repo.',
      cosine: 0.82,
      sharedTopics: ['llm serving'],
      sharedEntities: ['vllm'],
      flags: ['same_folder', 'same_hour']
    },
    { id: 'c2', title: 'SGLang overview', type: 'url', kind: 'saas_product', forItemId: 'i1', flags: [] }
  ],
  collections: [
    {
      id: 'col1',
      name: 'Local LLM inference research',
      description: 'Engines, benchmarks and notes about running models on this Mac.',
      count: 7,
      createdBy: 'agent',
      cosine: 0.71,
      nearestMembers: [
        { id: 'c1', title: 'vllm GitHub repo' },
        { id: 'm2', title: 'llama.cpp release notes' }
      ]
    }
  ],
  userFacts: ['"vllm GitHub repo" belongs to "Local LLM inference research".'],
  suppressed: ['relationship: i1 -- notes.md']
}
const longOrganize: OrganizeInput = {
  ...minimalOrganize,
  item: { ...minimalOrganize.item, understanding: LONG_TEXT }
}

const batchInput: OrganizeBatchInput = {
  items: [minimalOrganize.item, { id: 'i2', title: 'clean shot of palette UI', type: 'image' }],
  candidates: fullOrganize.candidates,
  collections: fullOrganize.collections,
  userFacts: fullOrganize.userFacts,
  suppressed: fullOrganize.suppressed
}

const minimalConsolidate: ConsolidateInput = { collections: [], items: [] }
const fullConsolidate: ConsolidateInput = {
  collections: [
    {
      id: 'col1',
      name: 'Local LLM inference research',
      description: 'Engines, benchmarks and notes about running models on this Mac.',
      count: 3,
      createdBy: 'agent',
      members: [
        { id: 'i1', title: 'vllm serving notes', kind: 'note' },
        { id: 'i2', title: 'vllm GitHub repo', kind: 'library' }
      ]
    }
  ],
  items: [
    {
      id: 'i3',
      title: 'TensorRT-LLM benchmarks',
      kind: 'article',
      topics: ['llm serving', 'benchmarks'],
      understanding: 'Benchmark numbers vs vllm.',
      collectionIds: [],
      capturedAgo: 'yesterday'
    }
  ],
  suppressed: ['collection: col-old']
}
const longConsolidate: ConsolidateInput = {
  ...fullConsolidate,
  items: [{ ...(fullConsolidate.items[0] as (typeof fullConsolidate.items)[number]), understanding: LONG_TEXT }]
}

const minimalFolder: FolderInput = {
  title: 'inference-notes',
  structure: { fileCount: 1, dirCount: 0, totalBytes: 320, extensions: { md: 1 } },
  samples: []
}
const fullFolder: FolderInput = {
  title: 'keepanything',
  path: 'repos/keepanything',
  structure: {
    fileCount: 42,
    dirCount: 6,
    totalBytes: 1_900_000,
    truncated: true,
    extensions: { ts: 30, md: 8, swift: 4 },
    tree: 'keepanything/\n  src/\n    main/\n    renderer/\n  docs/'
  },
  samples: [
    { path: 'docs/ARCHITECTURE.md', excerpt: 'Design and implementation contract.' },
    { path: 'README.md', excerpt: 'Keep anything.' }
  ],
  children: [{ id: 'i9', title: 'ARCHITECTURE.md', kind: 'docs', understanding: 'The contract document.' }],
  capturedAt: '2026-07-01T10:00:00.000Z'
}
const longFolder: FolderInput = {
  ...fullFolder,
  structure: { ...fullFolder.structure, tree: `root/\n${'  file.txt\n'.repeat(2000)}` }
}

const minimalCommand: CommandInput = { mode: 'ask', question: 'what is vllm?' }
const fullCommand: CommandInput = {
  mode: 'template',
  template: 'compare',
  seeds: [
    {
      id: 'i1',
      title: 'vllm GitHub repo',
      type: 'url',
      kind: 'library',
      understanding: 'Serving engine.',
      capturedAgo: '3 weeks ago'
    },
    { id: 'i2', title: 'llama.cpp', type: 'url', kind: 'library' }
  ],
  instruction: 'which should I use for Qwen models?',
  today: '2026-09-01'
}
const askHistoryCommand: CommandInput = {
  mode: 'ask',
  question: 'and which is faster?',
  today: '2026-09-01',
  history: [
    { role: 'user', content: 'what is vllm?' },
    { role: 'assistant', content: `A serving engine. ${'Extra detail about batching. '.repeat(200)}` }
  ]
}

function stripSignal(req: ChatRequest): Omit<ChatRequest, 'signal'> {
  const { signal: _signal, ...rest } = req
  return rest
}

function named<T>(name: string, input: T): { name: string; input: T } {
  return { name, input }
}

const SCHEMAS: { name: string; schema: StructuredSchema<unknown> }[] = [
  { name: 'understanding', schema: understandingSchema as StructuredSchema<unknown> },
  { name: 'organizePlan', schema: organizePlanSchema as StructuredSchema<unknown> },
  { name: 'consolidatePlan', schema: consolidatePlanSchema as StructuredSchema<unknown> },
  { name: 'folderUnderstanding', schema: folderUnderstandingSchema as StructuredSchema<unknown> },
  { name: 'commandFinish', schema: commandFinishSchema as StructuredSchema<unknown> }
]

export function exportPrompts(): void {
  writeJson('prompts/system.json', {
    IDENTITY,
    VOICE_RULES,
    KIND_LIST,
    KIND_RULES,
    RELATIONSHIP_CATALOG,
    COLLECTION_RULES,
    RELATIONSHIP_RULES,
    UNDERSTAND_SYSTEM_PROMPT,
    ORGANIZE_SYSTEM_PROMPT,
    CONSOLIDATE_SYSTEM_PROMPT,
    FOLDER_SYSTEM_PROMPT,
    COMMAND_SYSTEM_PROMPT,
    FORCE_FINISH_MESSAGE,
    NO_TOOL_CALL_MESSAGE,
    FINISH_TOOL_NAME
  })

  const understandCases = [
    named('minimal', minimalUnderstand),
    named('full', fullUnderstand),
    named('long-text', longUnderstand)
  ]
  writeJson(
    'prompts/understand.json',
    understandCases.map((c) => ({
      name: c.name,
      input: c.input,
      messages: buildUnderstandMessages(c.input),
      request: stripSignal(buildUnderstandRequest(c.input))
    }))
  )

  const organizeCases = [
    named('minimal', minimalOrganize),
    named('full', fullOrganize),
    named('long-text', longOrganize)
  ]
  writeJson(
    'prompts/organize.json',
    organizeCases.map((c) => ({
      name: c.name,
      input: c.input,
      messages: buildOrganizeMessages(c.input),
      request: stripSignal(buildOrganizeRequest(c.input))
    }))
  )

  const batchCases = [
    named('minimal', { items: [], candidates: [], collections: [] }),
    named('full', batchInput),
    named('long-text', { ...batchInput, items: [{ id: 'i3', title: 'n', type: 'note', understanding: LONG_TEXT }] })
  ]
  writeJson(
    'prompts/organize-batch.json',
    batchCases.map((c) => ({
      name: c.name,
      input: c.input,
      messages: buildOrganizeBatchMessages(c.input),
      request: stripSignal(buildOrganizeBatchRequest(c.input))
    }))
  )

  const consolidateCases = [
    named('minimal', minimalConsolidate),
    named('full', fullConsolidate),
    named('long-text', longConsolidate)
  ]
  writeJson(
    'prompts/consolidate.json',
    consolidateCases.map((c) => ({
      name: c.name,
      input: c.input,
      messages: buildConsolidateMessages(c.input),
      request: stripSignal(buildConsolidateRequest(c.input))
    }))
  )

  const folderCases = [named('minimal', minimalFolder), named('full', fullFolder), named('long-text', longFolder)]
  writeJson(
    'prompts/folder.json',
    folderCases.map((c) => ({
      name: c.name,
      input: c.input,
      messages: buildFolderMessages(c.input),
      request: stripSignal(buildFolderRequest(c.input))
    }))
  )

  const commandCases = [
    named('minimal', minimalCommand),
    named('full', fullCommand),
    named('long-text', askHistoryCommand)
  ]
  writeJson(
    'prompts/command.json',
    commandCases.map((c) => ({ name: c.name, input: c.input, messages: buildCommandMessages(c.input) }))
  )

  writeJson('prompts/structured-contract.json', {
    schemas: SCHEMAS.map(({ name, schema }) => ({
      name,
      contract: buildStructuredContract(schema),
      finishTool: finishToolSpec(schema)
    })),
    messagesWithContract: messagesWithContract(
      [
        { role: 'system', content: 'You are a test.' },
        { role: 'user', content: 'Describe this item.' }
      ],
      understandingSchema as StructuredSchema<unknown>
    )
  })
}
