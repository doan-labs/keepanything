import GRDB
import KAModel

func rowToRelationship(_ row: Row) throws -> Relationship {
  Relationship(
    id: try requireText(row["id"], "id"),
    sourceItemId: try requireText(row["source_item_id"], "source_item_id"),
    targetItemId: try requireText(row["target_item_id"], "target_item_id"),
    type: RelationshipType(rawValue: try requireText(row["type"], "type")) ?? .relatedTo,
    description: text(row["description"]),
    confidence: num(row["confidence"]),
    evidence: parseJson(row["evidence"], nil),
    createdBy: RelationshipCreator(rawValue: try requireText(row["created_by"], "created_by")) ?? .user,
    agentRunId: text(row["agent_run_id"]),
    createdAt: try requireText(row["created_at"], "created_at")
  )
}

/// Relationship repository. Pair normalization happens in the service.
public struct RelationshipRepo: Sendable {
  let db: Db
  public init(db: Db) { self.db = db }

  public func insert(_ r: Relationship) throws {
    try db.run { d in
      try d.execute(sql: """
        INSERT INTO relationships (id, source_item_id, target_item_id, type, description, confidence, evidence, created_by, agent_run_id, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          r.id, r.sourceItemId, r.targetItemId, r.type.rawValue, r.description, r.confidence,
          r.evidence.map { jsonEncode($0) }, r.createdBy.rawValue, r.agentRunId, r.createdAt
        ])
    }
  }

  public func get(_ id: String) throws -> Relationship? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM relationships WHERE id = ?", arguments: [id]).map(rowToRelationship)
    }
  }

  public func delete(_ id: String) throws {
    try db.run { d in try d.execute(sql: "DELETE FROM relationships WHERE id = ?", arguments: [id]) }
  }

  /// Edges touching `itemId` in either direction (other side may be trashed; callers filter).
  public func forItem(_ itemId: String) throws -> [Relationship] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM relationships WHERE source_item_id = ? OR target_item_id = ? ORDER BY created_at DESC",
                       arguments: [itemId, itemId]).map(rowToRelationship)
    }
  }

  /// Exact stored triple.
  public func find(_ sourceItemId: String, _ targetItemId: String, _ type: RelationshipType) throws -> Relationship? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM relationships WHERE source_item_id = ? AND target_item_id = ? AND type = ?",
                       arguments: [sourceItemId, targetItemId, type.rawValue]).map(rowToRelationship)
    }
  }

  /// Any edge between two items regardless of direction/type.
  public func between(_ a: String, _ b: String) throws -> [Relationship] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: """
        SELECT * FROM relationships WHERE (source_item_id = ? AND target_item_id = ?) OR (source_item_id = ? AND target_item_id = ?)
        """, arguments: [a, b, b, a]).map(rowToRelationship)
    }
  }

  public func count() throws -> Int {
    let row = try db.readOnly { d in try Row.fetchOne(d, sql: "SELECT count(*) AS n FROM relationships") }
    return Int(numOr(row?["n"], 0))
  }
}
