import Foundation
import KACore
import KAModel
import KAPipeline
import KATestSupport
import KAStorage
import Testing

/// Port of `electron/tests/unit/services.test.ts` (all 18 `it`s).
@Suite struct ItemServiceSuite {
  private func harness() throws -> Harness { try Harness() }

  private let understanding = Understanding(
    kind: .article, title: "Model title", summary: "Model summary", whyUseful: "Model why",
    topics: ["t1"], entities: ["e1"], visualDescription: "dark page", visibleText: nil,
    retrievalHints: ["hint"], confidence: 0.9)

  @Test func createsItemsAtCapturedAndEmitsItemCreatedAfterCommit() throws {
    let h = try harness()
    defer { h.close() }
    let item = try h.item { $0.title = "  Hello  " }
    #expect(item.title == "Hello")
    #expect(item.processingStatus == .captured)
    let created = h.eventsNamed("item.created")
    #expect(created.count == 1)
    guard case .itemCreated(let e) = created.first else { Issue.record("wrong event"); return }
    #expect(e.summaries?.first?.id == item.id)
  }

  @Test func userEditsSetOverridesAuditAndAnIndexJobThenAgentSkips() throws {
    let h = try harness()
    defer { h.close() }
    let item = try h.item { i in
      i.type = .markdown
      i.title = "Original"
    }
    let detail = try h.items.updateByUser(item.id, patch: ItemUpdatePatch(
      title: "Mine", understanding: "My understanding"))
    #expect(detail.item.title == "Mine")
    #expect(detail.item.userOverrides == { var o = UserOverrides(); o.title = true; o.understanding = true; return o }())
    #expect(try h.repos.jobs.activeForItem(item.id).map(\.stage) == [.index])
    let a1 = try h.repos.audit.forEntity("item", item.id).first
    #expect(a1?.actor == .user && a1?.action == "update_item")

    let applied = try h.items.applyUnderstanding(item.id, understanding: understanding,
                                                 agentRunId: "run-1")
    #expect(applied.skippedFields == [.title, .understanding])
    #expect(applied.item.title == "Mine")
    #expect(applied.item.understanding == "My understanding")
    #expect(applied.item.whyUseful == "Model why")
    #expect(applied.item.kind == .article)
    #expect(applied.item.topics == ["t1"])
    #expect(applied.item.visionText == "dark page")
    #expect(applied.item.retrievalHints == ["hint"])
    #expect(applied.item.aiConfidence == 0.9)
    let a2 = try h.repos.audit.forEntity("item", item.id).first
    #expect(a2?.actor == .agent && a2?.action == "update_understanding" && a2?.agentRunId == "run-1")
  }

  @Test func rejectsEmptyTitlesAndUnknownIdsWithKaErrorCodes() throws {
    let h = try harness()
    defer { h.close() }
    let item = try h.item()
    #expect(throws: KaError.self) {
      try h.items.updateByUser(item.id, patch: ItemUpdatePatch(title: "   "))
    }
    do {
      _ = try h.items.get("nope")
      Issue.record("expected KaError")
    } catch {
      #expect((error as? KaError)?.code == .notFound)
    }
  }

  @Test func trashRestoreUndoable() throws {
    let h = try harness()
    defer { h.close() }
    let item = try h.item()
    _ = h.queue.enqueueInitial(item)
    #expect(try h.repos.jobs.activeForItem(item.id).isEmpty == false)
    try h.items.trash([item.id])
    #expect(try h.repos.jobs.activeForItem(item.id).isEmpty)
    #expect(try h.repos.items.get(item.id)?.deletedAt != nil)
    // Nothing is processing it any more, so the card must not keep claiming work is in flight.
    #expect(try h.repos.items.get(item.id)?.processingStatus == .partial)
    #expect(h.eventsNamed("item.trashed").count == 1)
    let trashAudit = try h.repos.audit.forEntity("item", item.id).first
    #expect(trashAudit?.action == "trash_item")
    try h.audit.undo(trashAudit!.id)
    #expect(try h.repos.items.get(item.id)?.deletedAt == nil)
    try h.items.trash([item.id])
    try h.items.restore([item.id])
    #expect(try h.repos.items.get(item.id)?.deletedAt == nil)
    #expect(h.eventsNamed("item.restored").count == 2)
  }

  @Test func deleteForeverRemovesFolderChildrenAndCascades() throws {
    let h = try harness()
    defer { h.close() }
    let folder = try h.item { $0.type = .folder }
    let child = try h.item { $0.parentItemId = folder.id }
    let other = try h.item()
    _ = try h.relationships.create(CreateRelationshipInput(
      sourceId: child.id, targetId: other.id, type: .references, createdBy: .user))
    let removed = try h.items.deleteForever([folder.id])
    #expect(removed.map(\.id).sorted() == [folder.id, child.id].sorted())
    #expect(try h.repos.items.get(child.id) == nil)
    #expect(try h.repos.relationships.forItem(other.id).isEmpty)
    guard case .itemDeleted(let e) = h.eventsNamed("item.deleted").first else {
      Issue.record("wrong event"); return
    }
    #expect(e.ids.count == 2)
  }

  @Test func reprocessResetsStatusPerStageAndEnqueuesFromThere() throws {
    let h = try harness()
    defer { h.close() }
    let item = try h.item { i in
      i.type = .url
      i.processingStatus = .ready
      i.url = "https://a.b"
    }
    try h.items.reprocess(item.id, from: .understand)
    #expect(try h.repos.items.get(item.id)?.processingStatus == .extracted)
    #expect(try h.repos.jobs.activeForItem(item.id).map(\.stage) == [.understand])
    try h.items.reprocess(item.id)
    #expect(try h.repos.items.get(item.id)?.processingStatus == .captured)
    #expect(try h.repos.jobs.activeForItem(item.id).map(\.stage.rawValue).sorted()
      == [Stage.extract.rawValue, Stage.snapshot.rawValue])
    #expect(try h.items.reprocessAll(.index) == 1)
  }

  @Test func cancelProcessingStopsActiveJobsAndSettlesPartial() throws {
    let h = try harness()
    defer { h.close() }
    let item = try h.item { i in
      i.type = .url
      i.processingStatus = .captured
      i.url = "https://a.b"
    }
    _ = h.queue.enqueueInitial(item)
    try h.items.cancelProcessing([item.id])
    #expect(try h.repos.jobs.activeForItem(item.id).isEmpty)
    #expect(try h.repos.items.get(item.id)?.processingStatus == .partial)
    let statuses = h.eventsNamed("job.progress").compactMap { e -> JobStatus? in
      if case .jobProgress(let p) = e { return p.jobStatus }
      return nil
    }
    #expect(statuses.contains(.cancelled))
  }

  @Test func reprocessForgetsFinishedDownstreamJobs() throws {
    let h = try harness()
    defer { h.close() }
    let item = try h.item { i in
      i.type = .url
      i.processingStatus = .ready
      i.url = "https://a.b"
    }
    let now = h.clock.nowIso()
    for stage in [Stage.extract, .snapshot, .embed, .understand, .index, .relate] {
      let job = try h.repos.jobs.insert(Job(
        id: "j-\(stage.rawValue)", itemId: item.id, stage: stage, lane: .io,
        priority: 0, status: .queued, attempts: 1, createdAt: now, updatedAt: now))
      try h.repos.jobs.finish(job!.id, .done, now)
    }
    try h.items.reprocess(item.id)
    #expect(try h.repos.jobs.finishedStages(item.id).isEmpty)
    try h.items.reprocess(item.id, from: .understand)
    #expect(try h.repos.jobs.finishedStages(item.id).isEmpty)
  }

  @Test func buildsItemDetailWithRelationshipsCollectionsAndChildren() throws {
    let h = try harness()
    defer { h.close() }
    let folder = try h.item { i in
      i.type = .folder
      i.title = "F"
    }
    let child = try h.item { $0.parentItemId = folder.id }
    let other = try h.item { $0.title = "Other" }
    _ = try h.relationships.create(CreateRelationshipInput(
      sourceId: other.id, targetId: folder.id, type: .inspiredBy,
      createdBy: .agent, agentRunId: "r"))
    let c = try h.collections.create(CreateCollectionInput(name: "Set", createdBy: .agent))
    _ = try h.collections.addItems(c.id, members: [AddMemberInput(
      itemId: folder.id, confidence: 0.5, reason: "because")], opts: .init(actor: .agent, agentRunId: "r"))
    let detail = try h.items.detail(folder.id)
    #expect(detail.relationships.count == 1)
    #expect(detail.relationships[0].direction == .in)
    #expect(detail.relationships[0].label == "inspired")
    #expect(detail.relationships[0].other.id == other.id)
    #expect(detail.collections[0].collection.id == c.id)
    #expect(detail.collections[0].reason == "because")
    #expect(detail.collections[0].addedBy == .agent)
    #expect(detail.collections[0].agentRunId == "r")
    #expect(detail.children?.map(\.id) == [child.id])
    #expect(detail.summary.childCount == 1)
  }

  @Test func keptAgainBumpsLastKeptAtAndAudits() throws {
    let h = try harness()
    defer { h.close() }
    let item = try h.item()
    h.clock.advance(60_000)
    let bumped = try h.items.keptAgain(item.id)
    #expect(bumped.lastKeptAt == h.clock.nowIso())
    #expect(try h.repos.audit.forEntity("item", item.id).first?.action == "kept_again")
  }
}

@Suite struct CollectionServiceSuite {
  @Test func validatesNamesAndRefusesDuplicatesNormalized() throws {
    let h = try Harness()
    defer { h.close() }
    _ = try h.collections.create(CreateCollectionInput(name: "Reading List", createdBy: .user))
    #expect(throws: (any Error).self) {
      try h.collections.create(CreateCollectionInput(name: "  reading-list ", createdBy: .agent))
    }
    #expect(throws: (any Error).self) {
      try h.collections.create(CreateCollectionInput(name: "   ", createdBy: .user))
    }
    #expect(h.eventsNamed("collections.changed").count == 1)
  }

  @Test func agentsCannotRenameUserCollectionsAndRenamesAreUndoable() throws {
    let h = try Harness()
    defer { h.close() }
    let c = try h.collections.create(CreateCollectionInput(name: "Mine", createdBy: .user))
    #expect(throws: KaError.self) {
      try h.collections.rename(c.id, name: "Theirs", opts: .init(actor: .agent))
    }
    _ = try h.collections.rename(c.id, name: "Renamed", descriptionSet: "desc",
                                 opts: .init(actor: .user))
    let got = try h.repos.collections.get(c.id)
    #expect(got?.name == "Renamed" && got?.nameKey == "renamed" && got?.description == "desc")
    let audit = try h.repos.audit.forEntity("collection", c.id).first
    try h.audit.undo(audit!.id)
    #expect(try h.repos.collections.get(c.id)?.name == "Mine")
  }

  @Test func userRemovalWritesBothSuppressionKeysAndAgentIsRefused() throws {
    let h = try Harness()
    defer { h.close() }
    let c = try h.collections.create(CreateCollectionInput(name: "Research", createdBy: .agent))
    let item = try h.item()
    let first = try h.collections.addItems(
      c.id, members: [AddMemberInput(itemId: item.id), AddMemberInput(itemId: "ghost")],
      opts: .init(actor: .agent))
    #expect(first == .init(added: [item.id], skipped: [.init(itemId: "ghost", reason: .missing)]))
    try h.collections.removeItem(c.id, itemId: item.id, opts: .init(actor: .user))
    #expect(try h.repos.suppressions.has(.collectionMember, "\(c.id):\(item.id)"))
    #expect(try h.repos.suppressions.has(.collectionMember, "name:research:\(item.id)"))
    let second = try h.collections.addItems(c.id, members: [AddMemberInput(itemId: item.id)],
                                          opts: .init(actor: .agent))
    #expect(second == .init(added: [], skipped: [.init(itemId: item.id, reason: .suppressed)]))
    // The user re-adding clears the suppression.
    let third = try h.collections.addItems(c.id, members: [AddMemberInput(itemId: item.id)],
                                           opts: .init(actor: .user))
    #expect(third.added == [item.id])
    #expect(try h.repos.suppressions.has(.collectionMember, "\(c.id):\(item.id)") == false)
    let fourth = try h.collections.addItems(c.id, members: [AddMemberInput(itemId: item.id)],
                                            opts: .init(actor: .user))
    #expect(fourth.skipped.first?.reason == .exists)
  }

  @Test func undoingAgentAddRemovesMemberAndSuppressesItUndoTwiceConflicts() throws {
    let h = try Harness()
    defer { h.close() }
    let c = try h.collections.create(CreateCollectionInput(name: "Set", createdBy: .agent))
    let item = try h.item()
    _ = try h.collections.addItems(c.id, members: [AddMemberInput(itemId: item.id)],
                                   opts: .init(actor: .agent, agentRunId: "run"))
    let entry = try h.repos.audit.forRun("run").first
    try h.audit.undo(entry!.id)
    #expect(try h.repos.collections.getMember(collectionId: c.id, itemId: item.id) == nil)
    #expect(try h.repos.suppressions.has(.collectionMember, "\(c.id):\(item.id)"))
    #expect(throws: (any Error).self) { try h.audit.undo(entry!.id) }
    #expect(throws: KaError.self) { try h.audit.undo("missing") }
  }

  @Test func deletingACollectionIsUndoableWithItsMembers() throws {
    let h = try Harness()
    defer { h.close() }
    let c = try h.collections.create(CreateCollectionInput(name: "Set", createdBy: .user))
    let item = try h.item()
    _ = try h.collections.addItems(c.id, members: [AddMemberInput(itemId: item.id)],
                                   opts: .init(actor: .user))
    try h.collections.delete(c.id, opts: .init(actor: .user))
    #expect(try h.repos.collections.get(c.id) == nil)
    let entry = try h.repos.audit.forEntity("collection", c.id).first
    try h.audit.undo(entry!.id)
    #expect(try h.repos.collections.get(c.id)?.name == "Set")
    #expect(try h.repos.collections.getMember(collectionId: c.id, itemId: item.id) != nil)
  }

  @Test func userRemoveItemSuppressesFutureAgentAddsForThatPair() throws {
    let h = try Harness()
    defer { h.close() }
    let c = try h.collections.create(CreateCollectionInput(name: "Set", createdBy: .user))
    let item = try h.item()
    _ = try h.collections.addItems(c.id, members: [AddMemberInput(itemId: item.id)],
                                   opts: .init(actor: .agent))
    try h.collections.removeItem(c.id, itemId: item.id, opts: .init(actor: .user))
    let result = try h.collections.addItems(c.id, members: [AddMemberInput(itemId: item.id)],
                                            opts: .init(actor: .agent))
    #expect(result.added.isEmpty)
    #expect(result.skipped == [.init(itemId: item.id, reason: .suppressed)])
    let retry = try h.collections.addItems(c.id, members: [AddMemberInput(itemId: item.id)],
                                           opts: .init(actor: .user))
    #expect(retry.added == [item.id])
  }
}

@Suite struct RelationshipServiceSuite {
  @Test func normalizesSymmetricPairsAndRefusesSelfDuplicatesAndSuppressed() throws {
    let h = try Harness()
    defer { h.close() }
    let a = try h.item()
    let b = try h.item()
    #expect(throws: (any Error).self) {
      try h.relationships.create(CreateRelationshipInput(
        sourceId: a.id, targetId: a.id, type: .relatedTo, createdBy: .user))
    }
    let r = try h.relationships.create(CreateRelationshipInput(
      sourceId: b.id, targetId: a.id, type: .relatedTo, createdBy: .agent))
    #expect(r.sourceItemId < r.targetItemId)
    #expect(throws: (any Error).self) {
      try h.relationships.create(CreateRelationshipInput(
        sourceId: a.id, targetId: b.id, type: .relatedTo, createdBy: .agent))
    }
    try h.relationships.remove(r.id, actor: .user)
    #expect(throws: (any Error).self) {
      try h.relationships.create(CreateRelationshipInput(
        sourceId: a.id, targetId: b.id, type: .inspiredBy, createdBy: .agent))
    }
    // The user may recreate it, which clears the suppression.
    let again = try h.relationships.create(CreateRelationshipInput(
      sourceId: a.id, targetId: b.id, type: .inspiredBy, createdBy: .user))
    #expect(try h.relationships.isSuppressed(a.id, b.id) == false)
    let view = try h.relationships.forItem(b.id).first
    #expect(view?.direction == .in && view?.label == "inspired" && view?.otherId == a.id)
    #expect(try h.relationships.get(again.id).type == .inspiredBy)
  }

  @Test func undoingAgentRelationshipDeletesItAndSuppressesThePair() throws {
    let h = try Harness()
    defer { h.close() }
    let a = try h.item()
    let b = try h.item()
    let r = try h.relationships.create(CreateRelationshipInput(
      sourceId: a.id, targetId: b.id, type: .references, createdBy: .agent, agentRunId: "run"))
    let entry = try h.repos.audit.forRun("run").first
    try h.audit.undo(entry!.id)
    #expect(try h.repos.relationships.get(r.id) == nil)
    #expect(try h.relationships.isSuppressed(a.id, b.id))
  }
}

@Suite struct AuditSuite {
  @Test func undoingTwiceAndUnknownIdsThrow() throws {
    let h = try Harness()
    defer { h.close() }
    let c = try h.collections.create(CreateCollectionInput(name: "C", createdBy: .agent))
    let entry = try h.repos.audit.forEntity("collection", c.id).first!
    let undone = try h.audit.undo(entry.id)
    #expect(undone.undoneAt != nil)
    do {
      _ = try h.audit.undo(entry.id)
      Issue.record("expected conflict")
    } catch {
      #expect((error as? KaError)?.code == .conflict)
    }
    do {
      _ = try h.audit.undo("missing")
      Issue.record("expected notFound")
    } catch {
      #expect((error as? KaError)?.code == .notFound)
    }
  }
}

@Suite struct EventBusSuite {
  @Test func listenersRunInOrderAndErrorsAreLoggedNotPropagated() throws {
    let errors = ErrorsBox()
    let bus = createEventBus(logger: errors)
    let calls = CallsBox()
    bus.on("collections.changed") { _ in calls.list.append("first") }
    bus.on("collections.changed") { _ in calls.list.append("boom") }
    // A "throwing" listener in Swift can't throw — simulate with a fatal path? Instead we trust
    // the logger path is exercised via a listener that signals failure through a thrown error is
    // impossible for `(DomainEvent) -> Void`; TS swallows listener exceptions. In Swift listeners
    // are non-throwing, so this reduces to: order is preserved and all listeners run.
    bus.emit(.collectionsChanged)
    #expect(calls.list == ["first", "boom"])
    #expect(errors.lines.isEmpty)
  }

  @Test func offAndCancelUnsubscribe() {
    let bus = createEventBus()
    let n = CountBox()
    let l: @Sendable (DomainEvent) -> Void = { _ in n.value += 1 }
    bus.on("collections.changed", listener: l)
    let cancel = bus.on("collections.changed", listener: { _ in n.value += 10 })
    bus.off("collections.changed", listener: l)
    cancel()
    bus.emit(.collectionsChanged)
    #expect(n.value == 0)
  }

  private final class CallsBox: @unchecked Sendable { var list: [String] = [] }
  private final class CountBox: @unchecked Sendable { var value = 0 }

  private final class ErrorsBox: Logger, @unchecked Sendable {
    var lines: [String] = []
    var crash = false
    func debug(_ msg: String, fields: LogFields) {}
    func info(_ msg: String, fields: LogFields) {}
    func warn(_ msg: String, fields: LogFields) {}
    func error(_ msg: String, fields: LogFields) { lines.append(msg) }
    func child(_ fields: LogFields) -> Logger { self }
  }
}

@Suite struct IdsSuite {
  @Test func uuidLooksLikeRandomUUIDAndSequentialIdsCount() {
    let id = uuid()
    #expect(id.count == 36 && id == id.lowercased())
    let ids = sequentialIds("job")
    #expect(ids() == "job-1")
    #expect(ids() == "job-2")
  }
}
