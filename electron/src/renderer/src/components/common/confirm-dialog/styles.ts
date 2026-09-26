import * as stylex from '@stylexjs/stylex'
import { colors, motion, radii, shadows, space, text, weight, zIndex } from '../../../styles/tokens.stylex'

const rise = stylex.keyframes({ from: { opacity: 0, transform: 'translateY(6px)' } })

export const styles = stylex.create({
  scrim: {
    position: 'absolute',
    inset: 0,
    zIndex: zIndex.confirm,
    display: 'flex',
    alignItems: 'flex-start',
    justifyContent: 'center',
    paddingTop: '22vh',
    backgroundColor: colors.scrim
  },
  sheet: {
    width: 400,
    maxWidth: 'calc(100vw - 80px)',
    paddingTop: space.s5,
    paddingInline: space.s5,
    paddingBottom: space.s5,
    borderRadius: radii.r3,
    backgroundColor: colors.bg3,
    backdropFilter: 'blur(24px)',
    borderWidth: 1,
    borderStyle: 'solid',
    borderColor: colors.hairline,
    boxShadow: shadows.sheet,
    display: 'flex',
    flexDirection: 'column',
    gap: space.s3,
    outlineStyle: 'none',
    animationName: rise,
    animationDuration: motion.base,
    animationTimingFunction: motion.easeOut
  },
  title: { fontSize: text.t15, fontWeight: weight.medium },
  body: { fontSize: text.t13, color: colors.fg2, lineHeight: 1.5 },
  row: { display: 'flex', justifyContent: 'flex-end', gap: space.s2, marginTop: space.s2 }
})
