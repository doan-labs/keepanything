import GRDB
import KAModel

/// Facts the agent must not re-create after a user removed them.
public struct SuppressionRepo: Sendable {
  let db: Db
  public init(db: Db) { self.db = db }

  /// Idempotent insert.
  public func add(_ kind: SuppressionKind, _ key: String, _ nowIso: String) throws {
    try db.run { d in
      try d.execute(sql: "INSERT OR IGNORE INTO suppressions (kind, key, created_at) VALUES (?, ?, ?)",
                    arguments: [kind.rawValue, key, nowIso])
    }
  }

  public func has(_ kind: SuppressionKind, _ key: String) throws -> Bool {
    try db.readOnly { d in
      try Int.fetchOne(d, sql: "SELECT 1 FROM suppressions WHERE kind = ? AND key = ?",
                       arguments: [kind.rawValue, key]) != nil
    }
  }

  public func remove(_ kind: SuppressionKind, _ key: String) throws {
    try db.run { d in
      try d.execute(sql: "DELETE FROM suppressions WHERE kind = ? AND key = ?",
                    arguments: [kind.rawValue, key])
    }
  }

  /// Every key of one kind (agent tool handlers filter candidates in bulk).
  public func keys(_ kind: SuppressionKind) throws -> Set<String> {
    try db.readOnly { d in
      Set(try String.fetchAll(d, sql: "SELECT key FROM suppressions WHERE kind = ?", arguments: [kind.rawValue]))
    }
  }
}
