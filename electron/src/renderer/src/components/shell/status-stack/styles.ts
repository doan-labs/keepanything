import * as stylex from '@stylexjs/stylex'
import { colors, motion, radii, shadows, space, text, zIndex } from '../../../styles/tokens.stylex'

const rise = stylex.keyframes({
  from: { opacity: 0, transform: 'translateY(6px)' },
  to: { opacity: 1, transform: 'none' }
})

export const styles = stylex.create({
  stack: {
    position: 'fixed',
    right: space.s5,
    bottom: space.s5,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'flex-end',
    gap: space.s2,
    zIndex: zIndex.status,
    pointerEvents: 'none'
  },
  live: {
    pointerEvents: 'auto',
    display: 'inline-flex',
    alignItems: 'center',
    gap: space.s2,
    maxWidth: 300,
    paddingTop: 7,
    paddingBottom: 7,
    paddingLeft: 12,
    paddingRight: 12,
    borderRadius: radii.r3,
    backgroundColor: colors.bg3,
    backdropFilter: 'blur(24px)',
    borderWidth: 1,
    borderStyle: 'solid',
    borderColor: { default: colors.hairline, ':hover': colors.hairlineStrong },
    boxShadow: shadows.pop,
    color: { default: colors.fg2, ':hover': colors.fg1 },
    fontSize: text.t12,
    animationName: rise,
    animationDuration: motion.base,
    animationTimingFunction: motion.easeOut
  }
})
