import { classifyBytes, classifyFile, isScreenshotName, isTempPath } from '../../../src/main/capture/classify'
import { writeJson } from '../lib'

const FILE_CASES: [string, string | null][] = [
  ['photo.png', null],
  ['photo.jpg', 'image/jpeg'],
  ['Screenshot 2026-09-01 at 10.22.33.png', null],
  ['scan.heic', null],
  ['vector.svg', null],
  ['clip.mp4', null],
  ['movie.mov', 'video/quicktime'],
  ['track.mp3', null],
  ['voice.m4a', 'audio/mp4'],
  ['paper.pdf', null],
  ['document', 'application/pdf'],
  ['notes.md', null],
  ['readme.markdown', null],
  ['page.mdx', 'text/markdown'],
  ['log.txt', null],
  ['plainfile', 'text/plain'],
  ['report.docx', null],
  ['book.epub', null],
  ['sheet.xlsx', null],
  ['data.csv', null],
  ['slides.pptx', null],
  ['talk.key', null],
  ['archive.zip', null],
  ['backup.tar.gz', null],
  ['app.dmg', null],
  ['main.ts', null],
  ['script.py', 'application/octet-stream'],
  ['style.scss', null],
  ['Package.swift', null],
  ['data.json', null],
  ['export.yaml', null],
  ['db.sqlite', null],
  ['app.log', null],
  ['mystery.xyz', null],
  ['noext', 'application/octet-stream'],
  ['noext', null],
  ['photo', 'image/png'],
  ['recording', 'video/mp4'],
  ['song', 'audio/mpeg'],
  ['doc', 'text/markdown'],
  ['file', 'application/pdf'],
  ['upper.PNG', null],
  ['dotfile.', null]
]

const BYTE_CASES: { name: string; hex: string }[] = [
  { name: 'png', hex: '89504e470d0a1a0a0000000d49484452' },
  { name: 'jpeg', hex: 'ffd8ffe000104a4649460001' },
  { name: 'gif89', hex: '47494638396101000100' },
  { name: 'webp', hex: '52494646100000005745425056503820' },
  { name: 'pdf', hex: '255044462d312e370a25' },
  { name: 'bmp', hex: '424d4600000000000000' },
  { name: 'tiff-le', hex: '49492a0008000000' },
  { name: 'tiff-be', hex: '4d4d002a00000008' },
  { name: 'random', hex: '00010203040506070809' },
  { name: 'empty', hex: '' },
  { name: 'text', hex: '68656c6c6f20776f726c64' }
]

const hexToBytes = (hex: string): Uint8Array => new Uint8Array((hex.match(/.{2}/g) ?? []).map((b) => parseInt(b, 16)))

const TEMP_CASES = [
  '/tmp/x/a.png',
  '/tmp/x/sub/dir/a.png',
  '/tmp/y/a.png',
  '/private/var/folders/zz/abcdef/T/drag.png',
  '/Users/devin/TemporaryItems/shot.png',
  '/Users/devin/Pictures/photo.png',
  'relative/path.png'
]

const SCREENSHOT_NAMES = [
  'Screenshot 2026-09-01 at 10.22.33.png',
  'Screen Shot 2024-01-01 at 9.00.00 AM.png',
  'CleanShot 2026-08-30 at 14.03.22@2x.png',
  'simulator screen shot - iPhone 16 - 2026-08-01.png',
  'SCR-20240101.png',
  'bildschirmfoto 2026.png',
  '截屏2026-09-01.png',
  'スクリーンショット.png',
  'skjermbilde.png',
  'zrzut ekranu 2026.png',
  'IMG_1234.png',
  'photo of screen.png',
  'screenshot',
  'my screenshot.png',
  'screenshot.png'
]

export function exportClassify(): void {
  writeJson('classify.json', {
    classifyFile: FILE_CASES.map(([name, mime]) => ({ name, mime, out: classifyFile(name, mime) })),
    classifyBytes: BYTE_CASES.map((c) => ({ name: c.name, hex: c.hex, out: classifyBytes(hexToBytes(c.hex)) })),
    isTempPath: TEMP_CASES.map((p) => ({ path: p, tmpDir: '/tmp/x', out: isTempPath(p, '/tmp/x') })),
    isScreenshotName: SCREENSHOT_NAMES.map((n) => ({ name: n, out: isScreenshotName(n) }))
  })
}
