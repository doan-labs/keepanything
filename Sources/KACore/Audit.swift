import Foundation
import GRDB
import KAModel
import KAStorage

/// Audited actions. `before`/`after` shapes are documented per action in `undo()`.
/// Port of `core/audit.ts`.
public enum AuditActions {
  public static let createCollection = "create_collection"
  public static let renameCollection = "rename_collection"
  public static let deleteCollection = "delete_collection"
  public static let addToCollection = "add_to_collection"
  public static let removeFromCollection = "remove_from_collection"
  public static let createRelationship = "create_relationship"
  public static let removeRelationship = "remove_relationship"
  public static let updateItem = "update_item"
  public static let updateUnderstanding = "update_understanding"
  public static let createNote = "create_note"
  public static let keptAgain = "kept_again"
  public static let trashItem = "trash_item"
  public static let restoreItem = "restore_item"
}

/// Id/timestamp are filled in.
public struct AuditInput: Sendable {
  public var actor: AuditActor
  /// One of `AuditActions.*` (the row stores a plain string).
  public var action: String
  public var entity: String
  public var entityId: String
  public var before: JSONValue?
  public var after: JSONValue?
  public var agentRunId: String?

  public init(actor: AuditActor, action: String, entity: String, entityId: String,
              before: JSONValue? = nil, after: JSONValue? = nil, agentRunId: String? = nil) {
    self.actor = actor
    self.action = action
    self.entity = entity
    self.entityId = entityId
    self.before = before
    self.after = after
    self.agentRunId = agentRunId
  }
}

/// Membership key used in `entity_id` for `collection_item` rows.
public func membershipKey(_ collectionId: String, _ itemId: String) -> String {
  "\(collectionId):\(itemId)"
}

/// Second `collection_member` suppression key: survives the collection being deleted and
/// re-created under the same name.
public func nameMemberKey(_ nameKey: String, _ itemId: String) -> String {
  "name:\(nameKey):\(itemId)"
}

/// Re-decode a stored JSON column into a typed value (the audit `before`/`after` columns hold
/// whatever shape the action recorded).
func jsonCast<T: Decodable>(_ v: JSONValue?) -> T? {
  guard let v else { return nil }
  guard let data = try? JSONEncoder().encode(v) else { return nil }
  return try? JSONDecoder().decode(T.self, from: data)
}

/// Convert a JSON audit field into an items-patch value (TS spread the `before` object into the
/// repo update; the repo patch maps property names to columns).
func jsonToDbValue(_ v: JSONValue) -> DatabaseValueConvertible? {
  switch v {
  case .null: return nil
  case .string(let s): return s
  case .number(let n): return n
  case .bool(let b): return b
  case .array, .object: return (try? jsonEncode(v)) ?? "{}"
  }
}

/// Audit writes and undo.
public struct AuditService: Sendable {
  private let db: Db
  private let repos: Repositories
  private let events: EventBus
  private let clock: Clock
  private let ids: IdGenerator

  public init(db: Db, repos: Repositories, events: EventBus, clock: Clock, ids: IdGenerator? = nil) {
    self.db = db
    self.repos = repos
    self.events = events
    self.clock = clock
    self.ids = ids ?? uuid
  }

  @discardableResult
  public func record(_ input: AuditInput) -> AuditEntry {
    let entry = AuditEntry(
      id: ids(), actor: input.actor, action: input.action, entity: input.entity,
      entityId: input.entityId, before: input.before, after: input.after,
      agentRunId: input.agentRunId, createdAt: clock.nowIso())
    try? repos.audit.insert(entry)
    return entry
  }

  public func get(_ auditId: String) -> AuditEntry? {
    try? repos.audit.get(auditId)
  }

  private struct CollectionWithMembers: Decodable {
    let collection: Collection
    let members: [CollectionItem]?
  }

  private struct IdsAfter: Decodable {
    let ids: [String]?
  }

  private func emitItems(_ reason: ItemsChangedReason, _ itemIds: [String]) {
    if itemIds.isEmpty { return }
    db.afterCommit { [db, repos, events] in
      let items = (try? repos.items.getMany(itemIds)) ?? []
      let summaries = (try? repos.items.summaries(items)) ?? []
      let event = ItemsChangedEvent(reason: reason, ids: itemIds, summaries: summaries)
      switch reason {
      case .updated: events.emit(.itemUpdated(event))
      case .trashed: events.emit(.itemTrashed(event))
      case .restored: events.emit(.itemRestored(event))
      case .created: events.emit(.itemCreated(event))
      case .deleted: events.emit(.itemDeleted(event))
      }
    }
  }

  private func emitCollections() {
    db.afterCommit { [events] in events.emit(.collectionsChanged) }
  }

  private func isAgentFact(_ entry: AuditEntry) -> Bool { entry.actor == .agent }

  private func undoEntry(_ entry: AuditEntry, _ now: String) throws {
    switch entry.action {
    case AuditActions.createCollection:
      let after: CollectionWithMembers? = jsonCast(entry.after)
      let collection = (try? repos.collections.get(entry.entityId)) ?? after?.collection
      if isAgentFact(entry), let collection {
        for m in try repos.collections.members(collection.id) {
          try repos.suppressions.add(.collectionMember, nameMemberKey(collection.nameKey, m.itemId), now)
        }
      }
      try repos.collections.delete(entry.entityId)
      emitCollections()
    case AuditActions.renameCollection:
      let before: RenameBefore? = jsonCast(entry.before)
      guard let before else { throw KaError(.conflict, "Can't undo that.") }
      let clash = try repos.collections.getByNameKey(before.nameKey)
      if let clash, clash.id != entry.entityId {
        throw KaError(.conflict, "A collection with that name already exists.")
      }
      try repos.collections.update(entry.entityId, patch: [
        ("name", before.name), ("nameKey", before.nameKey),
        ("description", before.description as DatabaseValueConvertible?),
        ("updatedAt", now)
      ])
      emitCollections()
    case AuditActions.deleteCollection:
      let before: CollectionWithMembers? = jsonCast(entry.before)
      guard let before else { throw KaError(.conflict, "Can't undo that.") }
      if try repos.collections.getByNameKey(before.collection.nameKey) != nil {
        throw KaError(.conflict, "A collection with that name already exists.")
      }
      try repos.collections.insert(before.collection)
      for m in before.members ?? [] {
        if try repos.items.get(m.itemId) != nil { try repos.collections.addMember(m) }
      }
      emitCollections()
      emitItems(.updated, (before.members ?? []).map(\.itemId))
    case AuditActions.addToCollection:
      let after: CollectionItem? = jsonCast(entry.after)
      guard let after else { throw KaError(.conflict, "Can't undo that.") }
      try repos.collections.removeMember(collectionId: after.collectionId, itemId: after.itemId)
      if isAgentFact(entry) {
        try repos.suppressions.add(
          .collectionMember, membershipKey(after.collectionId, after.itemId), now)
        if let collection = try repos.collections.get(after.collectionId) {
          try repos.suppressions.add(
            .collectionMember, nameMemberKey(collection.nameKey, after.itemId), now)
        }
      }
      emitCollections()
      emitItems(.updated, [after.itemId])
    case AuditActions.removeFromCollection:
      let before: CollectionItem? = jsonCast(entry.before)
      guard let before else { throw KaError(.conflict, "Can't undo that.") }
      guard let collection = try repos.collections.get(before.collectionId),
            try repos.items.get(before.itemId) != nil else {
        throw KaError(.notFound, "That collection or item is gone.")
      }
      if try repos.collections.getMember(collectionId: before.collectionId, itemId: before.itemId) == nil {
        try repos.collections.addMember(before)
      }
      try repos.suppressions.remove(
        .collectionMember, membershipKey(before.collectionId, before.itemId))
      try repos.suppressions.remove(
        .collectionMember, nameMemberKey(collection.nameKey, before.itemId))
      emitCollections()
      emitItems(.updated, [before.itemId])
    case AuditActions.createRelationship:
      let after: Relationship? = jsonCast(entry.after)
      guard let after else { throw KaError(.conflict, "Can't undo that.") }
      try repos.relationships.delete(after.id)
      if isAgentFact(entry) {
        try repos.suppressions.add(
          .relationship, relationshipSuppressionKey(after.sourceItemId, after.targetItemId), now)
      }
      emitItems(.updated, [after.sourceItemId, after.targetItemId])
    case AuditActions.removeRelationship:
      let before: Relationship? = jsonCast(entry.before)
      guard let before else { throw KaError(.conflict, "Can't undo that.") }
      guard try repos.items.get(before.sourceItemId) != nil,
            try repos.items.get(before.targetItemId) != nil else {
        throw KaError(.notFound, "One of those items is gone.")
      }
      if try repos.relationships.find(before.sourceItemId, before.targetItemId, before.type) == nil {
        try repos.relationships.insert(before)
      }
      try repos.suppressions.remove(
        .relationship, relationshipSuppressionKey(before.sourceItemId, before.targetItemId))
      emitItems(.updated, [before.sourceItemId, before.targetItemId])
    case AuditActions.updateItem, AuditActions.updateUnderstanding:
      guard case .object(let before)? = entry.before,
            try repos.items.get(entry.entityId) != nil else {
        throw KaError(.notFound, "That item is gone.")
      }
      var patch = before.map { (key: $0.key, value: jsonToDbValue($0.value)) }
      patch.append(("modifiedAt", now))
      try repos.items.update(entry.entityId, patch: patch)
      emitItems(.updated, [entry.entityId])
    case AuditActions.createNote:
      guard try repos.items.get(entry.entityId) != nil else {
        throw KaError(.notFound, "That note is gone.")
      }
      _ = try repos.jobs.cancelForItems([entry.entityId], now)
      try repos.items.setDeleted([entry.entityId], deletedAt: now)
      emitItems(.trashed, [entry.entityId])
    case AuditActions.trashItem:
      let after: IdsAfter? = jsonCast(entry.after)
      let idsToRestore = after?.ids ?? [entry.entityId]
      try repos.items.setDeleted(idsToRestore, deletedAt: nil)
      emitItems(.restored, idsToRestore)
    case AuditActions.restoreItem:
      let after: IdsAfter? = jsonCast(entry.after)
      let idsToTrash = after?.ids ?? [entry.entityId]
      _ = try repos.jobs.cancelForItems(idsToTrash, now)
      try repos.items.setDeleted(idsToTrash, deletedAt: now)
      emitItems(.trashed, idsToTrash)
    case AuditActions.keptAgain:
      throw KaError(.conflict, "Nothing to undo there.")
    default:
      throw KaError(.conflict, "Can't undo that.")
    }
  }

  /// Revert one entry. Throws `CONFLICT` when already undone or not undoable, `NOT_FOUND` when unknown.
  @discardableResult
  public func undo(_ auditId: String) throws -> AuditEntry {
    try db.transaction { _ in
      guard let entry = try repos.audit.get(auditId) else {
        throw KaError(.notFound, "Couldn't find that change.")
      }
      if entry.undoneAt != nil { throw KaError(.conflict, "Already undone.") }
      let now = clock.nowIso()
      try undoEntry(entry, now)
      try repos.audit.markUndone(entry.id, now)
      var done = entry
      done.undoneAt = now
      return done
    }
  }

  private struct RenameBefore: Decodable {
    let name: String
    let nameKey: String
    let description: String?
  }
}
