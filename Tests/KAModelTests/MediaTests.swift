import Testing
@testable import KAModel

/// Port of `electron/tests/unit/media.test.ts`.
@Suite struct MediaTests {
  @Test func toMediaUrlEncodesSegmentsAndVersion() {
    #expect(toMediaUrl(root: "thumbs", relPath: "abc.png", version: 1) == "ka-media://local/thumbs/abc.png?v=1")
    #expect(toMediaUrl(root: "objects", relPath: "item-1/My File (final).pdf", version: 3) ==
      "ka-media://local/objects/item-1/My%20File%20(final).pdf?v=3")
    #expect(toMediaUrl(root: "content", relPath: "note.md", version: 0) == "ka-media://local/content/note.md?v=0")
  }

  @Test func toMediaUrlHandlesUnicodeEmptySegmentsAndOddVersions() {
    #expect(toMediaUrl(root: "objects", relPath: "x/Résumé – 2026.pdf", version: 2) ==
      "ka-media://local/objects/x/R%C3%A9sum%C3%A9%20%E2%80%93%202026.pdf?v=2")
    #expect(toMediaUrl(root: "snapshots", relPath: "a//b.jpg", version: 1) == "ka-media://local/snapshots/a/b.jpg?v=1")
    #expect(toMediaUrl(root: "snapshots", relPath: "/leading/slash.jpg", version: 1) ==
      "ka-media://local/snapshots/leading/slash.jpg?v=1")
    #expect(toMediaUrl(root: "thumbs", relPath: "a.png", version: -4) == "ka-media://local/thumbs/a.png?v=0")
    #expect(toMediaUrl(root: "thumbs", relPath: "a.png", version: 2.9) == "ka-media://local/thumbs/a.png?v=2")
  }

  @Test func parseRoundTrips() {
    for root in MEDIA_ROOTS {
      for rel in ["a.png", "item 1/My File (final).pdf", "x/Résumé – 2026.pdf", "deep/er/path/文件.md"] {
        let parsed = parseMediaUrl(toMediaUrl(root: root, relPath: rel, version: 7))
        #expect(parsed == ParsedMediaUrl(root: root, relPath: rel, version: 7), "\(root)/\(rel)")
      }
    }
  }

  @Test func parseDefaultsVersionAndIgnoresFragments() {
    #expect(parseMediaUrl("ka-media://local/thumbs/a.png") == ParsedMediaUrl(root: "thumbs", relPath: "a.png", version: 0))
    #expect(parseMediaUrl("ka-media://local/thumbs/a.png?v=4#x") ==
      ParsedMediaUrl(root: "thumbs", relPath: "a.png", version: 4))
    #expect(parseMediaUrl("ka-media://local/thumbs/a.png?other=1&v=9") ==
      ParsedMediaUrl(root: "thumbs", relPath: "a.png", version: 9))
  }

  @Test func parseRejectsUnknownSchemeHostRoot() {
    #expect(parseMediaUrl("file:///etc/passwd") == nil)
    #expect(parseMediaUrl("ka-media://remote/thumbs/a.png") == nil)
    #expect(parseMediaUrl("ka-media://local/models/a.onnx") == nil)
    #expect(parseMediaUrl("ka-media://local/library.db") == nil)
    #expect(parseMediaUrl("ka-media://local/") == nil)
  }

  @Test func parseRejectsTraversalBackslashesAbsolute() {
    for url in [
      "ka-media://local/thumbs",
      "ka-media://local/thumbs/",
      "ka-media://local/thumbs/../library.db",
      "ka-media://local/thumbs/%2e%2e/library.db",
      "ka-media://local/thumbs/a/./b.png",
      "ka-media://local/thumbs//etc/passwd",
      "ka-media://local/thumbs/%2Fetc%2Fpasswd",
      "ka-media://local/thumbs/a\\b.png",
      "ka-media://local/thumbs/a%5Cb.png",
      "ka-media://local/thumbs/a%00.png",
      "ka-media://local/thumbs/%E0%A4%A.png",
      "ka-media://local/thumbs/a.png?v=abc"
    ] {
      #expect(parseMediaUrl(url) == nil, Comment(rawValue: url))
    }
  }
}
