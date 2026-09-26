/**
 * The Doan lab mark: a half disc, a ring, a triangle and a tilted square on a 24-unit grid, read
 * as D O A N. Transcribed from `doan-labs.com/public/doan-mark.svg`, the handoff file, where the
 * ring and square are outlined rather than stroked so the weight survives any size. Change it
 * there first.
 */
export function DoanMark({ size = 14 }: { size?: number }): React.JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M5.6 3.4A4.1 4.1 0 0 1 5.6 11.6Z" />
      <path d="M21 7.5A4.5 4.5 0 1 1 12 7.5A4.5 4.5 0 1 1 21 7.5ZM19.2 7.5A2.7 2.7 0 1 0 13.8 7.5A2.7 2.7 0 1 0 19.2 7.5Z" />
      <path d="M7.5 12.9L3.5 20.1L11.5 20.1Z" />
      <path d="M16.5 11.586L21.414 16.5L16.5 21.414L11.586 16.5ZM16.5 14.061L14.061 16.5L16.5 18.939L18.939 16.5Z" />
    </svg>
  )
}
