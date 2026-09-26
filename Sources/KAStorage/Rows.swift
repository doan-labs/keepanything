import Foundation
import GRDB

/// Port of `storage/repositories/rows.ts`. Values are `DatabaseValue` off a GRDB `Row`
/// (`row["col"]`); schema drift surfaces through `requireText`.

/// Parse a JSON text column, returning `fallback` on null/invalid input.
func parseJson<T: Decodable>(_ value: DatabaseValue?, _ fallback: T) -> T {
  guard let s = text(value), !s.isEmpty, let data = s.data(using: .utf8) else { return fallback }
  return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
}

/// Parse a JSON string array column. Non-string entries are dropped.
func parseStringArray(_ value: DatabaseValue?) -> [String] {
  guard let s = text(value), let data = s.data(using: .utf8),
        let arr = try? JSONSerialization.jsonObject(with: data) as? [Any]
  else { return [] }
  return arr.compactMap { $0 as? String }
}

/// SQLite integer -> boolean.
func toBool(_ value: DatabaseValue?) -> Bool {
  guard let value else { return false }
  switch value.storage {
  case .int64(let n): return n == 1
  case .double(let d): return d == 1
  default: return false
  }
}

func text(_ value: DatabaseValue?) -> String? {
  guard case .string(let s) = value?.storage else { return nil }
  return s
}

/// Nullable numeric column (Int64 or Double).
func num(_ value: DatabaseValue?) -> Double? {
  guard let value else { return nil }
  switch value.storage {
  case .int64(let n): return Double(n)
  case .double(let d): return d
  default: return nil
  }
}

/// Required numeric column with default.
func numOr(_ value: DatabaseValue?, _ fallback: Double) -> Double {
  num(value) ?? fallback
}

/// Required text column; throws on null so schema drift surfaces loudly.
enum RowError: Error, Equatable {
  case nullColumn(String)
}

func requireText(_ value: DatabaseValue?, _ column: String) throws -> String {
  guard let s = text(value) else { throw RowError.nullColumn(column) }
  return s
}

/// `(?, ?, ?)` placeholder list for `IN` clauses.
func placeholders(_ n: Int) -> String {
  [String](repeating: "?", count: n).joined(separator: ", ")
}

/// Split an id list into chunks below SQLite's parameter limit.
func chunk<T>(_ items: [T], size: Int = 400) -> [[T]] {
  stride(from: 0, to: items.count, by: size).map { Array(items[$0 ..< min($0 + size, items.count)]) }
}

private let jsonEncoder = JSONEncoder()
private let lock = NSLock()

/// `JSON.stringify(v)`: compact, no escaping slashes. Declaration-order keys when `T` is a
/// KAModel struct (JSONEncoder emits CodingKeys order, which mirrors field declaration order).
func jsonEncode<T: Encodable>(_ v: T) -> String {
  lock.lock()
  defer { lock.unlock() }
  let data = try! jsonEncoder.encode(v)
  return String(data: data, encoding: .utf8)!
}

/// `JSON.stringify(value ?? null)` for optional encodables.
func jsonEncodeOrNull<T: Encodable>(_ v: T?) -> String {
  jsonEncode(v)
}
