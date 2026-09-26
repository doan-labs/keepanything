import GRDB
import KAModel

func rowToCollection(_ row: Row) throws -> Collection {
  var c = Collection()
  c.id = try requireText(row["id"], "id")
  c.name = try requireText(row["name"], "name")
  c.nameKey = try requireText(row["name_key"], "name_key")
  c.description = text(row["description"])
  c.createdBy = CollectionCreator(rawValue: try requireText(row["created_by"], "created_by")) ?? .user
  c.color = text(row["color"])
  c.pinned = toBool(row["pinned"])
  c.createdAt = try requireText(row["created_at"], "created_at")
  c.updatedAt = try requireText(row["updated_at"], "updated_at")
  return c
}

func rowToMembership(_ row: Row) throws -> CollectionItem {
  var m = CollectionItem()
  m.collectionId = try requireText(row["collection_id"], "collection_id")
  m.itemId = try requireText(row["item_id"], "item_id")
  m.confidence = num(row["confidence"])
  m.reason = text(row["reason"])
  m.addedBy = MembershipActor(rawValue: try requireText(row["added_by"], "added_by")) ?? .user
  m.agentRunId = text(row["agent_run_id"])
  m.addedAt = try requireText(row["added_at"], "added_at")
  return m
}

/// Collection repository. Callers own transactions.
public struct CollectionRepo: Sendable {
  let db: Db
  public init(db: Db) { self.db = db }

  public func insert(_ c: Collection) throws {
    try db.run { d in
      try d.execute(sql: """
        INSERT INTO collections (id, name, name_key, description, created_by, color, pinned, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [c.id, c.name, c.nameKey, c.description, c.createdBy.rawValue, c.color,
                         c.pinned ? 1 : 0, c.createdAt, c.updatedAt])
    }
  }

  public func get(_ id: String) throws -> Collection? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM collections WHERE id = ?", arguments: [id]).map(rowToCollection)
    }
  }

  public func getByNameKey(_ nameKey: String) throws -> Collection? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM collections WHERE name_key = ?", arguments: [nameKey]).map(rowToCollection)
    }
  }

  /// Patch maps Collection field names to new values (`nil` writes SQL NULL); keys:
  /// name, nameKey, description, color, pinned, updatedAt.
  public func update(_ id: String, patch: [(key: String, value: DatabaseValueConvertible?)]) throws {
    var sets: [String] = []
    var params: [DatabaseValueConvertible?] = []
    for p in patch {
      switch p.key {
      case "name": sets.append("name = ?"); params.append(p.value)
      case "nameKey": sets.append("name_key = ?"); params.append(p.value)
      case "description": sets.append("description = ?"); params.append(p.value)
      case "color": sets.append("color = ?"); params.append(p.value)
      case "pinned": sets.append("pinned = ?"); params.append((p.value as? Bool) == true ? 1 : 0)
      case "updatedAt": sets.append("updated_at = ?"); params.append(p.value)
      default: break
      }
    }
    if sets.isEmpty { return }
    try db.run { d in
      try d.execute(sql: "UPDATE collections SET \(sets.joined(separator: ", ")) WHERE id = ?",
                    arguments: StatementArguments(params + [id]))
    }
  }

  public func delete(_ id: String) throws {
    try db.run { d in try d.execute(sql: "DELETE FROM collections WHERE id = ?", arguments: [id]) }
  }

  public func list() throws -> [Collection] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM collections ORDER BY pinned DESC, name COLLATE NOCASE").map(rowToCollection)
    }
  }

  /// Summaries with member count and up to 4 cover thumbnails (non-deleted members only).
  public func listSummaries() throws -> [CollectionSummary] {
    let rows = try db.readOnly { d in
      try Row.fetchAll(d, sql: """
        SELECT c.*, (SELECT count(*) FROM collection_items ci JOIN items i ON i.id = ci.item_id
                     WHERE ci.collection_id = c.id AND i.deleted_at IS NULL) AS count
        FROM collections c ORDER BY c.pinned DESC, c.name COLLATE NOCASE
        """)
    }
    return try rows.map { row in
      let collection = try rowToCollection(row)
      let thumbs = try db.readOnly { d in
        try Row.fetchAll(d, sql: """
          SELECT i.thumbnail_path, i.media_version FROM collection_items ci JOIN items i ON i.id = ci.item_id
          WHERE ci.collection_id = ? AND i.deleted_at IS NULL AND i.thumbnail_path IS NOT NULL
          ORDER BY ci.added_at DESC LIMIT 4
          """, arguments: [collection.id])
      }.map { toMediaUrl(root: "thumbs", relPath: text($0["thumbnail_path"]) ?? "", version: numOr($0["media_version"], 1)) }
      var s = CollectionSummary()
      s.collection = collection
      s.count = Int(numOr(row["count"], 0))
      s.coverThumbnailUrls = thumbs
      return s
    }
  }

  public func addMember(_ m: CollectionItem) throws {
    try db.run { d in
      try d.execute(sql: """
        INSERT INTO collection_items (collection_id, item_id, confidence, reason, added_by, agent_run_id, added_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, arguments: [m.collectionId, m.itemId, m.confidence, m.reason, m.addedBy.rawValue, m.agentRunId, m.addedAt])
    }
  }

  public func removeMember(collectionId: String, itemId: String) throws {
    try db.run { d in
      try d.execute(sql: "DELETE FROM collection_items WHERE collection_id = ? AND item_id = ?",
                    arguments: [collectionId, itemId])
    }
  }

  public func getMember(collectionId: String, itemId: String) throws -> CollectionItem? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM collection_items WHERE collection_id = ? AND item_id = ?",
                       arguments: [collectionId, itemId]).map(rowToMembership)
    }
  }

  public func members(_ collectionId: String) throws -> [CollectionItem] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM collection_items WHERE collection_id = ? ORDER BY added_at",
                       arguments: [collectionId]).map(rowToMembership)
    }
  }

  public func membershipsForItem(_ itemId: String) throws -> [CollectionItem] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM collection_items WHERE item_id = ? ORDER BY added_at",
                       arguments: [itemId]).map(rowToMembership)
    }
  }

  public func memberCount(_ collectionId: String) throws -> Int {
    let row = try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT count(*) AS n FROM collection_items WHERE collection_id = ?",
                       arguments: [collectionId])
    }
    return Int(numOr(row?["n"], 0))
  }
}
