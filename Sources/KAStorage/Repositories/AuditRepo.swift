import GRDB
import KAModel

func rowToAudit(_ row: Row) throws -> AuditEntry {
  AuditEntry(
    id: try requireText(row["id"], "id"),
    actor: AuditActor(rawValue: try requireText(row["actor"], "actor")) ?? .user,
    action: try requireText(row["action"], "action"),
    entity: try requireText(row["entity"], "entity"),
    entityId: try requireText(row["entity_id"], "entity_id"),
    before: parseJson(row["before"], nil),
    after: parseJson(row["after"], nil),
    agentRunId: text(row["agent_run_id"]),
    createdAt: try requireText(row["created_at"], "created_at"),
    undoneAt: text(row["undone_at"])
  )
}

/// Audit repository.
public struct AuditRepo: Sendable {
  let db: Db
  public init(db: Db) { self.db = db }

  public func insert(_ e: AuditEntry) throws {
    try db.run { d in
      try d.execute(sql: """
        INSERT INTO audit_log (id, actor, action, entity, entity_id, before, after, agent_run_id, created_at, undone_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          e.id, e.actor.rawValue, e.action, e.entity, e.entityId,
          e.before.map { jsonEncode($0) }, e.after.map { jsonEncode($0) },
          e.agentRunId, e.createdAt, e.undoneAt
        ])
    }
  }

  public func get(_ id: String) throws -> AuditEntry? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM audit_log WHERE id = ?", arguments: [id]).map(rowToAudit)
    }
  }

  public func markUndone(_ id: String, _ undoneAt: String) throws {
    try db.run { d in
      try d.execute(sql: "UPDATE audit_log SET undone_at = ? WHERE id = ?", arguments: [undoneAt, id])
    }
  }

  public func forRun(_ agentRunId: String) throws -> [AuditEntry] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM audit_log WHERE agent_run_id = ? ORDER BY created_at, rowid",
                       arguments: [agentRunId]).map(rowToAudit)
    }
  }

  public func forEntity(_ entity: String, _ entityId: String) throws -> [AuditEntry] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM audit_log WHERE entity = ? AND entity_id = ? ORDER BY created_at DESC, rowid DESC",
                       arguments: [entity, entityId]).map(rowToAudit)
    }
  }

  public func latest(_ limit: Int) throws -> [AuditEntry] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM audit_log ORDER BY created_at DESC, rowid DESC LIMIT ?",
                       arguments: [max(1, limit)]).map(rowToAudit)
    }
  }
}
