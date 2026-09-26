import Foundation
import KACore
import KAModel
import KAStorage

public struct EnqueueInput: Sendable {
  public var itemId: String?
  public var batchId: String?
  public var stage: Stage
  public var priority: Double?
  public var runAfter: String?

  public init(itemId: String? = nil, batchId: String? = nil, stage: Stage,
              priority: Double? = nil, runAfter: String? = nil) {
    self.itemId = itemId
    self.batchId = batchId
    self.stage = stage
    self.priority = priority
    self.runAfter = runAfter
  }
}

/// The job queue over `jobs`. Callers own transactions. Port of `pipeline/queue.ts`.
public final class Queue: ItemPipeline, @unchecked Sendable {
  private let jobs: JobRepo
  private let clock: Clock
  private let ids: IdGenerator
  private let lock = NSLock()
  private var listeners: [UUID: @Sendable () -> Void] = [:]

  public init(jobs: JobRepo, clock: Clock, ids: IdGenerator? = nil) {
    self.jobs = jobs
    self.clock = clock
    self.ids = ids ?? uuid
  }

  private func notify() {
    lock.lock()
    let all = listeners.values.map { $0 }
    lock.unlock()
    for l in all { l() }
  }

  /// Insert one job; nil when an active job for that item+stage already exists.
  @discardableResult
  public func enqueue(_ input: EnqueueInput) throws -> Job? {
    let now = clock.nowIso()
    let job = Job(
      id: ids(), itemId: input.itemId, batchId: input.batchId, stage: input.stage,
      lane: stageLane(input.stage), priority: input.priority ?? stagePriority(input.stage),
      status: .queued, attempts: 0, runAfter: input.runAfter, lastError: nil,
      createdAt: now, updatedAt: now)
    let inserted = try jobs.insert(job)
    if inserted != nil { notify() }
    return inserted
  }

  /// Enqueue several stages for one item (child items get lower priority).
  @discardableResult
  public func enqueueStages(_ item: Item, _ stages: [Stage]) throws -> [Job] {
    var out: [Job] = []
    for stage in stages {
      if let job = try enqueue(EnqueueInput(
        itemId: item.id, batchId: item.captureBatchId, stage: stage,
        priority: stagePriority(stage, isChild: item.parentItemId != nil))) {
        out.append(job)
      }
    }
    return out
  }

  /// The item's initial stages per the graph.
  @discardableResult
  public func enqueueInitial(_ item: Item) -> [Job] {
    (try? enqueueStages(item, initialStages(item.type))) ?? []
  }

  /// Everything from `from` downstream (or the initial stages when `from` is absent).
  @discardableResult
  public func enqueueFrom(_ item: Item, from: Stage?) -> [Job] {
    // Old done rows would make `nextStages` skip the downstream stages of a re-run.
    let rerun = from.map { stagesFrom(item.type, $0) } ?? stagesFor(item.type)
    try? jobs.forgetStages(item.id, rerun)
    guard let from else { return (try? enqueueStages(item, initialStages(item.type))) ?? [] }
    // Only `from` itself is enqueued; its downstream stages follow through the graph as it finishes.
    return rerun.isEmpty ? [] : ((try? enqueueStages(item, [from])) ?? [])
  }

  /// Cancel active jobs of the items.
  @discardableResult
  public func cancelForItems(_ itemIds: [String]) -> [Job] {
    (try? jobs.cancelForItems(itemIds, clock.nowIso())) ?? []
  }

  /// Boot recovery of jobs left `running` by a crash.
  public func resetCrashed() throws -> JobRepo.ResetRunningResult {
    try jobs.resetRunning(LIMITS.maxAttempts, clock.nowIso())
  }

  /// Active jobs as `JobProgress` rows.
  public func progress() throws -> [JobProgress] {
    try jobs.activeProgress()
  }

  /// Called after every successful enqueue (scheduler wake-up).
  public func onEnqueue(_ listener: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
    let id = UUID()
    lock.lock()
    listeners[id] = listener
    lock.unlock()
    return { [weak self] in
      self?.lock.lock()
      self?.listeners.removeValue(forKey: id)
      self?.lock.unlock()
    }
  }
}
