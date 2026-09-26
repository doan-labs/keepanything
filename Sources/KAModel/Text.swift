import Foundation

/// Pure text helpers used on both sides of the bridge (port of `electron/src/shared/text.ts`).

/// JS `Math.round` semantics: .5 rounds towards +∞ (half away from zero for positives).
private func jsRound(_ x: Double) -> Double {
  (x + 0.5).rounded(.down)
}

/// Shorten `s` to at most `n` characters, appending `…` when cut.
public func truncate(_ s: String, _ n: Int) -> String {
  if n <= 0 { return "" }
  if s.count <= n { return s }
  if n == 1 { return "…" }
  return String(s.prefix(n - 1)).trimmingCharacters(in: .whitespaces) + "…"
}

/// URL/file-safe slug: lowercase ASCII letters, digits and single dashes.
public func slugify(_ s: String) -> String {
  // JS `normalize('NFKD')` then strip combining marks, lowercase, non-alphanumeric runs -> '-'.
  let decomposed = s.decomposedStringWithCompatibilityMapping
  let noMarks = decomposed.unicodeScalars.filter { !(0x0300 ... 0x036F).contains($0.value) }
  let lowered = String(String.UnicodeScalarView(noMarks)).lowercased()
  return lowered
    .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
    .replacingOccurrences(of: #"^-+|-+$"#, with: "", options: .regularExpression)
}

/// Normalized comparison key for names (`collections.name_key`): lowercase, punctuation and
/// symbols removed, whitespace collapsed, trimmed.
public func normalizeName(_ name: String) -> String {
  // JS `normalize('NFKC')` → precomposedStringWithCompatibilityMapping; `\p{P}\p{S}` → NSRegularExpression.
  let normalized = name.precomposedStringWithCompatibilityMapping.lowercased()
  let stripped = normalized.replacingOccurrences(
    of: #"[\p{P}\p{S}]+"#, with: " ", options: .regularExpression
  )
  return stripped
    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    .trimmingCharacters(in: .whitespaces)
}

private let MINUTE = 60_000.0
private let HOUR = 60 * MINUTE
private let DAY = 24 * HOUR
private let WEEK = 7 * DAY
private let MONTH = 30 * DAY
private let YEAR = 365 * DAY

/// JS `Date.parse` for the ISO forms the app writes; anything else is nil.
/// (ISO8601DateFormatter is not Sendable, so it lives per-call rather than as a global.)
private func parseIsoMs(_ iso: String) -> Double? {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f.date(from: iso).map { $0.timeIntervalSince1970 * 1000 }
}

/// Human relative time ("just now", "3 weeks ago"). Future or invalid dates read as "just now".
public func relativeTime(iso: String, nowIso: String) -> String {
  guard let then = parseIsoMs(iso), let now = parseIsoMs(nowIso) else { return "just now" }
  let diff = now - then
  if diff < 45_000 { return "just now" }
  if diff < 90_000 { return "1 minute ago" }
  if diff < 45 * MINUTE { return "\(Int(jsRound(diff / MINUTE))) minutes ago" }
  if diff < 90 * MINUTE { return "1 hour ago" }
  if diff < 22 * HOUR { return "\(Int(jsRound(diff / HOUR))) hours ago" }
  if diff < 36 * HOUR { return "yesterday" }
  if diff < WEEK { return "\(Int(jsRound(diff / DAY))) days ago" }
  if diff < 11 * DAY { return "1 week ago" }
  if diff < 30 * DAY { return "\(Int(jsRound(diff / WEEK))) weeks ago" }
  if diff < 45 * DAY { return "1 month ago" }
  if diff < 320 * DAY { return "\(Int(jsRound(diff / MONTH))) months ago" }
  if diff < 548 * DAY { return "1 year ago" }
  return "\(Int(jsRound(diff / YEAR))) years ago"
}

private let BYTE_UNITS = ["B", "KB", "MB", "GB", "TB"]

/// Decimal (1000-based, like Finder) size string: "0 B", "12 KB", "2.4 MB".
public func formatBytes(_ bytes: Double) -> String {
  if !bytes.isFinite || bytes < 0 { return "0 B" }
  if bytes < 1000 { return "\(Int(jsRound(bytes))) B" }
  var value = bytes
  var unit = 0
  while value >= 1000, unit < BYTE_UNITS.count - 1 {
    value /= 1000
    unit += 1
  }
  // JS `toFixed` rounds half away from zero at the last digit.
  let text = value >= 100 || value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
  return "\(text) \(BYTE_UNITS[unit])"
}

/// Media duration as `m:ss` or `h:mm:ss`.
public func formatDuration(_ ms: Double) -> String {
  if !ms.isFinite || ms < 0 { return "0:00" }
  let total = Int(jsRound(ms / 1000))
  let hours = total / 3600
  let minutes = (total % 3600) / 60
  let seconds = total % 60
  func two(_ n: Int) -> String { String(format: "%02d", n) }
  return hours > 0 ? "\(hours):\(two(minutes)):\(two(seconds))" : "\(minutes):\(two(seconds))"
}

private let QUESTION_WORDS: Set<String> = [
  "what", "which", "where", "when", "who", "whose", "whom", "how", "why", "show", "find", "list",
  "tell", "did", "do", "does", "is", "are", "was", "were", "can", "could", "should", "would",
  "have", "has"
]

/// ≥ 4 words, starts with a question word, or ends with `?` (drives the "Ask" row).
public func isProbablyNaturalLanguage(_ query: String) -> Bool {
  let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty { return false }
  if trimmed.hasSuffix("?") { return true }
  let words = tokenize(trimmed)
  if words.count >= 4 { return true }
  return words.first.map { QUESTION_WORDS.contains($0) } ?? false
}

/// Lowercase alphanumeric tokens, Unicode-aware (letters and digits of any script).
/// JS `match(/[\p{L}\p{N}]+/gu)` — NSRegularExpression supports the same properties.
public func tokenize(_ s: String) -> [String] {
  let lowered = s.lowercased()
  let pattern = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
  let range = NSRange(lowered.startIndex..., in: lowered)
  return pattern.matches(in: lowered, range: range).compactMap { m in
    guard let r = Range(m.range, in: lowered) else { return nil }
    let t = String(lowered[r])
    return t.isEmpty ? nil : t
  }
}
