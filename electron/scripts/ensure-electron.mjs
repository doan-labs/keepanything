/**
 * pnpm only runs the `electron` postinstall (which downloads the binary) once its build
 * script is approved via pnpm-workspace.yaml. This guard makes a fresh clone self-heal.
 */

import { execSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { resolve } from 'node:path'

const electronDir = resolve(process.cwd(), 'node_modules/electron')
// Delegate the "is it there?" check to install.js: it exits 0 when the binary is present and
// re-extracts when it is not. Gating on `dist/` alone missed a half-extracted dist (licences
// unzipped, no Electron.app), which only surfaced as an ENOENT spawn at dev time.
if (existsSync(electronDir)) {
  execSync('node install.js', { cwd: electronDir, stdio: 'inherit' })
}
