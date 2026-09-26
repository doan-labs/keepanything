import { createHashEmbeddingProvider, fnv1a, hashEmbed, tokenize } from '../../../src/main/ai/embeddings/hash'
import { writeJson } from '../lib'

const STRINGS = ['vllm', 'local inference', 'keepanything', 'attention is all you need', 'a', '']

const TEXTS = [
  'vllm: easy, fast and cheap LLM serving with PagedAttention',
  'Notes on local inference providers: GMI Cloud vs OpenRouter.',
  'The quick brown fox jumps over the lazy dog.',
  '',
  'a an the and or of to in on at by for with from as is',
  'Design references for the shelf rail fillet and notch.'
]

export async function exportHashVectors(): Promise<void> {
  const provider = createHashEmbeddingProvider()
  const batch = await provider.embed(TEXTS.slice(0, 3))
  writeJson('hash-vectors.json', {
    fnv1a: STRINGS.map((s) => ({ input: s, seed: 0x811c9dc5, hash: fnv1a(s) })).concat([
      { input: 'vllm', seed: 0x9747b28c, hash: fnv1a('vllm', 0x9747b28c) }
    ]),
    tokenize: TEXTS.map((t) => ({ input: t, tokens: tokenize(t) })),
    hashEmbed: TEXTS.slice(0, 4)
      .map((t) => ({ input: t, dims: 384, vector: Array.from(hashEmbed(t, 384)) }))
      .concat([{ input: TEXTS[0] ?? '', dims: 16, vector: Array.from(hashEmbed(TEXTS[0] ?? '', 16)) }]),
    provider: {
      id: provider.id,
      model: provider.model,
      dims: provider.dims,
      batch: batch.map((v) => Array.from(v))
    }
  })
}
