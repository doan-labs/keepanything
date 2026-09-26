import Foundation
import GRDB
import KAModel
import KAStorage

/// Everything optional except type and title. Mirrors `NewItemInput`.
public struct NewItemInput: Sendable {
  public var id: String?
  public var type: ItemType
  public var title: String
  public var subtype: ItemSubtype?
  public var kind: Kind?
  public var originalPath: String?
  public var managedPath: String?
  public var url: String?
  public var canonicalUrl: String?
  public var domain: String?
  public var mimeType: String?
  public var size: Double?
  public var contentHash: String?
  public var width: Double?
  public var height: Double?
  public var durationMs: Double?
  public var pageCount: Double?
  public var createdAt: String?
  public var capturedAt: String?
  public var modifiedAt: String?
  public var lastKeptAt: String?
  public var captureBatchId: String?
  public var processingStatus: ProcessingStatus?
  public var processingError: String?
  public var understanding: String?
  public var whyUseful: String?
  public var topics: [String]?
  public var entities: [String]?
  public var visionText: String?
  public var retrievalHints: [String]?
  public var aiConfidence: Double?
  public var metadata: ItemMetadata?
  public var extractedText: String?
  public var excerpt: String?
  public var thumbnailPath: String?
  public var snapshotPath: String?
  public var faviconPath: String?
  public var dominantColor: String?
  public var mediaVersion: Double?
  public var parentItemId: String?
  public var userOverrides: UserOverrides?
  public var isMissing: Bool?
  public var missingCheckedAt: String?
  public var deletedAt: String?

  public init(type: ItemType, title: String) {
    self.type = type
    self.title = title
  }
}

/// Status an item is reset to when reprocessing from a given stage (nil = keep).
public func statusForReprocess(_ from: Stage?) -> ProcessingStatus? {
  switch from {
  case .none, .extract, .thumbnail, .snapshot: return .captured
  case .embed, .understand: return .extracted
  default: return nil
  }
}

/// Result of `applyUnderstanding`.
public struct ApplyUnderstandingResult: Sendable {
  public var item: Item
  public var skippedFields: [UserOverridableField]
}

/// Item domain service. Every mutation is one transaction. Port of `core/item-service.ts`.
public struct ItemService: Sendable {
  private let db: Db
  private let repos: Repositories
  private let events: EventBus
  private let clock: Clock
  private let audit: AuditService
  private let pipeline: ItemPipeline
  private let ids: IdGenerator

  /// Understanding fields the user may override, in the order they are applied.
  private static let overridable: [UserOverridableField] =
    [.title, .understanding, .whyUseful, .kind, .topics, .entities]

  public init(db: Db, repos: Repositories, events: EventBus, clock: Clock,
              audit: AuditService, pipeline: ItemPipeline, ids: IdGenerator? = nil) {
    self.db = db
    self.repos = repos
    self.events = events
    self.clock = clock
    self.audit = audit
    self.pipeline = pipeline
    self.ids = ids ?? uuid
  }

  private var items: ItemRepo { repos.items }

  private func emit(_ event: ItemsChangedReason, _ idList: [String]) {
    if idList.isEmpty { return }
    db.afterCommit { [repos, events] in
      let payload: ItemsChangedEvent
      if event == .deleted {
        payload = ItemsChangedEvent(reason: event, ids: idList)
      } else {
        let list = (try? repos.items.getMany(idList)) ?? []
        payload = ItemsChangedEvent(
          reason: event, ids: idList,
          summaries: (try? repos.items.summaries(list)) ?? [])
      }
      switch event {
      case .created: events.emit(.itemCreated(payload))
      case .updated: events.emit(.itemUpdated(payload))
      case .trashed: events.emit(.itemTrashed(payload))
      case .restored: events.emit(.itemRestored(payload))
      case .deleted: events.emit(.itemDeleted(payload))
      }
    }
  }

  /// Insert a new item at `CAPTURED` (or the given status). Does not enqueue jobs.
  @discardableResult
  public func create(_ input: NewItemInput) throws -> Item {
    let now = clock.nowIso()
    let item = Item(
      id: input.id ?? ids(), type: input.type, subtype: input.subtype, kind: input.kind,
      title: input.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled"
        : input.title.trimmingCharacters(in: .whitespaces),
      originalPath: input.originalPath, managedPath: input.managedPath, url: input.url,
      canonicalUrl: input.canonicalUrl, domain: input.domain, mimeType: input.mimeType,
      size: input.size, contentHash: input.contentHash, width: input.width, height: input.height,
      durationMs: input.durationMs, pageCount: input.pageCount,
      createdAt: input.createdAt ?? now, capturedAt: input.capturedAt ?? now,
      modifiedAt: input.modifiedAt ?? now, lastKeptAt: input.lastKeptAt ?? now,
      captureBatchId: input.captureBatchId, processingStatus: input.processingStatus ?? .captured,
      processingError: input.processingError, understanding: input.understanding,
      whyUseful: input.whyUseful, topics: input.topics ?? [], entities: input.entities ?? [],
      visionText: input.visionText, retrievalHints: input.retrievalHints ?? [],
      aiConfidence: input.aiConfidence, metadata: input.metadata ?? ItemMetadata(),
      extractedText: input.extractedText, excerpt: input.excerpt,
      thumbnailPath: input.thumbnailPath, snapshotPath: input.snapshotPath,
      faviconPath: input.faviconPath, dominantColor: input.dominantColor,
      mediaVersion: input.mediaVersion ?? 1, parentItemId: input.parentItemId,
      userOverrides: input.userOverrides ?? UserOverrides(), isMissing: input.isMissing ?? false,
      missingCheckedAt: input.missingCheckedAt, deletedAt: input.deletedAt)
    try db.transaction { _ in
      try items.insert(item)
      emit(.created, [item.id])
    }
    return item
  }

  /// Throws `NOT_FOUND`.
  public func get(_ id: String) throws -> Item {
    guard let item = try items.get(id) else {
      throw KaError(.notFound, "Couldn't find that item.")
    }
    return item
  }

  public func find(_ id: String) throws -> Item? {
    try items.get(id)
  }

  public func list(_ request: ItemsListRequest) throws -> [ItemSummary] {
    if request.view == .collection && request.collectionId == nil {
      throw KaError(.validation, "Which collection?")
    }
    var q = ItemListQuery(view: request.view)
    q.collectionId = request.collectionId
    q.types = request.types
    q.sort = request.sort
    q.limit = request.limit
    q.offset = request.offset
    return try items.summaries(items.list(q))
  }

  public func summary(_ id: String) throws -> ItemSummary? {
    try items.summary(id)
  }

  public func summaries(_ list: [Item]) throws -> [ItemSummary] {
    try items.summaries(list)
  }

  public func detail(_ id: String) throws -> ItemDetail {
    let item = try get(id)
    var relationships: [ItemDetailRelationship] = []
    for r in try repos.relationships.forItem(id) {
      let direction: RelationshipDirection = r.sourceItemId == id ? .out : .in
      let otherId = direction == .out ? r.targetItemId : r.sourceItemId
      guard let other = try items.summary(otherId) else { continue }
      relationships.append(ItemDetailRelationship(
        relationship: r, direction: direction,
        label: relationshipLabel(r.type, direction), other: other))
    }
    var collections: [ItemDetailCollection] = []
    for m in try repos.collections.membershipsForItem(id) {
      guard let c = try repos.collections.get(m.collectionId) else { continue }
      collections.append(ItemDetailCollection(
        collection: c, confidence: m.confidence, reason: m.reason,
        addedBy: m.addedBy, agentRunId: m.agentRunId, addedAt: m.addedAt))
    }
    var result = ItemDetail(
      item: item,
      summary: (try items.summary(id)) ?? toSummary(item),
      originalUrl: item.managedPath.map { toMediaUrl(root: "objects", relPath: $0, version: item.mediaVersion) },
      relationships: relationships,
      collections: collections,
      latestRuns: try repos.agentRuns.latestForItem(id, 5))
    if item.type == .folder {
      result.children = try items.summaries(items.children(id))
    }
    return result
  }

  /// Writes fields, marks `user_overrides`, audits, re-indexes.
  @discardableResult
  public func updateByUser(_ id: String, patch: ItemUpdatePatch) throws -> ItemDetail {
    try db.transaction { _ in
      let item = try get(id)
      let now = clock.nowIso()
      var before: [String: JSONValue] = [:]
      var update: [(key: String, value: DatabaseValueConvertible?)] = [("modifiedAt", now)]
      var overrides = item.userOverrides
      var after: [String: JSONValue] = ["modifiedAt": .string(now)]
      if let title = patch.title {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { throw KaError(.validation, "A title is needed.") }
        before["title"] = .string(item.title)
        update.append(("title", trimmed))
        after["title"] = .string(trimmed)
        overrides.title = true
      }
      if let understanding = patch.understanding {
        let trimmed = understanding.trimmingCharacters(in: .whitespaces)
        before["understanding"] = item.understanding.map { .string($0) } ?? .null
        let v: String? = trimmed.isEmpty ? nil : trimmed
        update.append(("understanding", v))
        after["understanding"] = v.map { .string($0) } ?? .null
        overrides.understanding = true
      }
      if let whyUseful = patch.whyUseful {
        let trimmed = whyUseful.trimmingCharacters(in: .whitespaces)
        before["whyUseful"] = item.whyUseful.map { .string($0) } ?? .null
        let v: String? = trimmed.isEmpty ? nil : trimmed
        update.append(("whyUseful", v))
        after["whyUseful"] = v.map { .string($0) } ?? .null
        overrides.whyUseful = true
      }
      if update.count == 1 { return }
      before["userOverrides"] = (try? JSONDecoder().decode(
        JSONValue.self, from: JSONEncoder().encode(item.userOverrides))) ?? .object([:])
      update.append(("userOverrides", jsonEncode(overrides)))
      after["userOverrides"] = (try? JSONDecoder().decode(
        JSONValue.self, from: JSONEncoder().encode(overrides))) ?? .object([:])
      try items.update(id, patch: update)
      audit.record(AuditInput(
        actor: .user, action: AuditActions.updateItem, entity: "item", entityId: id,
        before: .object(before), after: .object(after)))
      var merged = item
      merged.modifiedAt = now
      if let title = patch.title { merged.title = title.trimmingCharacters(in: .whitespaces) }
      pipeline.enqueueFrom(merged, from: .index)
      emit(.updated, [id])
    }
    return try detail(id)
  }

  /// Agent/system write honouring `user_overrides`. Returns the fields it skipped.
  @discardableResult
  public func applyUnderstanding(_ id: String, understanding: Understanding,
                                 agentRunId: String? = nil, actor: AuditActor = .agent) throws -> ApplyUnderstandingResult {
    try db.transaction { _ in
      let item = try get(id)
      let now = clock.nowIso()
      var skipped: [UserOverridableField] = []
      var before: [String: JSONValue] = [:]
      var update: [(key: String, value: DatabaseValueConvertible?)] = [("modifiedAt", now)]
      var after: [String: JSONValue] = ["modifiedAt": .string(now)]
      // (new column value, JSON for audit) per overridable field.
      func newValue(_ f: UserOverridableField) -> (DatabaseValueConvertible?, JSONValue) {
        let trimmedTitle = understanding.title.trimmingCharacters(in: .whitespaces)
        switch f {
        case .title:
          let v = trimmedTitle.isEmpty ? item.title : trimmedTitle
          return (v, .string(v))
        case .understanding: return (understanding.summary, .string(understanding.summary))
        case .whyUseful: return (understanding.whyUseful, .string(understanding.whyUseful))
        case .kind: return (understanding.kind.rawValue, .string(understanding.kind.rawValue))
        case .topics: return (jsonEncode(understanding.topics), .array(understanding.topics.map { .string($0) }))
        case .entities: return (jsonEncode(understanding.entities), .array(understanding.entities.map { .string($0) }))
        }
      }
      func oldValue(_ f: UserOverridableField) -> JSONValue {
        switch f {
        case .title: return .string(item.title)
        case .understanding: return item.understanding.map { .string($0) } ?? .null
        case .whyUseful: return item.whyUseful.map { .string($0) } ?? .null
        case .kind: return item.kind.map { .string($0.rawValue) } ?? .null
        case .topics: return .array(item.topics.map { .string($0) })
        case .entities: return .array(item.entities.map { .string($0) })
        }
      }
      for field in Self.overridable {
        if item.userOverrides[field] == true {
          skipped.append(field)
          continue
        }
        before[field.rawValue] = oldValue(field)
        let (col, json) = newValue(field)
        update.append((field.rawValue, col))
        after[field.rawValue] = json
      }
      before["visionText"] = item.visionText.map { .string($0) } ?? .null
      before["retrievalHints"] = .array(item.retrievalHints.map { .string($0) })
      before["aiConfidence"] = item.aiConfidence.map { .number($0) } ?? .null
      let vision = [understanding.visualDescription, understanding.visibleText]
        .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
      update.append(("visionText", vision.isEmpty ? nil : vision))
      after["visionText"] = vision.isEmpty ? .null : .string(vision)
      update.append(("retrievalHints", jsonEncode(understanding.retrievalHints)))
      after["retrievalHints"] = .array(understanding.retrievalHints.map { .string($0) })
      update.append(("aiConfidence", understanding.confidence))
      after["aiConfidence"] = .number(understanding.confidence)
      try items.update(id, patch: update)
      audit.record(AuditInput(
        actor: actor, action: AuditActions.updateUnderstanding, entity: "item", entityId: id,
        before: .object(before), after: .object(after), agentRunId: agentRunId))
      emit(.updated, [id])
      return ApplyUnderstandingResult(item: try get(id), skippedFields: skipped)
    }
  }

  public func trash(_ idList: [String]) throws {
    if idList.isEmpty { return }
    try db.transaction { _ in
      let now = clock.nowIso()
      let existing = try items.getMany(idList).filter { $0.deletedAt == nil }
      if existing.isEmpty { return }
      let targetIds = existing.map(\.id)
      _ = pipeline.cancelForItems(targetIds)
      // The jobs are gone, so a running status would leave the card pulsing "Reading" for good.
      // Settle it the way cancelProcessing does: PARTIAL reads as "kept, we stopped short".
      // Failures keep their status: they already read as stopped, and the reason is worth keeping.
      for item in existing {
        let status = item.processingStatus
        if isTerminal(status) || isFailed(status) { continue }
        try items.update(item.id, patch: [("processingStatus", ProcessingStatus.partial.rawValue),
                                          ("modifiedAt", now)])
      }
      try items.setDeleted(targetIds, deletedAt: now)
      audit.record(AuditInput(
        actor: .user, action: AuditActions.trashItem, entity: "item",
        entityId: targetIds[0], after: .object(["ids": .array(targetIds.map { .string($0) })])))
      emit(.trashed, targetIds)
    }
  }

  public func restore(_ idList: [String]) throws {
    if idList.isEmpty { return }
    try db.transaction { _ in
      let existing = try items.getMany(idList).filter { $0.deletedAt != nil }
      if existing.isEmpty { return }
      let targetIds = existing.map(\.id)
      try items.setDeleted(targetIds, deletedAt: nil)
      audit.record(AuditInput(
        actor: .user, action: AuditActions.restoreItem, entity: "item",
        entityId: targetIds[0], after: .object(["ids": .array(targetIds.map { .string($0) })])))
      emit(.restored, targetIds)
    }
  }

  /// Hard delete. Returns the removed rows so the caller can purge managed files.
  @discardableResult
  public func deleteForever(_ idList: [String]) throws -> [Item] {
    if idList.isEmpty { return [] }
    return try db.transaction { _ in
      var existing = try items.getMany(idList)
      var targetIds = existing.map(\.id)
      // Children of a folder go with it.
      for item in existing where item.type == .folder {
        for child in try items.children(item.id) where !targetIds.contains(child.id) {
          existing.append(child)
          targetIds.append(child.id)
        }
      }
      _ = pipeline.cancelForItems(targetIds)
      try items.deleteForever(targetIds)
      emit(.deleted, targetIds)
      return existing
    }
  }

  /// Stop processing without deleting: cancels queued/running jobs and settles the items at `PARTIAL`.
  public func cancelProcessing(_ idList: [String]) throws {
    try db.transaction { _ in
      let cancelled = pipeline.cancelForItems(idList)
      var touched: [String] = []
      for id in idList {
        guard let item = try items.get(id) else { continue }
        if isTerminal(item.processingStatus) { continue }
        try items.update(id, patch: [("processingStatus", ProcessingStatus.partial.rawValue),
                                     ("modifiedAt", clock.nowIso())])
        touched.append(id)
      }
      db.afterCommit { [events] in
        for job in cancelled {
          events.emit(.jobProgress(JobProgress(
            itemId: job.itemId, batchId: job.batchId, processingStatus: .partial,
            stage: job.stage, jobStatus: .cancelled, attempts: job.attempts)))
        }
      }
      emit(.updated, touched)
    }
  }

  public func reprocess(_ id: String, from: Stage? = nil) throws {
    try db.transaction { _ in
      let item = try get(id)
      if item.deletedAt != nil { throw KaError(.conflict, "Restore it from the Trash first.") }
      _ = pipeline.cancelForItems([id])
      let status = statusForReprocess(from)
      var update: [(key: String, value: DatabaseValueConvertible?)] =
        [("processingError", nil), ("modifiedAt", clock.nowIso())]
      if let status { update.append(("processingStatus", status.rawValue)) }
      try items.update(id, patch: update)
      var merged = item
      merged.processingError = nil
      merged.modifiedAt = clock.nowIso()
      if let status { merged.processingStatus = status }
      pipeline.enqueueFrom(merged, from: from)
      emit(.updated, [id])
    }
  }

  @discardableResult
  public func reprocessAll(_ from: Stage? = nil) throws -> Int {
    try db.transaction { _ in
      let all = try items.allIds()
      let status = statusForReprocess(from)
      let now = clock.nowIso()
      var count = 0
      for id in all {
        guard let item = try items.get(id) else { continue }
        _ = pipeline.cancelForItems([id])
        var update: [(key: String, value: DatabaseValueConvertible?)] =
          [("processingError", nil), ("modifiedAt", now)]
        if let status { update.append(("processingStatus", status.rawValue)) }
        try items.update(id, patch: update)
        var merged = item
        merged.processingError = nil
        merged.modifiedAt = now
        if let status { merged.processingStatus = status }
        pipeline.enqueueFrom(merged, from: from)
        count += 1
      }
      emit(.updated, all)
      return count
    }
  }

  /// Bump `last_kept_at`, audit `kept_again`.
  @discardableResult
  public func keptAgain(_ id: String) throws -> Item {
    try db.transaction { _ in
      let item = try get(id)
      let now = clock.nowIso()
      try items.update(id, patch: [("lastKeptAt", now)])
      audit.record(AuditInput(
        actor: .user, action: AuditActions.keptAgain, entity: "item", entityId: id,
        before: .object(["lastKeptAt": .string(item.lastKeptAt)]),
        after: .object(["lastKeptAt": .string(now)])))
      emit(.updated, [id])
      var out = item
      out.lastKeptAt = now
      return out
    }
  }

  /// Update the missing-original cache.
  @discardableResult
  public func setMissing(_ id: String, isMissing: Bool) throws -> Item {
    try db.transaction { _ in
      let item = try get(id)
      let now = clock.nowIso()
      if item.isMissing != isMissing {
        try items.update(id, patch: [("isMissing", isMissing), ("missingCheckedAt", now)])
        emit(.updated, [id])
      } else {
        try items.update(id, patch: [("missingCheckedAt", now)])
      }
      var out = item
      out.isMissing = isMissing
      out.missingCheckedAt = now
      return out
    }
  }
}

private extension UserOverrides {
  subscript(field: UserOverridableField) -> Bool? {
    get {
      switch field {
      case .title: return title
      case .understanding: return understanding
      case .whyUseful: return whyUseful
      case .kind: return kind
      case .topics: return topics
      case .entities: return entities
      }
    }
    set {
      switch field {
      case .title: title = newValue
      case .understanding: understanding = newValue
      case .whyUseful: whyUseful = newValue
      case .kind: kind = newValue
      case .topics: topics = newValue
      case .entities: entities = newValue
      }
    }
  }
}
