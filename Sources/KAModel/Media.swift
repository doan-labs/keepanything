import Foundation

/// `ka-media://` URL construction and parsing (port of `electron/src/shared/media.ts`).

/// Library directories that may be served over `ka-media://`.
public let MEDIA_ROOTS: [String] = ["objects", "thumbs", "snapshots", "content"]

public struct ParsedMediaUrl: Sendable, Equatable {
  public init(root: String, relPath: String, version: Int) {
    self.root = root
    self.relPath = relPath
    self.version = version
  }

  public var root: String
  /// Decoded path relative to the root directory, forward slashes, no empty or `..` segments.
  public var relPath: String
  /// Cache-busting version (`?v=`); 0 when absent.
  public var version: Int
}

private let HOST = "local"
private let PREFIX = "\(MEDIA_SCHEME)://\(HOST)/"

public func isMediaRoot(_ value: String) -> Bool { MEDIA_ROOTS.contains(value) }

/// JS `encodeURIComponent`: escapes everything except `A-Za-z0-9-_.!~*'()`.
/// (`addingPercentEncoding` differs — `.` and `*` handling aside, the unreserved sets differ.)
private func encodeURIComponent(_ s: String) -> String {
  let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
  var out = ""
  for byte in s.utf8 {
    let c = Unicode.Scalar(byte)
    if unreserved.contains(Character(c)) {
      out.append(Character(c))
    } else {
      out += String(format: "%%%02X", byte)
    }
  }
  return out
}

/// Build `ka-media://local/<root>/<segments...>?v=<version>`. Each path segment is
/// `encodeURIComponent`-ed; empty segments are dropped. `relPath` must be relative.
public func toMediaUrl(root: String, relPath: String, version: Double) -> String {
  let segments = relPath
    .split(separator: "/", omittingEmptySubsequences: true)
    .map { encodeURIComponent(String($0)) }
  let v = version.isFinite && version >= 0 ? Int(version.rounded(.down)) : 0
  return "\(PREFIX)\(root)/\(segments.joined(separator: "/"))?v=\(v)"
}

/// JS `decodeURIComponent`: nil on malformed escapes / invalid UTF-8.
private func decodeSegment(_ segment: String) -> String? {
  segment.removingPercentEncoding
}

/// Parse a `ka-media://` URL. Returns nil for anything that must not be served: unknown scheme or
/// host, unknown root, empty path, empty / `.` / `..` segments, backslashes, absolute paths, or
/// undecodable escapes.
public func parseMediaUrl(_ url: String) -> ParsedMediaUrl? {
  guard url.hasPrefix(PREFIX) else { return nil }
  let rest = String(url.dropFirst(PREFIX.count))

  let withoutHash = rest.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
  let pathAndQuery = withoutHash.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
  let pathPart = String(pathAndQuery[0])
  let query = pathAndQuery.count > 1 ? String(pathAndQuery[1]) : ""

  if pathPart.contains("\\") { return nil }

  var split = pathPart.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
  guard let rootRaw = split.first, isMediaRoot(rootRaw) else { return nil }
  split.removeFirst()
  guard !split.isEmpty else { return nil }

  var decoded: [String] = []
  for encoded in split {
    guard let segment = decodeSegment(encoded) else { return nil }
    if segment.isEmpty || segment == "." || segment == ".." { return nil }
    if segment.contains("/") || segment.contains("\\") || segment.contains("\0") { return nil }
    decoded.append(segment)
  }

  var version = 0
  if !query.isEmpty {
    let pattern = try! NSRegularExpression(pattern: #"(?:^|&)v=([^&]*)"#)
    if let m = pattern.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
       let r = Range(m.range(at: 1), in: query) {
      let raw = String(query[r])
      guard raw.range(of: #"^\d+$"#, options: .regularExpression) != nil, let v = Int(raw) else { return nil }
      version = v
    }
  }

  return ParsedMediaUrl(root: rootRaw, relPath: decoded.joined(separator: "/"), version: version)
}
