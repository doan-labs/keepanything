import {
  canonicalizeUrl,
  guessUrlSubtype,
  isMediaUrl,
  isSingleUrl,
  parseUriList,
  titleFromUrl
} from '../../../src/main/capture/url'
import { writeJson } from '../lib'

const URLS = [
  'https://www.Example.com/Path/?utm_source=x&b=2&a=1#frag',
  'https://youtu.be/abc123',
  'https://x.com/someone/status/1',
  'ftp://nope',
  'not a url',
  'mailto:a@b.c',
  'https://',
  'https://Example.com/x?utm_source=1',
  'https://youtube.com/shorts/xyz789',
  'https://youtube.com/watch?v=abc123&list=PL1&t=42',
  'https://music.youtube.com/watch?v=abc123',
  'https://github.com/vllm-project/vllm',
  'https://twitter.com/user/status/42?s=20&t=abc',
  'https://old.reddit.com/r/LocalLLaMA/comments/xyz/title/?rdt=1',
  'https://arxiv.org/abs/2309.06180v2',
  'https://example.com/paper.pdf',
  'https://a.b/c/image.PNG?x=1',
  'https://example.com:443/path/',
  'http://example.com:80/path/',
  'https://en.m.wikipedia.org/wiki/Transformer',
  'https://a.b/page#/spa/route',
  'https://google.com/search?q=vllm&utm_source=x',
  'HTTPS://EXAMPLE.COM/UPPER/Path',
  'https://example.com/a//b///c/',
  'https://example.com/index.html',
  'https://amazon.com/dp/B0XYZ/?ref_=nav_cs_gb&th=1',
  'https://example.com/path?keep=1&utm_medium=em&fbclid=zz'
]

export function exportUrl(): void {
  writeJson('url.json', {
    urls: URLS.map((url) => ({
      url,
      canonicalize: canonicalizeUrl(url),
      isMedia: isMediaUrl(url),
      isSingle: isSingleUrl(url),
      title: (() => {
        try {
          return titleFromUrl(new URL(url))
        } catch {
          return null
        }
      })(),
      guessSubtype: (() => {
        const c = canonicalizeUrl(url)
        if (!c) return null
        return guessUrlSubtype(c.domain, new URL(c.canonical).pathname)
      })()
    })),
    guessUrlSubtype: [
      ['youtube.com', '/watch'],
      ['docs.python.org', '/3'],
      ['github.com', '/vllm-project/vllm'],
      ['github.com', '/vllm-project/vllm/issues/1'],
      ['twitter.com', '/user'],
      ['arxiv.org', '/abs/2309.06180'],
      ['example.com', '/']
    ].map(([domain, path]) => ({ domain, path, subtype: guessUrlSubtype(domain as string, path as string) })),
    parseUriList: [
      '# comment\nhttps://a.b\n\nhttps://c.d\r\n',
      'https://a.b/one\n#note\nhttps://c.d/two',
      '',
      'no-newline'
    ].map((input) => ({ input, out: parseUriList(input) }))
  })
}
