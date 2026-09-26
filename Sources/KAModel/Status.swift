/// Item processing lifecycle: statuses, user-facing stage groups, copy, and the pure transition
/// table used by the pipeline scheduler (port of `electron/src/shared/status.ts`).

/// Every `items.processing_status` value. Case order matches `PROCESSING_STATUSES`.
public enum ProcessingStatus: String, Codable, Sendable, CaseIterable {
  case captured = "CAPTURED"
  case extracting = "EXTRACTING"
  case extracted = "EXTRACTED"
  case embedding = "EMBEDDING"
  case understanding = "UNDERSTANDING"
  case relating = "RELATING"
  case ready = "READY"
  case partial = "PARTIAL"
  case extractionFailed = "EXTRACTION_FAILED"
  case aiFailed = "AI_FAILED"
  case waitingForAi = "WAITING_FOR_AI"
}

/// `PROCESSING_STATUSES` — the ordered wire values.
public let PROCESSING_STATUSES: [String] = ProcessingStatus.allCases.map(\.rawValue)

public func isProcessingStatus(_ value: String) -> Bool { ProcessingStatus(rawValue: value) != nil }

/// Failure statuses (the item is still kept; the card offers "Try again").
public func isFailed(_ status: ProcessingStatus) -> Bool {
  status == .extractionFailed || status == .aiFailed
}

/// No further automatic processing is pending (`READY`, `PARTIAL`).
public func isTerminal(_ status: ProcessingStatus) -> Bool {
  status == .ready || status == .partial
}

/// Ids of the three coarse stages a user sees while an item is being processed.
public enum UserStageId: String, Codable, Sendable, CaseIterable {
  case reading, understanding, connecting
}

/// A user-facing progress step grouping several internal statuses.
public struct UserStage: Sendable, Equatable {
  public let id: UserStageId
  public let label: String
  public let statuses: [ProcessingStatus]
  public init(id: UserStageId, label: String, statuses: [ProcessingStatus]) {
    self.id = id
    self.label = label
    self.statuses = statuses
  }
}

/// Coarse progress steps shown on cards (`reading -> understanding -> connecting`).
public let USER_STAGES: [UserStage] = [
  UserStage(id: .reading, label: "Reading", statuses: [.extracting, .extracted, .embedding]),
  UserStage(id: .understanding, label: "Understanding", statuses: [.understanding]),
  UserStage(id: .connecting, label: "Looking for similar things", statuses: [.relating])
]

/// The user-facing stage a status belongs to, or nil for settled/failed/waiting/captured states.
public func userStageFor(_ status: ProcessingStatus) -> UserStage? {
  USER_STAGES.first { $0.statuses.contains(status) }
}

/// Card copy per status, in the product's voice. Empty string = show nothing.
public let STATUS_LABEL: [ProcessingStatus: String] = [
  .captured: "Saved.",
  .extracting: "Reading",
  .extracted: "Reading",
  .embedding: "Reading",
  .understanding: "Understanding",
  .relating: "Looking for similar things",
  .ready: "",
  .partial: "Kept. Partly understood.",
  .extractionFailed: "Couldn't read this, but it's kept.",
  .aiFailed: "Still figuring this one out.",
  .waitingForAi: "Kept. Not understood yet."
]

/// Pipeline stages. Bodies live in `KAPipeline`; the list itself is frozen.
/// Case order matches the TS `Stage` union order.
public enum Stage: String, Codable, Sendable, CaseIterable {
  case extract, thumbnail, snapshot, embed, index, understand, relate
  case organizeBatch = "organize_batch"
  case consolidate
}

/// Copy for each pipeline stage (activity views, job lists).
public let STAGE_LABEL: [Stage: String] = [
  .extract: "Reading",
  .thumbnail: "Making a preview",
  .snapshot: "Capturing the page",
  .embed: "Indexing",
  .index: "Indexing",
  .understand: "Understanding",
  .relate: "Looking for similar things",
  .organizeBatch: "Organizing",
  .consolidate: "Tidying collections"
]

/// How a stage body ended. `partial` = it worked, but on incomplete input or with gaps.
public enum StageOutcome: String, Codable, Sendable, CaseIterable {
  case ok, partial, failed
}

/// Optional facts only the scheduler knows when applying a transition.
public struct TransitionContext: Sendable, Equatable {
  /// True when the graph has no further stage for this item after `stage` (e.g. `index` for notes,
  /// which skip understand/relate). Lets stages that normally leave the status alone settle it.
  public var isLast: Bool
  public init(isLast: Bool = false) { self.isLast = isLast }
}

/// Statuses that carry "not fully understood" memory. The scheduler does not overwrite them with a
/// stage's running status (see `stageEntryStatus`), so `next()` can turn them into `PARTIAL` at the
/// end instead of `READY`.
public let STICKY_STATUSES: [ProcessingStatus] = [.extractionFailed, .partial]

/// Statuses that mean "extraction has not completed yet" (embed may move them forward).
private let BEFORE_UNDERSTANDING: [ProcessingStatus] = [.captured, .extracting, .extracted, .embedding]

/// Settle an item after its last stage: sticky/partial inputs end `PARTIAL`, everything else `READY`.
private func settle(_ status: ProcessingStatus, _ outcome: StageOutcome) -> ProcessingStatus {
  if outcome == .partial { return .partial }
  if STICKY_STATUSES.contains(status) { return .partial }
  return .ready
}

/// Pure transition table. `status` is the item's *current* status when the stage finishes (normally
/// the value `stageEntryStatus()` set at claim time, or a sticky status that was left in place).
/// Rules are documented on `electron/src/shared/status.ts`.
public func next(
  _ status: ProcessingStatus,
  _ stage: Stage,
  _ outcome: StageOutcome,
  ctx: TransitionContext = TransitionContext()
) -> ProcessingStatus {
  switch stage {
  case .extract:
    return outcome == .failed ? .extractionFailed : .extracted
  case .thumbnail, .snapshot, .index:
    if ctx.isLast { return outcome == .failed ? .partial : settle(status, outcome) }
    return status
  case .embed:
    if outcome == .failed { return status }
    return BEFORE_UNDERSTANDING.contains(status) ? .understanding : status
  case .understand:
    if outcome == .failed { return .aiFailed }
    if outcome == .partial { return .partial }
    return status == .extractionFailed ? .partial : .relating
  case .relate, .organizeBatch:
    if outcome == .failed { return .aiFailed }
    return settle(status, outcome)
  case .consolidate:
    return status
  }
}

/// Nominal status an item shows while a stage runs; nil for stages that leave the status alone.
private let RUNNING_STATUS: [Stage: ProcessingStatus] = [
  .extract: .extracting,
  .embed: .embedding,
  .understand: .understanding,
  .relate: .relating,
  .organizeBatch: .relating
]

/// Position of each status along the flow. Used so a running status never moves an item backwards.
private let FLOW_RANK: [ProcessingStatus: Int] = [
  .captured: 0,
  .extracting: 1,
  .extracted: 2,
  .extractionFailed: 2,
  .embedding: 3,
  .understanding: 4,
  .aiFailed: 4,
  .waitingForAi: 4,
  .relating: 5,
  .ready: 6,
  .partial: 6
]

/// Status an item is in WHILE `stage` runs (`extract -> EXTRACTING`, `embed -> EMBEDDING`,
/// `understand -> UNDERSTANDING`, `relate`/`organize_batch -> RELATING`; others -> nil = unchanged).
/// See `electron/src/shared/status.ts` for the full contract.
public func stageEntryStatus(_ stage: Stage, _ current: ProcessingStatus? = nil) -> ProcessingStatus? {
  guard let running = RUNNING_STATUS[stage] else { return nil }
  guard let current, stage != .extract else { return running }
  if STICKY_STATUSES.contains(current) { return nil }
  if FLOW_RANK[current]! > FLOW_RANK[running]! { return nil }
  return running
}
