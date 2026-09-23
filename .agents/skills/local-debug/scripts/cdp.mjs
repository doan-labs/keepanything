#!/usr/bin/env node
// Drives the live dev window over CDP; start dev with `pnpm run dev --remoteDebuggingPort 9222` first.
//
// Usage: node .agents/skills/local-debug/scripts/cdp.mjs <command> [args]
//   shot [out]                screenshot the window (default .artifacts/live.png)
//   snap                      accessibility tree of the window (roles, names, states)
//   console [seconds]         stream console messages and page errors (default 10)
//   invoke <channel> [json]   call an IPC channel through the preload bridge, print the envelope
//   eval <expression>         evaluate JS in the renderer, print the result as JSON
//
// KA_CDP_PORT (default 9222), KA_VIEW=library|shelf (default library).
// invoke on a channel outside READ_CHANNELS, and eval, need KA_WRITE=1: they can change the library.

import { mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { chromium } from '@playwright/test'

const READ_CHANNELS = new Set([
  'items:list',
  'items:get',
  'items:readContent',
  'collections:list',
  'search:quick',
  'agent:run',
  'agent:runs',
  'settings:get',
  'system:stats',
  'system:updateStatus',
  'jobs:status'
])

const [cmd, ...args] = process.argv.slice(2)
const port = process.env.KA_CDP_PORT ?? '9222'
const view = process.env.KA_VIEW ?? 'library'

const fail = (message) => {
  console.error(message)
  process.exit(1)
}
const needsWrite = (what) => {
  if (process.env.KA_WRITE !== '1') fail(`${what} can change the library: ask first, then rerun with KA_WRITE=1`)
}

if (!['shot', 'snap', 'console', 'invoke', 'eval'].includes(cmd)) fail('usage: cdp.mjs shot|snap|console|invoke|eval')
if (cmd === 'eval') needsWrite('eval')
if (cmd === 'invoke' && !READ_CHANNELS.has(args[0])) needsWrite(`invoke ${args[0]}`)

const browser = await chromium
  .connectOverCDP(`http://127.0.0.1:${port}`)
  .catch(() => fail(`nothing on CDP port ${port}: restart dev with \`pnpm run dev --remoteDebuggingPort ${port}\``))
const pages = browser.contexts().flatMap((c) => c.pages())
const page = pages.find((p) => URL.canParse(p.url()) && new URL(p.url()).searchParams.get('view') === view)
if (!page) fail(`no ${view} window; open pages: ${pages.map((p) => p.url()).join(', ') || 'none'}`)

switch (cmd) {
  case 'shot': {
    const out = resolve(args[0] ?? '.artifacts/live.png')
    mkdirSync(dirname(out), { recursive: true })
    await page.screenshot({ path: out })
    console.log(out)
    break
  }
  case 'snap':
    console.log(await page.locator('body').ariaSnapshot())
    break
  case 'console':
    page.on('console', (m) => console.log(`[${m.type()}] ${m.text()}`))
    page.on('pageerror', (e) => console.log(`[pageerror] ${e.message}`))
    await page.waitForTimeout(Number(args[0] ?? 10) * 1000)
    break
  case 'invoke': {
    const payload = args[1] === undefined ? undefined : JSON.parse(args[1])
    const envelope = await page.evaluate(([c, p]) => window.keepAnything.invoke(c, p), [args[0], payload])
    console.log(JSON.stringify(envelope, null, 2))
    break
  }
  case 'eval':
    console.log(JSON.stringify(await page.evaluate(args.join(' ')), null, 2))
    break
}
// Exit without browser.close(): on a CDP connection that can quit the app itself.
process.exit(0)
