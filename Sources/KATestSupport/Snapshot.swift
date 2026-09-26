import Foundation
import GRDB
import KAModel
import KAStorage

/// Port of `electron/tests/scenarios/snapshot.ts`: the 9 tables dumped verbatim, plus the
/// determinism pass (`normalize`) the runner applies before comparing to the expected file.
/// `settings`/fake-call keys are not part of this snapshot — those are runner/E2E state.
public enum Snapshot {
  private static let tables: [(key: String, sql: String)] = [
    ("items", "SELECT * FROM items ORDER BY id"),
    ("fts", "SELECT * FROM items_fts ORDER BY item_id"),
    ("collections", "SELECT * FROM collections ORDER BY id"),
    ("collectionItems", "SELECT * FROM collection_items ORDER BY collection_id, item_id"),
    ("relationships", "SELECT * FROM relationships ORDER BY id"),
    ("suppressions", "SELECT * FROM suppressions ORDER BY kind, key"),
    ("audit", "SELECT * FROM audit_log ORDER BY id"),
    // Insertion order, not id: run ids are real UUIDs, so ordering by id scrambles every run.
    ("agentRuns", "SELECT * FROM agent_runs ORDER BY rowid"),
    ("jobs", "SELECT * FROM jobs ORDER BY id")
  ]

  /// Table keys in snapshot order, for callers that compare against the expected file.
  public static var tableKeys: [String] { tables.map(\.key) }

  /// node:sqlite returns INTEGER/REAL -> number, TEXT -> string, NULL -> null, BLOB -> Uint8Array
  /// (JSON.stringify emits `{ "0": byte, ... }`, which is what the expected file would contain).
  private static func jsonValue(_ v: DatabaseValue) -> JSONValue {
    switch v.storage {
    case .null: return .null
    case .int64(let i): return .number(Double(i))
    case .double(let d): return .number(d)
    case .string(let s): return .string(s)
    case .blob(let data):
      var o = [String: JSONValue]()
      for (i, b) in data.enumerated() { o["\(i)"] = .number(Double(b)) }
      return .object(o)
    }
  }

  private static func rowToJson(_ row: Row) -> JSONValue {
    var o = [String: JSONValue]()
    for (name, value) in zip(row.columnNames, row.databaseValues) {
      o[name] = jsonValue(value)
    }
    return .object(o)
  }

  public static func take(_ db: Db) throws -> JSONValue {
    try db.readOnly { d in
      var state = [String: JSONValue]()
      for t in tables {
        state[t.key] = try .array(Row.fetchAll(d, sql: t.sql).map(rowToJson))
      }
      return .object(state)
    }
  }

  private static let uuidRegex = try! NSRegularExpression(
    pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
  private static let tempSuffixRegex = try! NSRegularExpression(pattern: "ka-(scenario|keep)-[\\w-]+")
  private static let trailingSegmentRegex = try! NSRegularExpression(pattern: "-[A-Za-z0-9]+$")
  private static let timingRegex = try! NSRegularExpression(
    pattern: "\\\\?\"?(durationMs|latencyMs)\\\\?\":\\s*\\d+")

  /// Same rules as `normalizeDocument`: UUIDs -> uuid-N first-seen, path prefixes -> markers
  /// (longest first, including mid-string occurrences), mkdtemp suffixes -> -X, timings -> 0,
  /// and numeric pid/durationMs/latencyMs fields -> 0.
  public static func normalize(_ doc: JSONValue, prefixes: [(find: String, marker: String)]) -> JSONValue {
    var uuids = [String: Int]()
    let sorted = prefixes.sorted { $0.find.count > $1.find.count }

    func normalizeString(_ s: String) -> String {
      var v = s
      if uuidRegex.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)) != nil {
        if uuids[v] == nil { uuids[v] = uuids.count + 1 }
        return "uuid-\(uuids[v]!)"
      }
      for p in sorted {
        if v == p.find {
          v = p.marker
        } else if v.hasPrefix(p.find + "/") {
          v = p.marker + "/" + v.dropFirst(p.find.count + 1)
        } else if v.contains(p.find + "/") {
          v = v.replacingOccurrences(of: p.find + "/", with: p.marker + "/")
        }
      }
      v = tempSuffixRegex.replacingMatches(in: v) { whole, _ in
        let stripped = trailingSegmentRegex.stringByReplacingMatches(
          in: whole, range: NSRange(whole.startIndex..., in: whole), withTemplate: "")
        return stripped + "-X"
      }
      v = timingRegex.replacingMatches(in: v) { _, group in "\"\(group ?? "")\":0" }
      return v
    }

    func visit(_ value: JSONValue) -> JSONValue {
      switch value {
      case .string(let s): return .string(normalizeString(s))
      case .array(let a): return .array(a.map(visit))
      case .object(let o):
        var out = [String: JSONValue]()
        for (k, v) in o {
          if (k == "pid" || k == "durationMs" || k == "latencyMs"), case .number = v {
            out[k] = .number(0)
          } else {
            out[k] = visit(v)
          }
        }
        return .object(out)
      default: return value
      }
    }
    return visit(doc)
  }
}

private extension NSRegularExpression {
  /// Replace each match; `body` gets the whole match and first capture group (if any).
  func replacingMatches(in s: String, with body: (_ whole: String, _ group1: String?) -> String) -> String {
    let matches = matches(in: s, range: NSRange(s.startIndex..., in: s))
    var out = s
    for m in matches.reversed() {
      guard let whole = Range(m.range, in: out) else { continue }
      let group = m.numberOfRanges > 1 ? Range(m.range(at: 1), in: out).map { String(out[$0]) } : nil
      out.replaceSubrange(whole, with: body(String(out[whole]), group))
    }
    return out
  }
}
