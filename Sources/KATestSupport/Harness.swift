import Foundation
import KACore
import KAModel
import KAPipeline
import KAStorage

/// A recorded domain event.
public struct RecordedEvent: Sendable {
  public var name: String
  public var payload: DomainEvent
}

/// Everything a unit test needs, over an in-memory database. Port of `tests/unit/helpers/harness.ts`
/// minus `state` (the StateApplier lands with S-PIPE; no services test uses it).
public final class Harness: @unchecked Sendable {
  public let db: Db
  public let repos: Repositories
  public let events: EventBus
  public let recorded: RecordedEvents
  public let clock: ManualClock
  public let ids: IdGenerator
  public let audit: AuditService
  public let queue: Queue
  public let items: ItemService
  public let collections: CollectionService
  public let relationships: RelationshipService
  public let objectStore: ObjectStore
  public let paths: Paths
  private var itemN = 0
  private let root: String?
  private let withFiles: Bool

  public final class RecordedEvents: @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var all: [RecordedEvent] = []
    func push(_ e: RecordedEvent) {
      lock.lock()
      all.append(e)
      lock.unlock()
    }
  }

  /// `withFiles` creates a temp library directory for the object store.
  public init(file: String = ":memory:", withFiles: Bool = false) throws {
    self.withFiles = withFiles
    let db = try openDatabase(file: file)
    try db.migrate()
    self.db = db
    repos = createRepositories(db)
    let recorded = RecordedEvents()
    self.recorded = recorded
    let inner = createEventBus()
    events = RecordingBus(inner: inner, recorded: recorded)
    clock = ManualClock(start: "2026-09-03T10:00:00.000Z")
    ids = sequentialIds()
    audit = AuditService(db: db, repos: repos, events: events, clock: clock, ids: ids)
    queue = Queue(jobs: repos.jobs, clock: clock, ids: sequentialIds("job"))
    items = ItemService(db: db, repos: repos, events: events, clock: clock,
                        audit: audit, pipeline: queue, ids: ids)
    collections = CollectionService(db: db, repos: repos, events: events, clock: clock,
                                    audit: audit, ids: sequentialIds("col"))
    relationships = RelationshipService(db: db, repos: repos, events: events, clock: clock,
                                        audit: audit, ids: sequentialIds("rel"))
    if withFiles {
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ka-test-\(UUID().uuidString)").path
      root = dir
      let paths = buildPaths(dir)
      try ensureLibraryDirs(paths)
      self.paths = paths
    } else {
      root = nil
      paths = buildPaths((FileManager.default.temporaryDirectory.path as NSString)
        .appendingPathComponent("ka-test-unused"))
    }
    objectStore = ObjectStore(paths: paths)
  }

  /// Create an item with sensible defaults.
  @discardableResult
  public func item(_ over: (inout NewItemInput) -> Void = { _ in }) throws -> Item {
    itemN += 1
    var input = NewItemInput(type: .text, title: "Item \(itemN)")
    over(&input)
    return try items.create(input)
  }

  public func eventsNamed(_ name: String) -> [DomainEvent] {
    recorded.all.filter { $0.name == name }.map(\.payload)
  }

  public func close() {
    db.close()
    if withFiles, let root {
      try? FileManager.default.removeItem(atPath: root)
    }
  }
}

private final class RecordingBus: EventBus, @unchecked Sendable {
  let inner: EventBus
  let recorded: Harness.RecordedEvents

  init(inner: EventBus, recorded: Harness.RecordedEvents) {
    self.inner = inner
    self.recorded = recorded
  }

  func on(_ event: String, listener: @escaping @Sendable (DomainEvent) -> Void) -> EventCancel {
    inner.on(event, listener: listener)
  }

  func off(_ event: String, listener: @escaping @Sendable (DomainEvent) -> Void) {
    inner.off(event, listener: listener)
  }

  func emit(_ event: DomainEvent) {
    recorded.push(RecordedEvent(name: event.name, payload: event))
    inner.emit(event)
  }
}
