import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { cmp, sha256, writeFile, writeJson } from '../lib'

/** Every icon name imported from 'lucide-react' in electron/src/renderer (grep, 2026-09; LucideIcon is a type). */
const ICONS = [
  'Activity',
  'AlignLeft',
  'ArrowLeft',
  'ArrowUpRight',
  'Check',
  'ChevronDown',
  'ChevronLeft',
  'ChevronRight',
  'ClipboardCopy',
  'Copy',
  'CornerDownLeft',
  'Download',
  'Ellipsis',
  'ExternalLink',
  'Eye',
  'File',
  'FileText',
  'Folder',
  'FolderOpen',
  'Image',
  'KeyRound',
  'Layers',
  'LayoutGrid',
  'Link',
  'Music',
  'Pencil',
  'Play',
  'PlugZap',
  'Plus',
  'RefreshCw',
  'RotateCw',
  'Rows3',
  'Search',
  'Settings',
  'Sprout',
  'SquareStack',
  'Star',
  'StickyNote',
  'Trash2',
  'Video',
  'X'
]

const kebab = (name: string): string =>
  name
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
    .replace(/([a-zA-Z])([0-9]+)$/, '$1-$2')
    .toLowerCase()

type IconNode = [tag: string, attrs: Record<string, unknown>]

/** Icon files that re-export a differently named sibling instead of defining `__iconNode`. */
const ICON_ALIASES: Record<string, string> = { 'align-left': 'text-align-start' }

const SVG_OPEN =
  '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">'

function renderIcon(node: IconNode[]): string {
  const children = node
    .map(([tag, attrs]) => {
      const rendered = Object.entries(attrs)
        .filter(([k]) => k !== 'key')
        .map(([k, v]) => ` ${k}="${String(v)}"`)
        .join('')
      return `<${tag}${rendered}/>`
    })
    .join('')
  return `${SVG_OPEN}${children}</svg>\n`
}

const FONTS_DIR = resolve(__dirname, '../../../assets/fonts')
const GLOBAL_CSS = resolve(__dirname, '../../../src/renderer/src/styles/global.css')

export async function exportDesign(): Promise<void> {
  const tokens = await import('../../../src/renderer/src/styles/tokens.stylex')
  const themes = await import('../../../src/renderer/src/styles/themes')

  const counts: Record<string, number> = {
    colors: Object.keys(tokens.colors).length,
    shadows: Object.keys(tokens.shadows).length,
    radii: Object.keys(tokens.radii).length,
    space: Object.keys(tokens.space).length,
    text: Object.keys(tokens.text).length,
    weight: Object.keys(tokens.weight).length,
    motion: Object.keys(tokens.motion).length,
    layout: Object.keys(tokens.layout).length,
    zIndex: Object.keys(tokens.zIndex).length
  }
  const expected = { colors: 24, shadows: 4, radii: 3, space: 9, text: 7, weight: 3, motion: 8, layout: 6, zIndex: 7 }
  for (const [k, want] of Object.entries(expected)) {
    if (counts[k] !== want) {
      throw new Error(`design token count mismatch: ${k} is ${counts[k]}, PLAN.md says ${want}`)
    }
  }

  writeJson('design/tokens.json', {
    colors: { vars: tokens.colors, light: themes.lightColors, dark: themes.darkColors },
    shadows: { vars: tokens.shadows, light: themes.lightShadows, dark: themes.darkShadows },
    radii: tokens.radii,
    space: tokens.space,
    fonts: tokens.fonts,
    text: tokens.text,
    weight: tokens.weight,
    motion: tokens.motion,
    layout: tokens.layout,
    zIndex: tokens.zIndex,
    media: tokens.media
  })

  const iconsJson: Record<string, string> = {}
  for (const name of [...ICONS].sort(cmp)) {
    const file = `${kebab(name)}.svg`
    const kebabName = kebab(name)
    let mod = (await import(`lucide-react/dist/esm/icons/${kebabName}.mjs`)) as {
      __iconNode?: IconNode[]
    }
    if (!Array.isArray(mod.__iconNode) && ICON_ALIASES[kebabName]) {
      mod = (await import(`lucide-react/dist/esm/icons/${ICON_ALIASES[kebabName]}.mjs`)) as {
        __iconNode?: IconNode[]
      }
    }
    if (!Array.isArray(mod.__iconNode)) throw new Error(`no __iconNode for ${name}`)
    writeFile(`design/icons/${file}`, renderIcon(mod.__iconNode))
    iconsJson[name] = file
  }
  writeJson('design/icons.json', iconsJson)

  const css = readFileSync(GLOBAL_CSS, 'utf8')
  const fontFaces: unknown[] = []
  for (const match of css.matchAll(/@font-face\s*\{([^}]+)\}/g)) {
    const body = match[1] ?? ''
    const get = (prop: string): string | null => new RegExp(`${prop}:\\s*([^;]+)`).exec(body)?.[1]?.trim() ?? null
    const src = /url\('([^']+)'\)/.exec(body)?.[1] ?? null
    fontFaces.push({
      family: get('font-family'),
      style: get('font-style'),
      weight: get('font-weight'),
      src: src ? src.split('/').pop() : null
    })
  }
  writeJson('design/fonts.json', {
    files: readdirSync(FONTS_DIR)
      .sort(cmp)
      .map((file) => {
        const content = readFileSync(join(FONTS_DIR, file))
        return { file, bytes: statSync(join(FONTS_DIR, file)).size, sha256: sha256(content) }
      }),
    fontFaces
  })
}
