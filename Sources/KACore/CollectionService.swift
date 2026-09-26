import Foundation
import KAModel
import KAStorage

public struct CreateCollectionInput: Sendable {
  public var name: String
  public var description: String?
  public var createdBy: CollectionCreator
  public var agentRunId: String?
  public var color: String?

  public init(name: String, description: String? = nil, createdBy: CollectionCreator,
              agentRunId: String? = nil, color: String? = nil) {
    self.name = name
    self.description = description
    self.createdBy = createdBy
    self.agentRunId = agentRunId
    self.color = color
  }
}

public struct AddMemberInput: Sendable {
  public var itemId: String
  public var confidence: Double?
  public var reason: String?

  public init(itemId: String, confidence: Double? = nil, reason: String? = nil) {
    self.itemId = itemId
    self.confidence = confidence
    self.reason = reason
  }
}

/// Why a member was not added.
public enum SkipReason: String, Sendable, Equatable {
  case exists, suppressed, missing
}

public struct AddItemsResult: Sendable, Equatable {
  public var added: [String]
  public var skipped: [SkippedMember]

  public init(added: [String], skipped: [SkippedMember]) {
    self.added = added
    self.skipped = skipped
  }

  public struct SkippedMember: Sendable, Equatable {
    public var itemId: String
    public var reason: SkipReason

    public init(itemId: String, reason: SkipReason) {
      self.itemId = itemId
      self.reason = reason
    }
  }
}

public struct RenameOptions: Sendable {
  public var actor: CollectionCreator
  public var agentRunId: String?
  public init(actor: CollectionCreator, agentRunId: String? = nil) {
    self.actor = actor
    self.agentRunId = agentRunId
  }
}

/// Collection domain service. Port of `core/collection-service.ts`.
public struct CollectionService: Sendable {
  private let db: Db
  private let repos: Repositories
  private let events: EventBus
  private let clock: Clock
  private let audit: AuditService
  private let ids: IdGenerator

  public init(db: Db, repos: Repositories, events: EventBus, clock: Clock,
              audit: AuditService, ids: IdGenerator? = nil) {
    self.db = db
    self.repos = repos
    self.events = events
    self.clock = clock
    self.audit = audit
    self.ids = ids ?? uuid
  }

  private var collections: CollectionRepo { repos.collections }

  private func changed(_ itemIds: [String] = []) {
    db.afterCommit { [repos, events] in
      events.emit(.collectionsChanged)
      if !itemIds.isEmpty {
        let list = (try? repos.items.getMany(itemIds)) ?? []
        events.emit(.itemUpdated(ItemsChangedEvent(
          reason: .updated, ids: itemIds,
          summaries: (try? repos.items.summaries(list)) ?? [])))
      }
    }
  }

  /// Throws `NOT_FOUND`.
  public func get(_ id: String) throws -> Collection {
    guard let c = try collections.get(id) else {
      throw KaError(.notFound, "Couldn't find that collection.")
    }
    return c
  }

  public func list() throws -> [CollectionSummary] {
    try collections.listSummaries()
  }

  private func validName(_ rawName: String) throws -> (name: String, nameKey: String) {
    let trimmed = rawName.trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    let nameKey = normalizeName(trimmed)
    if trimmed.isEmpty || nameKey.isEmpty { throw KaError(.validation, "Give it a name.") }
    if trimmed.count > 80 { throw KaError(.validation, "Keep the name under 80 characters.") }
    return (trimmed, nameKey)
  }

  /// True when the agent must not (re-)add `itemId` to this collection.
  public func isSuppressed(_ collection: Collection, _ itemId: String) throws -> Bool {
    try repos.suppressions.has(.collectionMember, membershipKey(collection.id, itemId))
      || repos.suppressions.has(.collectionMember, nameMemberKey(collection.nameKey, itemId))
  }

  /// Throws `VALIDATION` on an empty name, `CONFLICT` on a duplicate (normalized) name.
  @discardableResult
  public func create(_ input: CreateCollectionInput) throws -> Collection {
    try db.transaction { _ in
      let (name, nameKey) = try validName(input.name)
      if try collections.getByNameKey(nameKey) != nil {
        throw KaError(.conflict, "A collection with that name already exists.")
      }
      let now = clock.nowIso()
      let description = input.description?.trimmingCharacters(in: .whitespaces)
      let collection = Collection(
        id: ids(), name: name, nameKey: nameKey,
        description: description?.isEmpty == true ? nil : description,
        createdBy: input.createdBy, color: input.color, pinned: false,
        createdAt: now, updatedAt: now)
      try collections.insert(collection)
      var after: [String: JSONValue] = [:]
      if let data = try? JSONEncoder().encode(collection),
         let v = try? JSONDecoder().decode(JSONValue.self, from: data) {
        after["collection"] = v
      }
      audit.record(AuditInput(
        actor: input.createdBy == .user ? .user : .agent,
        action: AuditActions.createCollection, entity: "collection", entityId: collection.id,
        after: .object(after), agentRunId: input.agentRunId))
      changed()
      return collection
    }
  }

  /// Agents may not rename user-created collections (`CONFLICT`).
  @discardableResult
  public func rename(_ id: String, name: String, description: String? = nil,
                     opts: RenameOptions) throws -> Collection {
    // `description: nil` means "keep" (TS `undefined`); pass `.some(nil)`… — Swift can't express
    // that on a plain optional, so a separate overload carries the explicit-null case.
    try rename(id, name: name, descriptionSet: nil, keepDescription: true, opts: opts)
  }

  /// Variant with an explicit description value (set or clear).
  @discardableResult
  public func rename(_ id: String, name: String, descriptionSet description: String?,
                     opts: RenameOptions) throws -> Collection {
    try rename(id, name: name, descriptionSet: description, keepDescription: false, opts: opts)
  }

  private func rename(_ id: String, name: String, descriptionSet description: String?,
                      keepDescription: Bool, opts: RenameOptions) throws -> Collection {
    try db.transaction { _ in
      let current = try get(id)
      if opts.actor == .agent && current.createdBy == .user {
        throw KaError(.conflict, "That collection was named by the user.")
      }
      let next = try validName(name)
      if let clash = try collections.getByNameKey(next.nameKey), clash.id != id {
        throw KaError(.conflict, "A collection with that name already exists.")
      }
      let now = clock.nowIso()
      let nextDescription: String? = keepDescription
        ? current.description
        : (description?.trimmingCharacters(in: .whitespaces).isEmpty == false ? description : nil)
      try collections.update(id, patch: [
        ("name", next.name), ("nameKey", next.nameKey),
        ("description", nextDescription), ("updatedAt", now)
      ])
      func col(_ c: Collection) -> JSONValue {
        var o: [String: JSONValue] = ["name": .string(c.name), "nameKey": .string(c.nameKey)]
        o["description"] = c.description.map { .string($0) } ?? .null
        return .object(o)
      }
      audit.record(AuditInput(
        actor: opts.actor == .user ? .user : .agent,
        action: AuditActions.renameCollection, entity: "collection", entityId: id,
        before: col(current),
        after: .object([
          "name": .string(next.name), "nameKey": .string(next.nameKey),
          "description": nextDescription.map { .string($0) } ?? .null
        ]),
        agentRunId: opts.agentRunId))
      changed()
      var out = current
      out.name = next.name
      out.nameKey = next.nameKey
      out.description = nextDescription
      out.updatedAt = now
      return out
    }
  }

  public func delete(_ id: String, opts: RenameOptions) throws {
    try db.transaction { _ in
      let current = try get(id)
      let members = try collections.members(id)
      try collections.delete(id)
      audit.record(AuditInput(
        actor: opts.actor == .user ? .user : .agent,
        action: AuditActions.deleteCollection, entity: "collection", entityId: id,
        before: .object([
          "collection": (try? JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(current))) ?? .null,
          "members": .array(members.compactMap {
            try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode($0))
          })
        ])))
      changed(members.map(\.itemId))
    }
  }

  /// Add members. Agent actors skip suppressed pairs; the user actor clears suppressions.
  /// Existing members and unknown items are skipped, never errors.
  @discardableResult
  public func addItems(_ id: String, members: [AddMemberInput],
                       opts: RenameOptions) throws -> AddItemsResult {
    try db.transaction { _ in
      let collection = try get(id)
      let now = clock.nowIso()
      var result = AddItemsResult(added: [], skipped: [])
      for m in members {
        if try repos.items.get(m.itemId) == nil {
          result.skipped.append(.init(itemId: m.itemId, reason: .missing))
          continue
        }
        if try collections.getMember(collectionId: id, itemId: m.itemId) != nil {
          result.skipped.append(.init(itemId: m.itemId, reason: .exists))
          continue
        }
        if opts.actor == .user {
          try repos.suppressions.remove(.collectionMember, membershipKey(id, m.itemId))
          try repos.suppressions.remove(.collectionMember, nameMemberKey(collection.nameKey, m.itemId))
        } else if try isSuppressed(collection, m.itemId) {
          result.skipped.append(.init(itemId: m.itemId, reason: .suppressed))
          continue
        }
        let reason = m.reason?.trimmingCharacters(in: .whitespaces)
        let membership = CollectionItem(
          collectionId: id, itemId: m.itemId, confidence: m.confidence,
          reason: reason?.isEmpty == true ? nil : reason,
          addedBy: MembershipActor(rawValue: opts.actor.rawValue) ?? .agent,
          agentRunId: opts.agentRunId, addedAt: now)
        try collections.addMember(membership)
        audit.record(AuditInput(
          actor: opts.actor == .user ? .user : .agent,
          action: AuditActions.addToCollection, entity: "collection_item",
          entityId: membershipKey(id, m.itemId),
          after: (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(membership))),
          agentRunId: opts.agentRunId))
        result.added.append(m.itemId)
      }
      if !result.added.isEmpty {
        try collections.update(id, patch: [("updatedAt", now)])
        changed(result.added)
      }
      return result
    }
  }

  /// Remove one member. A user removal writes both `collection_member` suppression keys.
  public func removeItem(_ id: String, itemId: String, opts: RenameOptions) throws {
    try db.transaction { _ in
      let collection = try get(id)
      guard let membership = try collections.getMember(collectionId: id, itemId: itemId) else { return }
      let now = clock.nowIso()
      try collections.removeMember(collectionId: id, itemId: itemId)
      if opts.actor == .user {
        try repos.suppressions.add(.collectionMember, membershipKey(id, itemId), now)
        try repos.suppressions.add(.collectionMember, nameMemberKey(collection.nameKey, itemId), now)
      }
      audit.record(AuditInput(
        actor: opts.actor == .user ? .user : .agent,
        action: AuditActions.removeFromCollection, entity: "collection_item",
        entityId: membershipKey(id, itemId),
        before: (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(membership)))))
      try collections.update(id, patch: [("updatedAt", now)])
      changed([itemId])
    }
  }
}
