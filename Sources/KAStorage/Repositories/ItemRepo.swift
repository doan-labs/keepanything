import Foundation
import GRDB
import KAModel

/// `Item` property -> SQL column and encoding. Port of `item-repo.ts`.
enum ColumnKind { case text, num, bool, json }

private struct Col { let key: String; let col: String; let kind: ColumnKind }

/// Column table in TS `COLUMNS` declaration order (iteration order drives INSERT placeholders).
private let COLUMNS: [Col] = [
  .init(key: "id", col: "id", kind: .text),
  .init(key: "type", col: "type", kind: .text),
  .init(key: "subtype", col: "subtype", kind: .text),
  .init(key: "kind", col: "kind", kind: .text),
  .init(key: "title", col: "title", kind: .text),
  .init(key: "originalPath", col: "original_path", kind: .text),
  .init(key: "managedPath", col: "managed_path", kind: .text),
  .init(key: "url", col: "url", kind: .text),
  .init(key: "canonicalUrl", col: "canonical_url", kind: .text),
  .init(key: "domain", col: "domain", kind: .text),
  .init(key: "mimeType", col: "mime_type", kind: .text),
  .init(key: "size", col: "size", kind: .num),
  .init(key: "contentHash", col: "content_hash", kind: .text),
  .init(key: "width", col: "width", kind: .num),
  .init(key: "height", col: "height", kind: .num),
  .init(key: "durationMs", col: "duration_ms", kind: .num),
  .init(key: "pageCount", col: "page_count", kind: .num),
  .init(key: "createdAt", col: "created_at", kind: .text),
  .init(key: "capturedAt", col: "captured_at", kind: .text),
  .init(key: "modifiedAt", col: "modified_at", kind: .text),
  .init(key: "lastKeptAt", col: "last_kept_at", kind: .text),
  .init(key: "captureBatchId", col: "capture_batch_id", kind: .text),
  .init(key: "processingStatus", col: "processing_status", kind: .text),
  .init(key: "processingError", col: "processing_error", kind: .text),
  .init(key: "understanding", col: "understanding", kind: .text),
  .init(key: "whyUseful", col: "why_useful", kind: .text),
  .init(key: "topics", col: "topics", kind: .json),
  .init(key: "entities", col: "entities", kind: .json),
  .init(key: "visionText", col: "vision_text", kind: .text),
  .init(key: "retrievalHints", col: "retrieval_hints", kind: .json),
  .init(key: "aiConfidence", col: "ai_confidence", kind: .num),
  .init(key: "metadata", col: "metadata", kind: .json),
  .init(key: "extractedText", col: "extracted_text", kind: .text),
  .init(key: "excerpt", col: "excerpt", kind: .text),
  .init(key: "thumbnailPath", col: "thumbnail_path", kind: .text),
  .init(key: "snapshotPath", col: "snapshot_path", kind: .text),
  .init(key: "faviconPath", col: "favicon_path", kind: .text),
  .init(key: "dominantColor", col: "dominant_color", kind: .text),
  .init(key: "mediaVersion", col: "media_version", kind: .num),
  .init(key: "parentItemId", col: "parent_item_id", kind: .text),
  .init(key: "userOverrides", col: "user_overrides", kind: .json),
  .init(key: "isMissing", col: "is_missing", kind: .bool),
  .init(key: "missingCheckedAt", col: "missing_checked_at", kind: .text),
  .init(key: "deletedAt", col: "deleted_at", kind: .text)
]

/// Item properties that feed the FTS row; writes touching any of them resync `items_fts`.
public let FTS_KEYS: Set<String> = [
  "title", "retrievalHints", "topics", "entities", "understanding", "whyUseful",
  "visionText", "metadata", "extractedText", "domain", "kind", "deletedAt"
]

private func itemValue(_ item: Item, _ key: String) -> DatabaseValueConvertible? {
  switch key {
  case "id": item.id
  case "type": item.type.rawValue
  case "subtype": item.subtype?.rawValue
  case "kind": item.kind?.rawValue
  case "title": item.title
  case "originalPath": item.originalPath
  case "managedPath": item.managedPath
  case "url": item.url
  case "canonicalUrl": item.canonicalUrl
  case "domain": item.domain
  case "mimeType": item.mimeType
  case "size": item.size
  case "contentHash": item.contentHash
  case "width": item.width
  case "height": item.height
  case "durationMs": item.durationMs
  case "pageCount": item.pageCount
  case "createdAt": item.createdAt
  case "capturedAt": item.capturedAt
  case "modifiedAt": item.modifiedAt
  case "lastKeptAt": item.lastKeptAt
  case "captureBatchId": item.captureBatchId
  case "processingStatus": item.processingStatus.rawValue
  case "processingError": item.processingError
  case "understanding": item.understanding
  case "whyUseful": item.whyUseful
  case "topics": jsonEncode(item.topics)
  case "entities": jsonEncode(item.entities)
  case "visionText": item.visionText
  case "retrievalHints": jsonEncode(item.retrievalHints)
  case "aiConfidence": item.aiConfidence
  case "metadata": jsonEncode(item.metadata)
  case "extractedText": item.extractedText
  case "excerpt": item.excerpt
  case "thumbnailPath": item.thumbnailPath
  case "snapshotPath": item.snapshotPath
  case "faviconPath": item.faviconPath
  case "dominantColor": item.dominantColor
  case "mediaVersion": item.mediaVersion
  case "parentItemId": item.parentItemId
  case "userOverrides": jsonEncode(item.userOverrides)
  case "isMissing": item.isMissing ? 1 : 0
  case "missingCheckedAt": item.missingCheckedAt
  case "deletedAt": item.deletedAt
  default: nil
  }
}

/// Map a raw `items` row to an `Item` (JSON parsed, booleans decoded).
func rowToItem(_ row: Row) throws -> Item {
  var item = Item()
  item.id = try requireText(row["id"], "id")
  item.type = ItemType(rawValue: try requireText(row["type"], "type")) ?? .unknown
  item.subtype = text(row["subtype"]).flatMap(ItemSubtype.init(rawValue:))
  item.kind = text(row["kind"]).flatMap(Kind.init(rawValue:))
  item.title = try requireText(row["title"], "title")
  item.originalPath = text(row["original_path"])
  item.managedPath = text(row["managed_path"])
  item.url = text(row["url"])
  item.canonicalUrl = text(row["canonical_url"])
  item.domain = text(row["domain"])
  item.mimeType = text(row["mime_type"])
  item.size = num(row["size"])
  item.contentHash = text(row["content_hash"])
  item.width = num(row["width"])
  item.height = num(row["height"])
  item.durationMs = num(row["duration_ms"])
  item.pageCount = num(row["page_count"])
  item.createdAt = try requireText(row["created_at"], "created_at")
  item.capturedAt = try requireText(row["captured_at"], "captured_at")
  item.modifiedAt = try requireText(row["modified_at"], "modified_at")
  item.lastKeptAt = try requireText(row["last_kept_at"], "last_kept_at")
  item.captureBatchId = text(row["capture_batch_id"])
  item.processingStatus = text(row["processing_status"]).flatMap(ProcessingStatus.init(rawValue:)) ?? .captured
  item.processingError = text(row["processing_error"])
  item.understanding = text(row["understanding"])
  item.whyUseful = text(row["why_useful"])
  item.topics = parseStringArray(row["topics"])
  item.entities = parseStringArray(row["entities"])
  item.visionText = text(row["vision_text"])
  item.retrievalHints = parseStringArray(row["retrieval_hints"])
  item.aiConfidence = num(row["ai_confidence"])
  item.metadata = parseJson(row["metadata"], ItemMetadata())
  item.extractedText = text(row["extracted_text"])
  item.excerpt = text(row["excerpt"])
  item.thumbnailPath = text(row["thumbnail_path"])
  item.snapshotPath = text(row["snapshot_path"])
  item.faviconPath = text(row["favicon_path"])
  item.dominantColor = text(row["dominant_color"])
  item.mediaVersion = numOr(row["media_version"], 1)
  item.parentItemId = text(row["parent_item_id"])
  item.userOverrides = parseJson(row["user_overrides"], UserOverrides())
  item.isMissing = toBool(row["is_missing"])
  item.missingCheckedAt = text(row["missing_checked_at"])
  item.deletedAt = text(row["deleted_at"])
  return item
}

/// Flatten `metadata` into the FTS `meta_text` column (descriptions, repo facts, names).
func metaText(_ metadata: ItemMetadata) -> String {
  var parts: [String] = []
  func push(_ v: String?) {
    guard let v else { return }
    let t = v.trimmingCharacters(in: .whitespaces)
    if !t.isEmpty { parts.append(t) }
  }
  func pushArr(_ v: [String]?) {
    for x in v ?? [] { parts.append(x) }
  }
  push(metadata.description)
  push(metadata.siteName)
  push(metadata.originalName)
  push(metadata.sourceUrl)
  pushArr(metadata.headings)
  if let og = metadata.og {
    push(og.title); push(og.description); push(og.siteName)
  }
  if let repo = metadata.repo {
    push(repo.owner); push(repo.name); push(repo.description); push(repo.language); pushArr(repo.topics)
  }
  if let folder = metadata.folder { pushArr(folder.extensions.keys.sorted()) }
  return parts.joined(separator: " ")
}

/// Facts needed to turn `Item`s into `ItemSummary`s in one pass.
public struct SummaryFacts: Sendable {
  public var collectionIds: [String: [String]] = [:]
  public var children: [String: (count: Int, thumbnailUrls: [String])] = [:]
  public init() {}
}

private func cardFacts(_ item: Item) -> ItemCardFacts? {
  guard let repo = item.metadata.repo else { return nil }
  var card = ItemCardFacts()
  card.language = repo.language
  card.stars = repo.stars
  card.description = repo.description
  card.owner = repo.owner
  return card
}

/// Build the card payload. Media URLs are created here and only here.
public func toSummary(_ item: Item, facts: SummaryFacts? = nil) -> ItemSummary {
  let children = facts?.children[item.id]
  var summary = ItemSummary()
  summary.id = item.id
  summary.type = item.type
  summary.subtype = item.subtype
  summary.kind = item.kind
  summary.title = item.title
  summary.domain = item.domain
  summary.url = item.url
  summary.thumbnailUrl = item.thumbnailPath.map { toMediaUrl(root: "thumbs", relPath: $0, version: item.mediaVersion) }
  summary.snapshotUrl = item.snapshotPath.map { toMediaUrl(root: "snapshots", relPath: $0, version: item.mediaVersion) }
  summary.faviconUrl = item.faviconPath.map { toMediaUrl(root: "objects", relPath: $0, version: item.mediaVersion) }
  summary.dominantColor = item.dominantColor
  summary.width = item.width
  summary.height = item.height
  summary.size = item.size
  summary.mimeType = item.mimeType
  summary.durationMs = item.durationMs
  summary.pageCount = item.pageCount
  summary.excerpt = item.excerpt
  summary.capturedAt = item.capturedAt
  summary.createdAt = item.createdAt
  summary.processingStatus = item.processingStatus
  summary.processingError = item.processingError
  summary.understanding = item.understanding.map { truncate($0, LIMITS.summaryUnderstandingMaxChars) }
  summary.collectionIds = facts?.collectionIds[item.id] ?? []
  // Folders are captured as one item with a manifest, so the file count comes from metadata.
  summary.childCount = Double(children?.count ?? 0) + (children == nil ? (item.metadata.folder?.fileCount ?? 0) : 0)
  summary.childThumbnailUrls = children?.thumbnailUrls ?? []
  summary.card = cardFacts(item)
  summary.isMissing = item.isMissing
  summary.parentItemId = item.parentItemId
  return summary
}

/// `items:list` query as the repository understands it.
public struct ItemListQuery: Sendable {
  public var view: ItemsView
  public var collectionId: String?
  public var types: [ItemType]?
  public var sort: ItemsSort?
  public var limit: Int?
  public var offset: Int?
  public init(view: ItemsView, collectionId: String? = nil, types: [ItemType]? = nil,
              sort: ItemsSort? = nil, limit: Int? = nil, offset: Int? = nil) {
    self.view = view
    self.collectionId = collectionId
    self.types = types
    self.sort = sort
    self.limit = limit
    self.offset = offset
  }
}

/// Row access, FTS sync and summary assembly. Callers own transactions.
public struct ItemRepo: Sendable {
  let db: Db
  public init(db: Db) { self.db = db }

  private let insertSql = "INSERT INTO items (\(COLUMNS.map(\.col).joined(separator: ", "))) VALUES (\(placeholders(COLUMNS.count)))"

  /// Rebuild the FTS row for one item (deleted items have none).
  public func syncFts(_ id: String) throws {
    try db.run { d in
      try d.execute(sql: "DELETE FROM items_fts WHERE item_id = ?", arguments: [id])
      guard let row = try Row.fetchOne(d, sql: "SELECT * FROM items WHERE id = ? AND deleted_at IS NULL",
                                     arguments: [id]) else { return }
      let item = try rowToItem(row)
      try d.execute(sql: """
        INSERT INTO items_fts (item_id, title, retrieval_hints, topics, entities, understanding, why_useful,
                               vision_text, meta_text, extracted_text, domain, kind)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          item.id,
          item.title,
          item.retrievalHints.joined(separator: " "),
          item.topics.joined(separator: " "),
          item.entities.joined(separator: " "),
          item.understanding ?? "",
          item.whyUseful ?? "",
          item.visionText ?? "",
          metaText(item.metadata),
          item.extractedText ?? "",
          item.domain ?? "",
          item.kind?.rawValue ?? ""
        ])
    }
  }

  public func insert(_ item: Item) throws {
    try db.run { d in
      try d.execute(sql: insertSql, arguments: StatementArguments(COLUMNS.map { itemValue(item, $0.key) }))
    }
    try syncFts(item.id)
  }

  public func get(_ id: String) throws -> Item? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM items WHERE id = ?", arguments: [id]).map(rowToItem)
    }
  }

  public func getMany(_ ids: [String]) throws -> [Item] {
    var out: [Item] = []
    for part in chunk(ids) {
      let rows = try db.readOnly { d in
        try Row.fetchAll(d, sql: "SELECT * FROM items WHERE id IN (\(placeholders(part.count)))",
                         arguments: StatementArguments(part))
      }
      out.append(contentsOf: try rows.map(rowToItem))
    }
    let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
    return out.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
  }

  /// Update the given fields; resyncs FTS when an indexed field (`FTS_KEYS`) is touched.
  /// `patch` maps Item property names to new values (`nil` writes SQL NULL).
  public func update(_ id: String, patch: [(key: String, value: DatabaseValueConvertible?)]) throws {
    var sets: [String] = []
    var params: [DatabaseValueConvertible?] = []
    var touchesFts = false
    let present = Set(patch.map(\.key))
    for c in COLUMNS where c.key != "id" && present.contains(c.key) {
      sets.append("\(c.col) = ?")
      params.append(patch.first(where: { $0.key == c.key })!.value)
      if FTS_KEYS.contains(c.key) { touchesFts = true }
    }
    if sets.isEmpty { return }
    try db.run { d in
      try d.execute(sql: "UPDATE items SET \(sets.joined(separator: ", ")) WHERE id = ?",
                    arguments: StatementArguments(params + [id]))
    }
    if touchesFts { try syncFts(id) }
  }

  /// `metadata = json_patch(metadata, patch)` (null values delete keys) and resync FTS.
  public func patchMetadata(_ id: String, patch: [String: JSONValue]) throws {
    try db.run { d in
      try d.execute(sql: "UPDATE items SET metadata = json_patch(metadata, ?) WHERE id = ?",
                    arguments: [jsonEncode(patch.mapValues { $0 }), id])
    }
    try syncFts(id)
  }

  /// Set/clear `deleted_at` and resync FTS.
  public func setDeleted(_ ids: [String], deletedAt: String?) throws {
    for part in chunk(ids) {
      try db.run { d in
        try d.execute(sql: "UPDATE items SET deleted_at = ? WHERE id IN (\(placeholders(part.count)))",
                      arguments: StatementArguments([deletedAt] + part.map { $0 as DatabaseValueConvertible? }))
      }
    }
    for id in ids { try syncFts(id) }
  }

  /// Hard delete (cascades to memberships, relationships, embeddings, jobs) and drop FTS rows.
  public func deleteForever(_ ids: [String]) throws {
    for part in chunk(ids) {
      try db.run { d in
        try d.execute(sql: "DELETE FROM items_fts WHERE item_id IN (\(placeholders(part.count)))",
                      arguments: StatementArguments(part))
        try d.execute(sql: "DELETE FROM items WHERE id IN (\(placeholders(part.count)))",
                      arguments: StatementArguments(part))
      }
    }
  }

  public func list(_ query: ItemListQuery) throws -> [Item] {
    var where_: [String] = []
    var params: [DatabaseValueConvertible?] = []
    var join = ""
    switch query.view {
    case .trash:
      where_.append("i.deleted_at IS NOT NULL")
    case .collection:
      join = "JOIN collection_items ci ON ci.item_id = i.id"
      where_.append("ci.collection_id = ?")
      where_.append("i.deleted_at IS NULL")
      params.append(query.collectionId ?? "")
    case .links:
      where_.append("i.deleted_at IS NULL")
      where_.append("i.parent_item_id IS NULL")
      where_.append("i.type = 'url'")
    case .files:
      where_.append("i.deleted_at IS NULL")
      where_.append("i.parent_item_id IS NULL")
      where_.append("i.type NOT IN ('url', 'note')")
    case .library:
      where_.append("i.deleted_at IS NULL")
      where_.append("i.parent_item_id IS NULL")
    }
    if let types = query.types, !types.isEmpty {
      where_.append("i.type IN (\(placeholders(types.count)))")
      params.append(contentsOf: types.map { $0.rawValue })
    }
    let order =
      query.sort == .title ? "i.title COLLATE NOCASE ASC, i.captured_at DESC"
        : query.sort == .created ? "i.created_at DESC"
        : query.view == .trash ? "i.deleted_at DESC"
        : "i.captured_at DESC"
    let limit = min(max(query.limit ?? 500, 1), 5000)
    let offset = max(query.offset ?? 0, 0)
    let sql = "SELECT i.* FROM items i \(join) WHERE \(where_.joined(separator: " AND ")) ORDER BY \(order) LIMIT ? OFFSET ?"
    return try db.readOnly { d in
      try Row.fetchAll(d, sql: sql, arguments: StatementArguments(params + [limit, offset])).map(rowToItem)
    }
  }

  public func children(_ parentId: String) throws -> [Item] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM items WHERE parent_item_id = ? AND deleted_at IS NULL ORDER BY title COLLATE NOCASE",
                       arguments: [parentId]).map(rowToItem)
    }
  }

  public func siblings(_ batchId: String) throws -> [Item] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM items WHERE capture_batch_id = ? AND deleted_at IS NULL ORDER BY captured_at",
                       arguments: [batchId]).map(rowToItem)
    }
  }

  public func findByHash(_ hash: String) throws -> Item? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM items WHERE content_hash = ? AND deleted_at IS NULL ORDER BY captured_at LIMIT 1",
                       arguments: [hash]).map(rowToItem)
    }
  }

  public func findByCanonicalUrl(_ canonicalUrl: String) throws -> Item? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM items WHERE canonical_url = ? AND deleted_at IS NULL ORDER BY captured_at LIMIT 1",
                       arguments: [canonicalUrl]).map(rowToItem)
    }
  }

  /// Ids of every non-deleted item (for `items:reprocessAll`).
  public func allIds() throws -> [String] {
    try db.readOnly { d in
      try String.fetchAll(d, sql: "SELECT id FROM items WHERE deleted_at IS NULL ORDER BY captured_at")
    }
  }

  public func summaryFacts(_ ids: [String]) throws -> SummaryFacts {
    var facts = SummaryFacts()
    for part in chunk(ids) {
      let members = try db.readOnly { d in
        try Row.fetchAll(d, sql: "SELECT item_id, collection_id FROM collection_items WHERE item_id IN (\(placeholders(part.count))) ORDER BY added_at",
                         arguments: StatementArguments(part))
      }
      for m in members {
        facts.collectionIds[try requireText(m["item_id"], "item_id"), default: []]
          .append(try requireText(m["collection_id"], "collection_id"))
      }
      let kids = try db.readOnly { d in
        try Row.fetchAll(d, sql: """
          SELECT parent_item_id, thumbnail_path, media_version FROM items
          WHERE parent_item_id IN (\(placeholders(part.count))) AND deleted_at IS NULL ORDER BY captured_at, title
          """, arguments: StatementArguments(part))
      }
      for k in kids {
        let parent = try requireText(k["parent_item_id"], "parent_item_id")
        var entry = facts.children[parent] ?? (count: 0, thumbnailUrls: [])
        entry.count += 1
        if let thumb = text(k["thumbnail_path"]), entry.thumbnailUrls.count < 4 {
          entry.thumbnailUrls.append(toMediaUrl(root: "thumbs", relPath: thumb, version: numOr(k["media_version"], 1)))
        }
        facts.children[parent] = entry
      }
    }
    return facts
  }

  public func summaries(_ items: [Item]) throws -> [ItemSummary] {
    let facts = try summaryFacts(items.map(\.id))
    return items.map { toSummary($0, facts: facts) }
  }

  public func summary(_ id: String) throws -> ItemSummary? {
    guard let item = try get(id) else { return nil }
    return toSummary(item, facts: try summaryFacts([id]))
  }

  /// `SystemStats` minus `aiStatus` (filled by the service layer).
  public struct SystemStatsCounts: Sendable, Equatable {
    public var items: Int
    public var connections: Int
    public var collections: Int
    public var processing: Int
  }

  public func stats() throws -> SystemStatsCounts {
    let row = try db.readOnly { d in
      try Row.fetchOne(d, sql: """
        SELECT (SELECT count(*) FROM items WHERE deleted_at IS NULL) AS items,
               (SELECT count(*) FROM relationships) AS connections,
               (SELECT count(*) FROM collections) AS collections,
               (SELECT count(*) FROM items WHERE deleted_at IS NULL AND processing_status NOT IN ('READY', 'PARTIAL')) AS processing
        """)
    }
    return SystemStatsCounts(
      items: Int(numOr(row?["items"], 0)),
      connections: Int(numOr(row?["connections"], 0)),
      collections: Int(numOr(row?["collections"], 0)),
      processing: Int(numOr(row?["processing"], 0))
    )
  }

  public func count() throws -> Int {
    let row = try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT count(*) AS n FROM items WHERE deleted_at IS NULL")
    }
    return Int(numOr(row?["n"], 0))
  }
}
