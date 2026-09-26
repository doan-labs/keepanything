import Foundation
import GRDB
import KAModel
import Testing
@testable import KAStorage

/// Port of `electron/tests/unit/repositories.test.ts`. The TS harness builds items through the
/// KACore services (not ported yet); these helpers replicate their repo-level effects directly:
/// `item()` = itemService.create defaults, `collections.create` = repo insert with normalizeName,
/// `relationships.create` = normalizePair + repo insert, `audit.record/undo` = insert/markUndone.
@Suite struct Repositories {
  private var clock = ManualClock()
  private var itemN = 0
  private var colN = 0
  private var relN = 0
  private var auditN = 0
  private var jobN = 0

  final class ManualClock: @unchecked Sendable {
    var ms: Double = 1_788_429_600_000 // 2026-09-03T10:00:00.000Z
    var nowIso: String { Date(timeIntervalSince1970: ms / 1000).iso() }
    func advance(_ byMs: Double) { ms += byMs }
  }

  private var db: Db!
  private var repos: KAStorage.Repositories!

  init() throws {
    db = try openDatabase(file: ":memory:")
    try db.migrate()
    repos = KAStorage.createRepositories(db)
  }

  private mutating func item(_ over: (inout Item) -> Void = { _ in }) throws -> Item {
    itemN += 1
    var i = Item(
      id: "item-\(itemN)", type: .text, title: "Item \(itemN)",
      createdAt: clock.nowIso, capturedAt: clock.nowIso, modifiedAt: clock.nowIso,
      lastKeptAt: clock.nowIso)
    over(&i)
    try repos.items.insert(i)
    return i
  }

  private mutating func createCollection(name: String, description: String? = nil, createdBy: CollectionCreator) throws -> Collection {
    colN += 1
    let c = Collection(
      id: "col-\(colN)", name: name, nameKey: normalizeName(name), description: description,
      createdBy: createdBy, createdAt: clock.nowIso, updatedAt: clock.nowIso)
    try repos.collections.insert(c)
    return c
  }

  private func addItems(_ collectionId: String, _ members: [(itemId: String, reason: String?, confidence: Double?)], actor: MembershipActor) throws {
    for m in members {
      try repos.collections.addMember(CollectionItem(
        collectionId: collectionId, itemId: m.itemId, confidence: m.confidence,
        reason: m.reason, addedBy: actor, addedAt: clock.nowIso))
    }
  }

  private mutating func createRelationship(sourceId: String, targetId: String, type: RelationshipType, createdBy: RelationshipCreator) throws -> Relationship {
    relN += 1
    let (a, b) = isSymmetric(type) ? normalizePair(sourceId, targetId, type) : (sourceId, targetId)
    let r = Relationship(id: "rel-\(relN)", sourceItemId: a, targetItemId: b, type: type,
                         createdBy: createdBy, createdAt: clock.nowIso)
    try repos.relationships.insert(r)
    return r
  }

  private mutating func recordAudit(actor: AuditActor, action: String, entity: String, entityId: String,
                                    before: JSONValue? = nil, after: JSONValue? = nil, agentRunId: String? = nil) throws -> AuditEntry {
    auditN += 1
    let e = AuditEntry(id: "audit-\(auditN)", actor: actor, action: action, entity: entity,
                       entityId: entityId, before: before, after: after, agentRunId: agentRunId,
                       createdAt: clock.nowIso)
    try repos.audit.insert(e)
    return e
  }

  private func undo(_ entry: AuditEntry) throws {
    try repos.audit.markUndone(entry.id, clock.nowIso)
  }

  private mutating func job(_ over: (inout Job) -> Void) throws -> Job {
    jobN += 1
    var j = Job(id: "job-\(jobN)", createdAt: clock.nowIso, updatedAt: clock.nowIso)
    over(&j)
    return j
  }

  private func fts(_ query: String) throws -> [String] {
    try db.readOnly { d in
      try String.fetchAll(d, sql: "SELECT item_id FROM items_fts WHERE items_fts MATCH ? ORDER BY rank",
                          arguments: [query])
    }
  }

  // MARK: item repository

  @Test mutating func roundTripsEveryColumn() throws {
    var meta = ItemMetadata()
    meta.og = .init()
    meta.og?.siteName = "Example"
    meta.extra = ["custom": .number(1)]
    var overrides = UserOverrides()
    overrides.title = true
    let created = try item { i in
      i.type = .url
      i.subtype = .url(.article)
      i.kind = .article
      i.title = "Batching strategies"
      i.url = "https://example.com/a"
      i.canonicalUrl = "https://example.com/a"
      i.domain = "example.com"
      i.topics = ["inference", "gpu"]
      i.entities = ["vLLM"]
      i.retrievalHints = ["cheap inference"]
      i.metadata = meta
      i.userOverrides = overrides
      i.isMissing = true
      i.aiConfidence = 0.7
      i.thumbnailPath = "x.png"
      i.mediaVersion = 3
    }
    let loaded = try repos.items.get(created.id)
    #expect(loaded == created)
    #expect(loaded?.isMissing == true)
    #expect(loaded?.metadata == meta)
  }

  @Test mutating func keepsFtsRowInSync() throws {
    let item = try item { i in i.title = "Globe animation website"; i.domain = "example.com" }
    #expect(try fts("\"globe\"") == [item.id])
    try repos.items.update(item.id, patch: [("understanding", "Landing page with warm typography")])
    #expect(try fts("\"typography\"") == [item.id])
    try repos.items.patchMetadata(item.id, patch: ["og": .object(["description": .string("inference batching")])])
    #expect(try fts("meta_text:\"batching\"") == [item.id])
    try repos.items.setDeleted([item.id], deletedAt: clock.nowIso)
    #expect(try fts("\"globe\"").isEmpty)
    try repos.items.setDeleted([item.id], deletedAt: nil)
    #expect(try fts("\"globe\"") == [item.id])
    try repos.items.deleteForever([item.id])
    #expect(try fts("\"globe\"").isEmpty)
    #expect(try repos.items.get(item.id) == nil)
  }

  @Test mutating func buildsSummariesWithMediaUrls() throws {
    let folder = try item { i in i.type = .folder; i.title = "Research" }
    let child1 = try item { i in
      i.type = .image; i.title = "a"; i.parentItemId = folder.id
      i.thumbnailPath = "a.png"; i.mediaVersion = 2
    }
    _ = try item { i in i.type = .text; i.title = "b"; i.parentItemId = folder.id }
    let collection = try createCollection(name: "mnismt", createdBy: .user)
    try addItems(collection.id, [(itemId: folder.id, reason: nil, confidence: nil)], actor: .user)
    try repos.items.update(folder.id, patch: [("understanding", String(repeating: "x", count: 400))])

    let summary = try repos.items.summary(folder.id)
    #expect(summary?.childCount == 2)
    #expect(summary?.childThumbnailUrls == ["ka-media://local/thumbs/a.png?v=2"])
    #expect(summary?.collectionIds == [collection.id])
    #expect(summary?.understanding?.count == 160)
    #expect(summary?.thumbnailUrl == nil)
    #expect(try repos.items.summary(child1.id)?.thumbnailUrl == "ka-media://local/thumbs/a.png?v=2")
  }

  @Test mutating func listsViewsCorrectly() throws {
    let folder = try item { i in i.type = .folder; i.title = "F" }
    let child = try item { i in i.type = .text; i.title = "child"; i.parentItemId = folder.id }
    let link = try item { i in i.type = .url; i.title = "link"; i.url = "https://x.y" }
    let ready = try item { i in
      i.type = .pdf; i.title = "old ready"; i.processingStatus = .ready
      i.capturedAt = "2026-01-01T00:00:00.000Z"
    }
    let trashed = try item { i in i.type = .image; i.title = "gone" }
    try repos.items.setDeleted([trashed.id], deletedAt: clock.nowIso)
    func ids(_ view: ItemsView, _ extra: (inout ItemListQuery) -> Void = { _ in }) throws -> [String] {
      var q = ItemListQuery(view: view)
      extra(&q)
      return try repos.items.list(q).map(\.id)
    }

    let library = try ids(.library)
    #expect(library.contains(folder.id) && library.contains(link.id) && library.contains(ready.id))
    #expect(!library.contains(child.id) && !library.contains(trashed.id))
    #expect(try ids(.links) == [link.id])
    let files = try ids(.files)
    #expect(files.contains(folder.id) && files.contains(ready.id) && !files.contains(link.id))
    #expect(try ids(.trash) == [trashed.id])
    #expect(try ids(.library, { $0.types = [.pdf] }) == [ready.id])
    let collection = try createCollection(name: "C", createdBy: .user)
    try addItems(collection.id, [(itemId: link.id, reason: nil, confidence: nil)], actor: .user)
    #expect(try ids(.collection, { $0.collectionId = collection.id }) == [link.id])
  }

  @Test mutating func findsDuplicatesAndCountsStats() throws {
    let a = try item { i in i.contentHash = "abc" }
    let b = try item { i in i.type = .url; i.url = "https://a.b/c"; i.canonicalUrl = "https://a.b/c" }
    #expect(try repos.items.findByHash("abc")?.id == a.id)
    #expect(try repos.items.findByCanonicalUrl("https://a.b/c")?.id == b.id)
    #expect(try repos.items.stats() == .init(items: 2, connections: 0, collections: 0, processing: 2))
  }

  // MARK: collection repository

  @Test mutating func storesCollectionsMembershipsAndCovers() throws {
    let c = try createCollection(name: "Local LLM inference research", description: "d", createdBy: .agent)
    #expect(c.createdBy == .agent)
    #expect(try repos.collections.getByNameKey("local llm inference research")?.id == c.id)
    let withThumb = try item { i in i.thumbnailPath = "t.png" }
    let plain = try item()
    try addItems(c.id, [
      (itemId: withThumb.id, reason: "why", confidence: 0.8),
      (itemId: plain.id, reason: nil, confidence: nil)
    ], actor: .agent)
    let summary = try repos.collections.listSummaries().first
    #expect(summary?.count == 2)
    #expect(summary?.coverThumbnailUrls == ["ka-media://local/thumbs/t.png?v=1"])
    let member = try repos.collections.getMember(collectionId: c.id, itemId: withThumb.id)
    #expect(member?.reason == "why" && member?.confidence == 0.8 && member?.addedBy == .agent)
    #expect(try repos.collections.membershipsForItem(plain.id).count == 1)
    try repos.collections.delete(c.id)
    #expect(try repos.collections.membershipsForItem(plain.id).isEmpty)
  }

  // MARK: relationship repository

  @Test mutating func storesEdgesAndFindsFromEitherSide() throws {
    let a = try item()
    let b = try item()
    let r = try createRelationship(sourceId: b.id, targetId: a.id, type: .relatedTo, createdBy: .user)
    #expect([r.sourceItemId, r.targetItemId] == [a.id, b.id].sorted())
    #expect(try repos.relationships.forItem(a.id).count == 1)
    #expect(try repos.relationships.between(b.id, a.id).count == 1)
    #expect(try repos.relationships.find(r.sourceItemId, r.targetItemId, .relatedTo)?.id == r.id)
    #expect(try repos.relationships.count() == 1)
  }

  // MARK: job repository

  @Test mutating func refusesSecondActiveJobForSameItemAndStage() throws {
    let item = try item()
    #expect(try repos.jobs.insert(job { $0.id = "a"; $0.itemId = item.id }) != nil)
    #expect(try repos.jobs.insert(job { $0.id = "b"; $0.itemId = item.id }) == nil)
    #expect(try repos.jobs.insert(job { $0.id = "c"; $0.itemId = item.id; $0.stage = .thumbnail }) != nil)
  }

  @Test mutating func claimsByPriorityThenAgeHonorsRunAfter() throws {
    let a = try item()
    let b = try item()
    let c = try item()
    _ = try repos.jobs.insert(job { $0.id = "low"; $0.itemId = a.id; $0.priority = 1; $0.createdAt = "2026-01-01T00:00:00.000Z" })
    _ = try repos.jobs.insert(job { $0.id = "high"; $0.itemId = b.id; $0.priority = 9 })
    _ = try repos.jobs.insert(job { $0.id = "later"; $0.itemId = c.id; $0.priority = 99; $0.runAfter = "2026-09-03T10:05:00.000Z" })
    let first = try repos.jobs.claim(.io, clock.nowIso)
    #expect(first?.id == "high")
    #expect(first?.status == .running)
    #expect(first?.attempts == 1)
    #expect(try repos.jobs.claim(.io, clock.nowIso)?.id == "low")
    #expect(try repos.jobs.claim(.io, clock.nowIso) == nil)
    #expect(try repos.jobs.claim(.ai, clock.nowIso) == nil)
    clock.advance(5 * 60_000)
    #expect(try repos.jobs.claim(.io, clock.nowIso)?.id == "later")
  }

  @Test mutating func finishesRequeuesParksCancelsAndResets() throws {
    let item = try item()
    _ = try repos.jobs.insert(job { $0.id = "j"; $0.itemId = item.id })
    let claimed = try repos.jobs.claim(.io, clock.nowIso)
    #expect(claimed?.id == "j")
    try repos.jobs.requeue("j", "2026-09-03T10:00:30.000Z", clock.nowIso, lastError: "boom")
    var j = try repos.jobs.get("j")
    #expect(j?.status == .queued && j?.runAfter == "2026-09-03T10:00:30.000Z" && j?.lastError == "boom" && j?.attempts == 1)
    try repos.jobs.park("j", nil, clock.nowIso)
    j = try repos.jobs.get("j")
    #expect(j?.status == .queued && j?.attempts == 0 && j?.runAfter == nil)
    _ = try repos.jobs.claim(.io, clock.nowIso)
    #expect(try repos.jobs.resetRunning(3, clock.nowIso) == .init(requeued: 1, failed: 0))
    _ = try repos.jobs.claim(.io, clock.nowIso)
    try db.run { d in try d.execute(sql: "UPDATE jobs SET attempts = 3 WHERE id = 'j'") }
    #expect(try repos.jobs.resetRunning(3, clock.nowIso) == .init(requeued: 0, failed: 1))
    j = try repos.jobs.get("j")
    #expect(j?.status == .failed && j?.lastError == "crashed")
    #expect(try repos.jobs.finishedStages(item.id) == [.extract])

    _ = try repos.jobs.insert(job { $0.id = "k"; $0.itemId = item.id; $0.stage = .thumbnail })
    #expect(try repos.jobs.cancelForItems([item.id], clock.nowIso).map(\.id) == ["k"])
    #expect(try repos.jobs.activeForItem(item.id).isEmpty)
    #expect(try repos.jobs.activeProgress().isEmpty)
  }

  @Test mutating func reEnqueuedStageUnfinishedUntilLatestFinishes() throws {
    let item = try item()
    _ = try repos.jobs.insert(job { $0.id = "first"; $0.itemId = item.id; $0.createdAt = "2026-01-01T00:00:00.000Z" })
    try repos.jobs.finish("first", .done, clock.nowIso)
    #expect(try repos.jobs.finishedStages(item.id) == [.extract])
    _ = try repos.jobs.insert(job { $0.id = "second"; $0.itemId = item.id })
    #expect(try repos.jobs.finishedStages(item.id).isEmpty)
    #expect(try repos.jobs.latestPerStage(item.id)[.extract]?.id == "second")
  }

  @Test mutating func exposesBatchJobsAndProgressRows() throws {
    let item = try item()
    _ = try repos.jobs.insert(job { $0.id = "b"; $0.batchId = "batch"; $0.stage = .organizeBatch; $0.lane = .ai })
    _ = try repos.jobs.insert(job { $0.id = "i"; $0.itemId = item.id })
    #expect(try repos.jobs.activeForBatch("batch", .organizeBatch)?.id == "b")
    #expect(try repos.jobs.latestForBatch("batch", .organizeBatch)?.id == "b")
    let progress = try repos.jobs.activeProgress()
    #expect(progress.contains(JobProgress(itemId: nil, batchId: "batch", processingStatus: nil,
                                          stage: .organizeBatch, jobStatus: .queued, attempts: 0)))
    #expect(progress.contains(JobProgress(itemId: item.id, batchId: nil, processingStatus: .captured,
                                          stage: .extract, jobStatus: .queued, attempts: 0)))
  }

  // MARK: embedding, agent run, audit and suppression repositories

  @Test mutating func roundTripsVectorsAndReplacesPerItem() throws {
    let item = try item()
    let row = EmbeddingRow(itemId: item.id, chunkIndex: 0, role: .summary, content: "memory",
                           model: "m", dims: 4, vector: [0.1, 0.2, 0.3, 0.4])
    var second = row
    second.chunkIndex = 1
    second.role = .body
    try repos.embeddings.replaceForItem(item.id, rows: [row, second])
    let loaded = try repos.embeddings.forItem(item.id)
    #expect(loaded.count == 2)
    #expect(loaded[0].vector == row.vector)
    #expect(try repos.embeddings.allForModel("m").count == 2)
    #expect(try repos.embeddings.countForModel("other") == 0)
    try repos.embeddings.replaceForItem(item.id, rows: [row])
    #expect(try repos.embeddings.forItem(item.id).count == 1)
  }

  @Test mutating func storesAgentRunsAndListsSummaries() throws {
    let item = try item()
    try repos.agentRuns.insert(AgentRunDetail(summary: AgentRunSummary(
      id: "run", itemId: item.id, task: .understand, status: .running, model: "m",
      startedAt: clock.nowIso)))
    var patch = AgentRunUpdate()
    patch.status(.succeeded)
    patch.steps([AgentStep(n: 1, tool: "finish", kind: .finish, label: "Done", status: .ok, durationMs: 5)])
    try repos.agentRuns.update("run", patch: patch)
    let got = try repos.agentRuns.get("run")
    #expect(got?.summary.status == .succeeded && got?.summary.stepCount == 1 && got?.summary.undoable == false)
    let summary = try repos.agentRuns.latestForItem(item.id, 5).first
    #expect(summary?.id == "run" && summary?.stepCount == 1 && summary?.undoable == false)
    #expect(summary?.steps.count == 1)
    #expect(got?.result == nil)
    #expect(got?.usage == nil)
    #expect(try repos.agentRuns.running().isEmpty)
    // `undoable` follows the run's audit rows until they are undone.
    let entry = try recordAudit(actor: .agent, action: "update_understanding", entity: "item",
                                entityId: item.id, before: .object(["title": .string(item.title)]),
                                after: .object(["title": .string("Renamed")]), agentRunId: "run")
    #expect(try repos.agentRuns.get("run")?.summary.undoable == true)
    #expect(try repos.agentRuns.latestForItem(item.id, 5)[0].undoable == true)
    try undo(entry)
    #expect(try repos.agentRuns.get("run")?.summary.undoable == false)
  }

  @Test mutating func recordsAuditRowsAndSuppressions() throws {
    let entry = try recordAudit(actor: .agent, action: "add_to_collection", entity: "collection_item",
                                entityId: "c:i", after: .object(["x": .number(1)]), agentRunId: "run")
    #expect(try repos.audit.get(entry.id) == entry)
    #expect(try repos.audit.forRun("run").count == 1)
    #expect(try repos.audit.forEntity("collection_item", "c:i").count == 1)
    try repos.suppressions.add(.relationship, "a:b", clock.nowIso)
    try repos.suppressions.add(.relationship, "a:b", clock.nowIso)
    #expect(try repos.suppressions.has(.relationship, "a:b"))
    #expect(try repos.suppressions.keys(.relationship) == ["a:b"])
    try repos.suppressions.remove(.relationship, "a:b")
    #expect(try repos.suppressions.has(.relationship, "a:b") == false)
  }

  // MARK: embedding blobs

  @Test func decodesByBlobLengthWhenDimsMissingOrZero() {
    let blob = vectorToBlob([0.5, 0.25, 0.125])
    #expect(blobToVector(blob, dims: 3) == [0.5, 0.25, 0.125])
    #expect(blobToVector(blob, dims: 0) == [0.5, 0.25, 0.125])
    #expect(blobToVector(blob, dims: 2) == [0.5, 0.25])
  }
}

private extension Date {
  func iso() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    f.timeZone = TimeZone(identifier: "UTC")
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: self)
  }
}
