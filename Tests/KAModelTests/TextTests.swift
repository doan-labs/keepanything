import Testing
@testable import KAModel

/// Port of `electron/tests/unit/text.test.ts`.
@Suite struct TextTests {
  @Test func truncateShortens() {
    #expect(truncate("hello", 10) == "hello")
    #expect(truncate("hello", 5) == "hello")
    #expect(truncate("hello world", 6) == "hello…")
    #expect(truncate("hello world", 1) == "…")
    #expect(truncate("hello", 0) == "")
  }

  @Test func slugifyProducesLowercaseAscii() {
    #expect(slugify("mnismt — Visual Direction!") == "mnismt-visual-direction")
    #expect(slugify("  Résumé 2026.pdf ") == "resume-2026-pdf")
    #expect(slugify("---") == "")
  }

  @Test func normalizeNameStripsPunctuation() {
    #expect(normalizeName("  mnismt:  Visual   Direction!! ") == "mnismt visual direction")
    #expect(normalizeName("Inference-Research") == "inference research")
    #expect(normalizeName("Things to Read") == normalizeName("things   to read"))
    #expect(normalizeName("Ｍacos Apps") == "macos apps")
  }

  @Test func relativeTimeReadsHuman() {
    let now = "2026-09-03T12:00:00.000Z"
    #expect(relativeTime(iso: now, nowIso: now) == "just now")
    // Full sweep lives in the parity test against text.json.
    #expect(relativeTime(iso: "not a date", nowIso: now) == "just now")
    #expect(relativeTime(iso: "2027-01-01T00:00:00.000Z", nowIso: now) == "just now")
  }

  @Test func formatBytesFormatsSizes() {
    #expect(formatBytes(0) == "0 B")
    #expect(formatBytes(512) == "512 B")
    #expect(formatBytes(12_300) == "12.3 KB")
    #expect(formatBytes(2_400_000) == "2.4 MB")
    #expect(formatBytes(150_000_000) == "150 MB")
    #expect(formatBytes(3_000_000_000) == "3 GB")
    #expect(formatBytes(-1) == "0 B")
  }

  @Test func formatDurationFormats() {
    #expect(formatDuration(0) == "0:00")
    #expect(formatDuration(65_000) == "1:05")
    #expect(formatDuration(3_725_000) == "1:02:05")
    #expect(formatDuration(.nan) == "0:00")
  }

  @Test func isProbablyNaturalLanguageDetects() {
    #expect(!isProbablyNaturalLanguage("minimax"))
    #expect(!isProbablyNaturalLanguage("hyperliquid docs"))
    #expect(!isProbablyNaturalLanguage("github repo"))
    #expect(isProbablyNaturalLanguage("what am I researching here?"))
    #expect(isProbablyNaturalLanguage("find that mac app"))
    #expect(isProbablyNaturalLanguage("the website with the globe animation"))
    #expect(isProbablyNaturalLanguage("minimax?"))
    #expect(!isProbablyNaturalLanguage("   "))
  }

  @Test func tokenizeSplitsLowercasesKeepsUnicode() {
    #expect(tokenize("Hello, World! 42") == ["hello", "world", "42"])
    #expect(tokenize("Résumé_naïve — 文件") == ["résumé", "naïve", "文件"])
    #expect(tokenize("").isEmpty)
  }
}
