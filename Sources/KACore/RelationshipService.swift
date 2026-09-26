import Foundation
import KAModel
import KAStorage

public struct CreateRelationshipInput: Sendable {
  public var sourceId: String
  public var targetId: String
  public var type: RelationshipType
  public var description: String?
  public var confidence: Double?
  public var evidence: RelationshipEvidence?
  public var createdBy: RelationshipCreator
  public var agentRunId: String?

  public init(sourceId: String, targetId: String, type: RelationshipType, description: String? = nil,
              confidence: Double? = nil, evidence: RelationshipEvidence? = nil,
              createdBy: RelationshipCreator, agentRunId: String? = nil) {
    self.sourceId = sourceId
    self.targetId = targetId
    self.type = type
    self.description = description
    self.confidence = confidence
    self.evidence = evidence
    self.createdBy = createdBy
    self.agentRunId = agentRunId
  }
}

/// A relationship as seen from one item.
public struct RelationshipView: Sendable, Equatable {
  public var relationship: Relationship
  public var direction: RelationshipDirection
  public var label: String
  public var otherId: String
}

/// Relationship domain service. Port of `core/relationship-service.ts`.
public struct RelationshipService: Sendable {
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

  private var relationships: RelationshipRepo { repos.relationships }
  private var suppressions: SuppressionRepo { repos.suppressions }
  private var items: ItemRepo { repos.items }

  private func touched(_ itemIds: [String]) {
    db.afterCommit { [repos, events] in
      let list = (try? repos.items.getMany(itemIds)) ?? []
      events.emit(.itemUpdated(ItemsChangedEvent(
        reason: .updated, ids: itemIds,
        summaries: (try? repos.items.summaries(list)) ?? [])))
    }
  }

  /**
   * Create an edge. Symmetric types are stored `source < target`. Throws `VALIDATION` for self
   * links, `NOT_FOUND` for unknown items, `CONFLICT` when the edge exists or the pair is suppressed
   * for agent/system actors.
   */
  @discardableResult
  public func create(_ input: CreateRelationshipInput) throws -> Relationship {
    try db.transaction { _ in
      if input.sourceId == input.targetId {
        throw KaError(.validation, "An item can't relate to itself.")
      }
      let (sourceItemId, targetItemId) = normalizePair(input.sourceId, input.targetId, input.type)
      let source = try items.get(sourceItemId)
      let target = try items.get(targetItemId)
      if source == nil || target == nil || source?.deletedAt != nil || target?.deletedAt != nil {
        throw KaError(.notFound, "One of those items is gone.")
      }
      if input.createdBy == .user {
        try suppressions.remove(.relationship, relationshipSuppressionKey(sourceItemId, targetItemId))
      } else if try isSuppressed(sourceItemId, targetItemId) {
        throw KaError(.conflict, "The user removed a connection between these items.")
      }
      if try relationships.find(sourceItemId, targetItemId, input.type) != nil {
        throw KaError(.conflict, "Already connected.")
      }
      let description = input.description?.trimmingCharacters(in: .whitespaces)
      let relationship = Relationship(
        id: ids(), sourceItemId: sourceItemId, targetItemId: targetItemId, type: input.type,
        description: description?.isEmpty == true ? nil : description,
        confidence: input.confidence, evidence: input.evidence,
        createdBy: input.createdBy, agentRunId: input.agentRunId, createdAt: clock.nowIso())
      try relationships.insert(relationship)
      audit.record(AuditInput(
        actor: input.createdBy == .user ? .user : (input.createdBy == .agent ? .agent : .system),
        action: AuditActions.createRelationship, entity: "relationship",
        entityId: relationship.id,
        after: (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(relationship))),
        agentRunId: input.agentRunId))
      touched([sourceItemId, targetItemId])
      return relationship
    }
  }

  /// Throws `NOT_FOUND`.
  public func get(_ id: String) throws -> Relationship {
    guard let r = try relationships.get(id) else {
      throw KaError(.notFound, "Couldn't find that connection.")
    }
    return r
  }

  /// Remove an edge. A user removal suppresses the pair for the agent.
  public func remove(_ id: String, actor: RelationshipCreator) throws {
    try db.transaction { _ in
      let r = try get(id)
      try relationships.delete(id)
      if actor == .user {
        try suppressions.add(
          .relationship, relationshipSuppressionKey(r.sourceItemId, r.targetItemId), clock.nowIso())
      }
      audit.record(AuditInput(
        actor: actor == .user ? .user : (actor == .agent ? .agent : .system),
        action: AuditActions.removeRelationship, entity: "relationship", entityId: id,
        before: (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(r)))))
      touched([r.sourceItemId, r.targetItemId])
    }
  }

  public func forItem(_ itemId: String) throws -> [RelationshipView] {
    try relationships.forItem(itemId).map { relationship in
      let direction: RelationshipDirection = relationship.sourceItemId == itemId ? .out : .in
      return RelationshipView(
        relationship: relationship, direction: direction,
        label: relationshipLabel(relationship.type, direction),
        otherId: direction == .out ? relationship.targetItemId : relationship.sourceItemId)
    }
  }

  public func isSuppressed(_ a: String, _ b: String) throws -> Bool {
    try suppressions.has(.relationship, relationshipSuppressionKey(a, b))
  }
}
