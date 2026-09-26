/**
 * Captures every surface in Tests/Fixtures/design/surfaces.json with the real Electron app, in both
 * themes at 1440×900, into Tests/Fixtures/design/reference/<id>.<theme>.png plus manifest.json.
 * Reference images for the Swift rewrite (docs/swift_rewrite/PLAN.md "Keeping the design"); the
 * `design-reference` workflow job (workflow_dispatch only) or a developer Mac regenerates them when
 * the Electron UI changes. macOS only — Linux lacks the SF fonts.
 *
 * Requires a built app (`pnpm run build`). The library is the `design-seed` scenario's, replayed by
 * the E-05 scenario runner into the E2E profile dir (KEEPANYTHING_E2E=1 -> <tmp>/keepanything-e2e).
 *
 * Usage:
 *   node scripts/capture-references.mjs                 capture all surfaces, both themes
 *   node scripts/capture-references.mjs --check         validate surfaces.json + reference/ files only
 *   node scripts/capture-references.mjs --surface <id>  one surface
 *   node scripts/capture-references.mjs --theme dark    one theme (dark|light)
 */

import { execFileSync } from 'node:child_process'
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { _electron as electron } from '@playwright/test'

const here = dirname(fileURLToPath(import.meta.url))
const electronDir = resolve(here, '..')
const designDir = resolve(electronDir, '../Tests/Fixtures/design')
const surfacesPath = join(designDir, 'surfaces.json')
const referenceDir = join(designDir, 'reference')
const manifestPath = join(referenceDir, 'manifest.json')
const appBundle = join(electronDir, 'out/main/index.js')
const e2eProfile = join(tmpdir(), 'keepanything-e2e')
const seedDir = join(tmpdir(), 'ka-design-seed')
const THEMES = ['dark', 'light']
const WINDOW = { width: 1440, height: 900 }

const args = process.argv.slice(2)
const option = (name) => {
  const i = args.indexOf(name)
  return i >= 0 && args[i + 1] ? args[i + 1] : null
}

/** ---- --check mode: no Electron, pure file validation ------------------------------------ */

function check() {
  const errors = []
  const doc = JSON.parse(readFileSync(surfacesPath, 'utf8'))
  const surfaces = doc.surfaces ?? []
  const ids = new Set()
  for (const s of surfaces) {
    if (!s.id || !/^[a-z0-9-]+$/.test(s.id)) errors.push(`bad id: ${JSON.stringify(s.id)}`)
    if (ids.has(s.id)) errors.push(`duplicate id: ${s.id}`)
    ids.add(s.id)
    if (!Array.isArray(s.steps) || s.steps.length === 0) errors.push(`${s.id}: no steps`)
  }
  const manifest = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8')) : null
  if (!manifest) errors.push('missing manifest.json')
  const expected = []
  for (const s of surfaces) for (const t of THEMES) expected.push(`${s.id}.${t}.png`)
  for (const f of expected) {
    if (!existsSync(join(referenceDir, f))) errors.push(`missing reference/${f}`)
  }
  if (manifest) {
    const have = new Set((manifest.surfaces ?? []).map((m) => m.file))
    for (const f of expected) if (!have.has(f)) errors.push(`manifest missing ${f}`)
    for (const f of have) if (!expected.includes(f)) errors.push(`manifest extra ${f}`)
    for (const m of manifest.surfaces ?? []) {
      if (m.width !== WINDOW.width || m.height !== WINDOW.height)
        errors.push(`${m.file}: manifest size ${m.width}x${m.height} != ${WINDOW.width}x${WINDOW.height}`)
    }
    if (manifest.capturedAt !== undefined) errors.push('manifest.capturedAt must not be recorded')
  }
  if (errors.length) {
    console.error(`capture-references --check failed:\n  ${errors.join('\n  ')}`)
    process.exit(1)
  }
  console.log(`check ok: ${surfaces.length} surfaces x ${THEMES.length} themes, manifest consistent`)
  process.exit(0)
}

/** ---- seeding + launch ------------------------------------------------------------------- */

function buildSeedLibrary() {
  // Replay the design-seed scenario with KEEPANYTHING_KEEP_LIBRARY pointing at a scratch dir, then
  // copy the finished library over the E2E profile the app will open.
  rmSync(seedDir, { recursive: true, force: true })
  execFileSync('pnpm', ['exec', 'vitest', 'run', 'tests/scenarios/run.test.ts'], {
    cwd: electronDir,
    env: {
      ...process.env,
      KEEPANYTHING_SCENARIOS: '1',
      KEEPANYTHING_KEEP_LIBRARY: seedDir,
      KA_SCENARIO: 'design-seed'
    },
    stdio: 'inherit'
  })
  const seeded = join(seedDir, 'design-seed')
  if (!existsSync(seeded)) throw new Error(`scenario runner did not produce ${seeded}`)
  rmSync(e2eProfile, { recursive: true, force: true })
  mkdirSync(dirname(e2eProfile), { recursive: true })
  cpSync(seeded, e2eProfile, { recursive: true })
  // The keep copy still holds the lock file the scenario runner took; the app must own it fresh.
  rmSync(join(e2eProfile, 'library.lock'), { force: true })
}

async function launch({ empty }) {
  if (empty) rmSync(e2eProfile, { recursive: true, force: true })
  const app = await electron.launch({
    args: [appBundle],
    env: { ...process.env, KEEPANYTHING_E2E: '1', KEEPANYTHING_AI: 'mock' }
  })
  const page = await app.firstWindow()
  await page.waitForLoadState('domcontentloaded')
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.waitForTimeout(1500)
  await app.evaluate(({ BrowserWindow }, size) => {
    const win = BrowserWindow.getAllWindows()[0]
    win.setSize(size.width, size.height)
    win.center()
  }, WINDOW)
  return { app, page }
}

async function setTheme(page, theme) {
  await page.evaluate((t) => window.keepAnything.invoke('settings:update', { theme: t }), theme)
  await page.waitForTimeout(300)
}

/** Close any open modal (palette, detail, settings, dialog) before the next surface. */
async function resetState(page, app) {
  // The shelf survives Escape and theme switches; hide it again via the same menu toggle.
  if (app) {
    const shelfVisible = await app
      .evaluate(({ BrowserWindow }) =>
        BrowserWindow.getAllWindows().some((w) => w.isVisible() && w.webContents.getURL().includes('view=shelf'))
      )
      .catch(() => false)
    if (shelfVisible)
      await app
        .evaluate(({ Menu }) => {
          const walk = (items) => items.flatMap((i) => [i, ...(i.submenu ? walk(i.submenu.items) : [])])
          walk(Menu.getApplicationMenu()?.items ?? [])
            .find((i) => i.label === 'Toggle Shelf')
            ?.click()
        })
        .catch(() => {})
  }
  await page.keyboard.press('Escape')
  await page.waitForTimeout(150)
  await page.keyboard.press('Escape')
  await page.waitForTimeout(150)
  // The settings sheet ignores Escape; close it via its own button.
  const closeSettings = page.getByRole('button', { name: 'Close settings' }).first()
  if (await closeSettings.isVisible().catch(() => false)) {
    await closeSettings.click().catch(() => {})
    await page.waitForTimeout(200)
  }
  // Palette/dialogs close on Escape; the section may have changed — go back to the library.
  // (The sidebar row's accessible name carries the item count, so role-name matching misses it.)
  const lib = page.locator('nav[aria-label="Library"] > div:nth-child(2) > button').first()
  if (await lib.isVisible().catch(() => false)) {
    await lib.click().catch(() => {})
    await page.waitForTimeout(200)
  }
}

/** ---- step interpreter ------------------------------------------------------------------- */

async function runSteps(ctx, steps) {
  let shot = null
  for (const step of steps) {
    if (step.empty) {
      ctx.empty = true
      continue
    }
    if (step.wait) await ctx.page.waitForTimeout(step.wait)
    if (step.press) await ctx.page.keyboard.press(step.press)
    if (step.type) await ctx.page.keyboard.type(step.type, { delay: 10 })
    if (step.click) {
      const c = step.click
      const target = c.selector
        ? ctx.page.locator(c.selector).first()
        : ctx.page.getByRole(c.role, { name: c.name }).first()
      await target.click({ modifiers: c.modifiers ?? [] })
    }
    if (step.dblclick) await ctx.page.locator(step.dblclick.selector).first().dblclick()
    if (step.select)
      await ctx.page.locator(`select:has(option[value='${step.select.value}'])`).first().selectOption(step.select.value)
    if (step.scroll)
      await ctx.page
        .getByRole('region', { name: step.scroll.region, exact: true })
        .evaluate((el) => el.scrollIntoView({ block: 'start' }))
    if (step.invoke)
      await ctx.page.evaluate(
        ([ch, p]) => window.keepAnything.invoke(ch, p),
        [step.invoke.channel, step.invoke.payload ?? undefined]
      )
    if (step.evaluate) await ctx.page.evaluate(step.evaluate)
    if (step.menu) {
      await ctx.app.evaluate(({ Menu }, label) => {
        const walk = (items) => items.flatMap((i) => [i, ...(i.submenu ? walk(i.submenu.items) : [])])
        const item = walk(Menu.getApplicationMenu()?.items ?? []).find((i) => i.label === label)
        if (!item) throw new Error(`menu item not found: ${label}`)
        item.click()
      }, step.menu)
    }
    if (step.window === 'shelf') {
      // Wait for the shelf BrowserWindow's page to appear, then swap the capture target.
      const deadline = Date.now() + 5000
      let shelfPage = null
      while (Date.now() < deadline) {
        shelfPage = ctx.app.windows().find((w) => w.url().includes('view=shelf'))
        if (shelfPage) break
        await new Promise((r) => setTimeout(r, 200))
      }
      if (!shelfPage) throw new Error('shelf window never appeared')
      await shelfPage.waitForLoadState('domcontentloaded')
      ctx.page = shelfPage
    }
    if (step.shot) shot = step.shot
  }
  return shot
}

/** ---- main ------------------------------------------------------------------------------- */

async function main() {
  const onlySurface = option('--surface')
  const onlyTheme = option('--theme')
  const doc = JSON.parse(readFileSync(surfacesPath, 'utf8'))
  let surfaces = doc.surfaces
  if (onlySurface) surfaces = surfaces.filter((s) => s.id === onlySurface)
  const themes = onlyTheme ? [onlyTheme] : THEMES
  if (!existsSync(appBundle)) throw new Error('out/main/index.js missing — run `pnpm run build` first')
  if (surfaces.length === 0) throw new Error(`no surfaces match --surface ${onlySurface}`)

  mkdirSync(referenceDir, { recursive: true })
  buildSeedLibrary()

  const manifest = { surfaces: [] }
  const electronVersion = JSON.parse(
    readFileSync(join(electronDir, 'node_modules/electron/package.json'), 'utf8')
  ).version

  // Empty-profile surfaces run in a second launch against a wiped profile.
  for (const group of [
    surfaces.filter((s) => !s.steps.some((st) => st.empty)),
    surfaces.filter((s) => s.steps.some((st) => st.empty))
  ]) {
    if (group.length === 0) continue
    const { app, page } = await launch({ empty: group[0].steps.some((st) => st.empty) })
    try {
      for (const theme of themes) {
        await setTheme(page, theme)
        for (const surface of group) {
          // Surfaces don't carry their own cleanup across a theme switch: reset first.
          await resetState(page, app)
          const ctx = { app, page }
          let shot
          try {
            shot = await runSteps(ctx, surface.steps)
          } catch (err) {
            // Leave the on-screen state behind for debugging a step that cannot run.
            await page.screenshot({ path: join(referenceDir, `debug-${surface.id}.${theme}.png`) }).catch(() => {})
            throw err
          }
          const file = `${surface.id}.${theme}.png`
          const target = shot?.element ? ctx.page.locator(shot.element).first() : ctx.page
          await target.screenshot({ path: join(referenceDir, file), timeout: 10000 })
          const shotPage = ctx.page
          manifest.surfaces.push({ id: surface.id, theme, file, width: WINDOW.width, height: WINDOW.height })
          console.log(`${file} <- ${surface.title}`)
          await resetState(page, app)
          ctx.page = shotPage === page ? page : shotPage
        }
      }
    } finally {
      await app.close()
    }
  }

  manifest.surfaces.sort((a, b) => (a.id + a.theme < b.id + b.theme ? -1 : 1))
  manifest.electronVersion = electronVersion
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)
  console.log(`wrote ${manifestPath} (${manifest.surfaces.length} captures)`)
}

if (args.includes('--check')) check()
else await main()
