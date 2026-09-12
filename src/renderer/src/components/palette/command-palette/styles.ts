import * as stylex from '@stylexjs/stylex'
import { colors, motion, radii, shadows, space, text, zIndex } from '../../../styles/tokens.stylex'

const fade = stylex.keyframes({ from: { opacity: 0 } })
const rise = stylex.keyframes({ from: { opacity: 0, transform: 'translateY(-6px)' } })

export const styles = stylex.create({
  scrim: {
    position: 'absolute',
    inset: 0,
    zIndex: zIndex.palette,
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'flex-start',
    paddingTop: '12vh',
    backgroundColor: colors.scrim,
    animationName: fade,
    animationDuration: motion.fast,
    animationTimingFunction: motion.easeOut
  },
  dialog: {
    width: 640,
    maxWidth: 'calc(100vw - 80px)',
    maxHeight: '66vh',
    display: 'flex',
    flexDirection: 'column',
    borderRadius: radii.r3,
    backgroundColor: colors.bg3,
    backdropFilter: 'blur(24px)',
    borderWidth: 1,
    borderStyle: 'solid',
    borderColor: colors.hairline,
    boxShadow: shadows.sheet,
    overflow: 'hidden',
    animationName: rise,
    animationDuration: motion.base,
    animationTimingFunction: motion.easeOut
  },
  inputRow: {
    display: 'flex',
    alignItems: 'center',
    gap: space.s3,
    paddingInline: space.s5,
    borderBottomWidth: 1,
    borderBottomStyle: 'solid',
    borderBottomColor: colors.hairline,
    color: colors.fg4
  },
  input: {
    flexGrow: 1,
    height: 52,
    fontSize: text.t15,
    color: colors.fg1,
    outline: { default: 'none', ':focus-visible': 'none' },
    '::placeholder': { color: colors.fg4 }
  },
  modeChip: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 6,
    height: 24,
    paddingInline: space.s2,
    borderRadius: radii.r1,
    backgroundColor: colors.bgActive,
    color: colors.fg2,
    fontSize: text.t12,
    whiteSpace: 'nowrap'
  },
  // Pinned between the input and the list so a long hit list can never push Ask out of sight.
  // The 16px column puts its icon under the search icon and its label under the query.
  askBar: {
    display: 'grid',
    gridTemplateColumns: '16px 1fr auto',
    alignItems: 'center',
    gap: space.s3,
    minHeight: 40,
    paddingBlock: 6,
    paddingInline: space.s5,
    borderBottomWidth: 1,
    borderBottomStyle: 'solid',
    borderBottomColor: colors.hairline,
    textAlign: 'left',
    color: colors.fg1,
    fontSize: text.t13,
    backgroundColor: { default: 'transparent', ':hover': colors.bgHover }
  },
  list: { overflowY: 'auto', paddingTop: space.s2, paddingInline: space.s2, paddingBottom: space.s2 },
  heading: {
    display: 'block',
    paddingTop: space.s2,
    paddingInline: space.s3,
    paddingBottom: space.s1,
    fontSize: text.t11,
    letterSpacing: '0.06em',
    textTransform: 'uppercase',
    color: colors.fg4
  },
  item: {
    display: 'grid',
    gridTemplateColumns: '36px 1fr auto',
    alignItems: 'center',
    gap: space.s3,
    minHeight: 44,
    paddingBlock: 6,
    paddingInline: space.s3,
    borderRadius: radii.r1,
    color: colors.fg1
  },
  itemActive: { backgroundColor: colors.bgActive },
  thumb: { width: 36, height: 28, borderRadius: 4, overflow: 'hidden' },
  iconCell: { display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: colors.fg3 },
  text: { minWidth: 0, display: 'flex', flexDirection: 'column', gap: 1 },
  sub: { fontSize: text.t12, color: colors.fg3 },
  meta: { fontSize: text.t12, color: colors.fg4, whiteSpace: 'nowrap' },
  empty: {
    paddingBlock: space.s5,
    paddingInline: space.s4,
    textAlign: 'center',
    color: colors.fg3,
    fontSize: text.t13
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
  error: { color: colors.fg2, lineHeight: 1.5 }
})
