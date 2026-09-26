import * as stylex from '@stylexjs/stylex'
import { colors, fonts, media, motion, radii, shadows, space, text, weight } from '../../../styles/tokens.stylex'

const rise = stylex.keyframes({
  from: { opacity: 0, transform: 'translateY(8px)' },
  to: { opacity: 1, transform: 'translateY(0)' }
})

/** One pass of the scan head over a tile: a quick lift and a short tail, so the row reads as a wave. */
const wave = stylex.keyframes({
  '0%': { opacity: 0.24, transform: 'translateY(0) scale(1)' },
  '7%': { opacity: 1, transform: 'translateY(-6px) scale(1.06)' },
  '22%': { opacity: 0.24, transform: 'translateY(0) scale(1)' },
  '100%': { opacity: 0.24, transform: 'translateY(0) scale(1)' }
})

/** Text arrives out of focus rather than a letter at a time: a word resolves, it is not typed. */
const wordIn = stylex.keyframes({
  from: { opacity: 0, filter: 'blur(5px)' },
  to: { opacity: 1, filter: 'blur(0px)' }
})

const breathe = stylex.keyframes({
  '0%': { opacity: 0.3 },
  '50%': { opacity: 0.85 },
  '100%': { opacity: 0.3 }
})

export const styles = stylex.create({
  // The question sits where the input was and clicking it goes back there, so the run never traps you.
  head: {
    display: 'grid',
    gridTemplateColumns: '16px 1fr auto',
    alignItems: 'center',
    gap: space.s3,
    minHeight: 52,
    paddingInline: space.s5,
    borderBottomWidth: 1,
    borderBottomStyle: 'solid',
    borderBottomColor: colors.hairline,
    textAlign: 'left',
    color: { default: colors.fg4, ':hover': colors.fg2 },
    backgroundColor: { default: 'transparent', ':hover': colors.bgHover }
  },
  question: { fontSize: text.t15, color: colors.fg1 },
  status: {
    display: 'grid',
    gridTemplateColumns: '8px 1fr auto',
    alignItems: 'center',
    gap: space.s3,
    minHeight: 40,
    paddingInline: space.s5,
    fontSize: text.t13,
    color: colors.fg1
  },
  time: { fontSize: text.t11, color: colors.fg3, fontFamily: fonts.mono, fontVariantNumeric: 'tabular-nums' },
  body: {
    paddingInline: space.s5,
    paddingBottom: space.s4,
    display: 'flex',
    flexDirection: 'column',
    gap: space.s3,
    // Without this the flex item refuses to shrink below its content and the dialog clips the
    // answer instead of scrolling it.
    minHeight: 0,
    overflowY: 'auto',
    // Scritto's leaving glyphs sit outside the host box mid-roll; without this the auto-x that
    // overflowY implies flashes a horizontal scrollbar every tick.
    overflowX: 'hidden'
  },

  strip: { display: 'flex', gap: 4, alignItems: 'flex-end', height: 42, paddingTop: 2, flexShrink: 0 },
  tile: {
    flexGrow: 1,
    flexShrink: 1,
    flexBasis: 0,
    minWidth: 0,
    maxWidth: 52,
    height: 36,
    borderRadius: 4,
    overflow: 'hidden',
    opacity: 0.24,
    // Items with no thumbnail still have to read as tiles, so the strip keeps its rhythm.
    backgroundColor: colors.bgActive,
    transitionProperty: 'opacity, transform, box-shadow',
    transitionDuration: motion.base,
    transitionTimingFunction: motion.easeOut
  },
  /** Passed over already: bright enough to read as covered ground, still behind the head. */
  tileSeen: { opacity: 0.55 },
  tileWave: {
    animationName: { default: wave, [media.reducedMotion]: 'none' },
    animationDuration: '1500ms',
    animationTimingFunction: 'linear',
    animationIterationCount: 'infinite'
  },
  tileDelay: (ms: number) => ({ animationDelay: `${ms}ms` }),
  tileLit: {
    opacity: 1,
    transform: 'translateY(-5px)',
    boxShadow: `0 0 0 1.5px ${colors.accent}, ${shadows.lift}`,
    animationName: 'none'
  },
  tileHover: { transform: 'translateY(-5px) scale(1.08)', opacity: 1 },
  track: {
    height: 2,
    flexShrink: 0,
    borderRadius: 1,
    marginTop: space.s3,
    backgroundColor: colors.hairline,
    overflow: 'hidden'
  },
  fill: (pct: number) => ({
    width: `${pct}%`,
    height: 2,
    backgroundColor: colors.accent,
    transitionProperty: 'width',
    transitionDuration: motion.slow,
    transitionTimingFunction: motion.easeOut
  }),
  caption: {
    display: 'flex',
    alignItems: 'baseline',
    gap: space.s3,
    marginTop: 10,
    fontSize: text.t12,
    color: colors.fg3,
    minWidth: 0
  },
  captionText: { flexGrow: 1, minWidth: 0 },
  counter: { fontFamily: fonts.mono, fontSize: text.t11, color: colors.fg3, fontVariantNumeric: 'tabular-nums' },

  matches: { display: 'flex', flexDirection: 'column', gap: space.s2 },
  match: {
    display: 'grid',
    gridTemplateColumns: '64px 1fr',
    gap: space.s3,
    alignItems: 'center',
    paddingBlock: space.s2,
    paddingInline: space.s2,
    borderRadius: radii.r2,
    borderWidth: 1,
    borderStyle: 'solid',
    borderColor: { default: colors.hairline, ':hover': colors.hairlineStrong },
    backgroundColor: { default: colors.bg2, ':hover': colors.bgActive },
    textAlign: 'left',
    transform: { default: 'translateX(0)', ':hover': 'translateX(2px)' },
    transitionProperty: 'background-color, transform, border-color',
    transitionDuration: motion.fast,
    transitionTimingFunction: motion.easeOut,
    animationName: rise,
    animationDuration: motion.slow,
    animationTimingFunction: motion.easeSettle,
    animationFillMode: 'both'
  },
  matchQuiet: { gridTemplateColumns: '40px 1fr', paddingBlock: 6 },
  matchDelay: (ms: number) => ({ animationDelay: `${ms}ms` }),
  matchThumb: { width: 64, height: 46, borderRadius: 4, overflow: 'hidden' },
  matchThumbQuiet: { width: 40, height: 28 },
  matchBody: { minWidth: 0, display: 'flex', flexDirection: 'column', gap: 4 },
  matchHead: { display: 'flex', alignItems: 'baseline', gap: space.s2, minWidth: 0 },
  matchTitle: { fontSize: text.t13, color: colors.fg1, minWidth: 0 },
  matchWhere: { fontSize: text.t11, color: colors.fg4, whiteSpace: 'nowrap' },
  quote: { fontSize: text.t12, lineHeight: 1.5, color: colors.fg2, fontStyle: 'italic' },
  /** The highlighter: a soft accent wash that bleeds a little past the glyphs. */
  mark: {
    borderRadius: 2,
    backgroundColor: colors.accentSoft,
    boxShadow: `0 0 0 3px ${colors.accentSoft}`,
    color: colors.fg1
  },

  // Full-bleed rule between what was found and what is written from it: two different kinds of
  // text, so they never read as one block.
  divider: {
    height: 1,
    flexShrink: 0,
    backgroundColor: colors.hairlineStrong,
    marginInline: `calc(-1 * ${space.s5})`,
    marginTop: space.s2,
    marginBottom: space.s2
  },
  answer: { fontSize: 15, lineHeight: 1.6, color: colors.fg1, whiteSpace: 'pre-wrap' },
  fact: { color: colors.accent, fontWeight: weight.semibold },
  word: {
    animationName: { default: wordIn, [media.reducedMotion]: 'none' },
    animationDuration: '300ms',
    animationTimingFunction: motion.easeOut,
    // `backwards`, so a word is invisible during its delay; with the animation off it is simply there.
    animationFillMode: 'backwards'
  },
  wordDelay: (ms: number) => ({ animationDelay: `${ms}ms` }),
  skeleton: { display: 'flex', flexDirection: 'column', gap: space.s3, paddingBlock: space.s2 },
  bar: (widthPct: number, delayMs: number) => ({
    height: 10,
    width: `${widthPct}%`,
    borderRadius: 5,
    backgroundColor: colors.hairlineStrong,
    animationName: breathe,
    animationDuration: '1400ms',
    animationTimingFunction: 'ease-in-out',
    animationIterationCount: 'infinite',
    animationDelay: `${delayMs}ms`
  }),
  evidence: { fontSize: text.t11, color: colors.fg4 },
  error: { fontSize: text.t13, color: colors.fg2, lineHeight: 1.5 },
  noteCard: {
    display: 'flex',
    alignItems: 'center',
    gap: space.s3,
    paddingBlock: space.s3,
    paddingInline: space.s4,
    borderRadius: radii.r2,
    backgroundColor: colors.paper,
    color: colors.ink,
    transform: { default: 'translateY(0)', ':hover': 'translateY(-1px)' },
    transitionProperty: 'transform',
    transitionDuration: motion.fast,
    transitionTimingFunction: motion.easeOut
  },
  noteTitle: { fontWeight: weight.medium, flexGrow: 1, minWidth: 0 },
  noteOpen: { fontSize: text.t12, color: 'rgba(29, 26, 23, 0.6)' },

  followUp: {
    display: 'flex',
    alignItems: 'center',
    gap: space.s3,
    paddingInline: space.s5,
    borderTopWidth: 1,
    borderTopStyle: 'solid',
    borderTopColor: colors.hairline,
    color: colors.fg4
  },
  followUpInput: {
    flexGrow: 1,
    height: 40,
    fontSize: text.t13,
    color: colors.fg1,
    backgroundColor: 'transparent',
    borderStyle: 'none',
    outline: { default: 'none', ':focus-visible': 'none' },
    '::placeholder': { color: colors.fg4 }
  },
  footer: {
    display: 'flex',
    alignItems: 'center',
    gap: space.s2,
    paddingBlock: space.s2,
    paddingInline: space.s3,
    borderTopWidth: 1,
    borderTopStyle: 'solid',
    borderTopColor: colors.hairline,
    color: colors.fg4,
    fontSize: text.t12
  },
  footerSpacer: { flexGrow: 1 },
  provenance: { minWidth: 0, color: colors.fg4 }
})
