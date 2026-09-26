import { describe, expect, it, vi } from 'vitest'
import { resetOut } from './lib'

// StyleX compiles away to objects we want verbatim: vars/consts are their argument,
// createTheme's override is its second argument.
vi.mock('@stylexjs/stylex', () => ({
  defineVars: (vars: unknown) => vars,
  defineConsts: (vars: unknown) => vars,
  createTheme: (_vars: unknown, theme: unknown) => theme,
  create: (styles: unknown) => styles,
  props: () => ({}),
  keyframes: (frames: unknown) => frames
}))

const enabled = process.env.KEEPANYTHING_PARITY_EXPORT === '1'

describe.skipIf(!enabled)('parity export', () => {
  it('writes every fixture into Tests/Fixtures/parity', async () => {
    resetOut()
    const exporters = await Promise.all([
      import('./exporters/vocab'),
      import('./exporters/limits'),
      import('./exporters/status-table'),
      import('./exporters/text'),
      import('./exporters/migrations'),
      import('./exporters/prompts'),
      import('./exporters/structured'),
      import('./exporters/url'),
      import('./exporters/query'),
      import('./exporters/classify'),
      import('./exporters/hash-vectors'),
      import('./exporters/masonry'),
      import('./exporters/design'),
      import('./exporters/retrieval-eval')
    ])
    const [
      vocab,
      limits,
      statusTable,
      text,
      migrations,
      prompts,
      structured,
      url,
      query,
      classify,
      hash,
      masonry,
      design,
      evalx
    ] = exporters
    vocab.exportVocab()
    limits.exportLimits()
    statusTable.exportStatusTable()
    text.exportText()
    migrations.exportMigrations()
    prompts.exportPrompts()
    structured.exportStructured()
    url.exportUrl()
    query.exportQuery()
    classify.exportClassify()
    await hash.exportHashVectors()
    masonry.exportMasonry()
    await design.exportDesign()
    await evalx.exportRetrievalEval()
    expect(exporters).toHaveLength(14)
  })
})
