import {
  bodyHeight,
  columnCount,
  type Direction,
  layoutMasonry,
  type MasonryInput,
  nearestInDirection,
  TYPE_RATIO
} from '../../../src/renderer/src/lib/masonry'
import type { ItemType } from '../../../src/shared/types'
import { writeJson } from '../lib'

/** One item per ItemType (11) plus three exercising intrinsic sizes and caption overrides. */
const ITEMS: MasonryInput[] = [
  { id: 'u1', type: 'url', width: null, height: null },
  { id: 'p1', type: 'pdf', width: null, height: null },
  { id: 'f1', type: 'file', width: null, height: null },
  { id: 'd1', type: 'folder', width: null, height: null },
  { id: 'i1', type: 'image', width: null, height: null },
  { id: 'v1', type: 'video', width: null, height: null },
  { id: 'a1', type: 'audio', width: null, height: null },
  { id: 't1', type: 'text', width: null, height: null },
  { id: 'm1', type: 'markdown', width: null, height: null },
  { id: 'n1', type: 'note', width: null, height: null },
  { id: 'x1', type: 'unknown', width: null, height: null },
  { id: 'i2', type: 'image', width: 3000, height: 2000, captionHeight: 44 },
  { id: 'i3', type: 'image', width: 400, height: 3000, captionHeight: 44 },
  { id: 'v2', type: 'video', width: 1280, height: 720, captionHeight: 64 }
]

const DENSITIES = {
  comfortable: { minColumnWidth: 220 },
  compact: { minColumnWidth: 168 }
} as const

/** Exactly what `masonry-grid/index.tsx` passes (`MIN_COL`, `GAP`, `CAPTION_HEIGHT`). */
const GAP = 14
const CAPTION_HEIGHT = 44

const WIDTHS = [480, 720, 960, 1280, 1600]
const DIRECTIONS: Direction[] = ['up', 'down', 'left', 'right']

export function exportMasonry(): void {
  const layouts = WIDTHS.flatMap((w) =>
    Object.entries(DENSITIES).map(([density, d]) => {
      const options = {
        containerWidth: w,
        minColumnWidth: d.minColumnWidth,
        gap: GAP,
        captionHeight: CAPTION_HEIGHT
      }
      return { containerWidth: w, density, options, layout: layoutMasonry(ITEMS, options) }
    })
  )

  const ref = layoutMasonry(ITEMS, {
    containerWidth: 960,
    minColumnWidth: DENSITIES.comfortable.minColumnWidth,
    gap: GAP,
    captionHeight: CAPTION_HEIGHT
  })
  const nearest = ITEMS.flatMap((item) =>
    DIRECTIONS.map((direction) => ({ from: item.id, direction, to: nearestInDirection(ref, item.id, direction) }))
  )

  writeJson('masonry.json', {
    typeRatio: TYPE_RATIO as Record<ItemType, number>,
    options: { gap: GAP, captionHeight: CAPTION_HEIGHT, densities: DENSITIES },
    items: ITEMS,
    columnCount: WIDTHS.flatMap((w) =>
      Object.entries(DENSITIES).map(([density, d]) => ({
        containerWidth: w,
        density,
        columns: columnCount(w, d.minColumnWidth, GAP)
      }))
    ),
    bodyHeight: [168, 220, 300].flatMap((cw) =>
      ITEMS.map((item) => ({ id: item.id, columnWidth: cw, h: bodyHeight(item, cw) }))
    ),
    layouts,
    nearestInDirection: nearest
  })
}
