import { createReadStream, existsSync, statSync } from 'node:fs'
import { createServer, type Server } from 'node:http'
import { extname, join, normalize } from 'node:path'

const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.json': 'application/json',
  '.pdf': 'application/pdf',
  '.txt': 'text/plain; charset=utf-8',
  '.png': 'image/png',
  '.xml': 'application/xml'
}

export interface FixtureServer {
  /** `http://127.0.0.1:<port>` */
  baseUrl: string
  close(): void
}

/**
 * Static file server bound to 127.0.0.1 on a random port. Serves `tests/fixtures/html/` at `/`
 * (a `.json` file under it acts as a stub). Anything missing answers 404 so the extraction
 * failure path is exercised deterministically.
 */
export async function startFixtureServer(root: string): Promise<FixtureServer> {
  const server: Server = createServer((req, res) => {
    const path = decodeURIComponent(new URL(req.url ?? '/', 'http://x').pathname)
    const file = normalize(join(root, path))
    if (!file.startsWith(normalize(root)) || !existsSync(file) || !statSync(file).isFile()) {
      res.writeHead(404, { 'content-type': 'text/plain' })
      res.end('not found')
      return
    }
    res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' })
    createReadStream(file).pipe(res)
  })
  await new Promise<void>((resolveListen) => server.listen(0, '127.0.0.1', resolveListen))
  const address = server.address()
  const port = typeof address === 'object' && address ? address.port : 0
  return { baseUrl: `http://127.0.0.1:${port}`, close: () => server.close() }
}

/**
 * `fetch` replacement for the scenario runner: rewrites `http://fixture/…` onto the fixture
 * server; any other host throws (the network is unreachable in scenarios, deterministically).
 */
export function fixtureFetchImpl(server: FixtureServer): typeof fetch {
  return (async (input: unknown, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : (input as { url: string }).url
    const parsed = new URL(url)
    if (parsed.hostname !== 'fixture')
      throw new TypeError(`fetch failed: host ${parsed.hostname} is not the fixture server`)
    const rewritten = `${server.baseUrl}${parsed.pathname}${parsed.search}`
    return fetch(rewritten, init)
  }) as typeof fetch
}
