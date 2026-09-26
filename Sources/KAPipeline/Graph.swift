import KAModel

/**
 * Pipeline graph: which stages an item type runs and in what order. Pure data +
 * functions; the scheduler consults it after every finished job. A stage becomes runnable when
 * every stage it waits for has *finished* (done or failed): previews never block understanding,
 * and an extraction failure still leads to understanding on metadata only.
 * Port of `pipeline/graph.ts`.
 */
private struct GraphNode {
  let stage: Stage
  let after: [Stage]
}

private let URL_GRAPH: [GraphNode] = [
  .init(stage: .extract, after: []),
  .init(stage: .snapshot, after: []),
  .init(stage: .embed, after: [.extract, .snapshot]),
  .init(stage: .understand, after: [.extract, .snapshot]),
  .init(stage: .index, after: [.understand]),
  .init(stage: .relate, after: [.index])
]

private let IMAGE_GRAPH: [GraphNode] = [
  .init(stage: .thumbnail, after: []),
  .init(stage: .understand, after: [.thumbnail]),
  .init(stage: .index, after: [.understand]),
  .init(stage: .relate, after: [.index])
]

private let DOCUMENT_GRAPH: [GraphNode] = [
  .init(stage: .extract, after: []),
  .init(stage: .thumbnail, after: []),
  .init(stage: .embed, after: [.extract, .thumbnail]),
  .init(stage: .understand, after: [.extract, .thumbnail]),
  .init(stage: .index, after: [.understand]),
  .init(stage: .relate, after: [.index])
]

private let FOLDER_GRAPH: [GraphNode] = [
  .init(stage: .extract, after: []),
  .init(stage: .understand, after: [.extract]),
  .init(stage: .index, after: [.understand]),
  .init(stage: .relate, after: [.index])
]

/// Notes skip understand/relate: their text is already the understanding.
private let NOTE_GRAPH: [GraphNode] = [
  .init(stage: .embed, after: []),
  .init(stage: .index, after: [])
]

private func graph(_ type: ItemType) -> [GraphNode] {
  switch type {
  case .url: return URL_GRAPH
  case .image: return IMAGE_GRAPH
  case .pdf, .text, .markdown, .file, .video, .audio, .unknown: return DOCUMENT_GRAPH
  case .folder: return FOLDER_GRAPH
  case .note: return NOTE_GRAPH
  }
}

/// Lane of each stage (`LIMITS.lanes` gives the concurrency).
public func stageLane(_ stage: Stage) -> Lane {
  switch stage {
  case .extract, .thumbnail, .snapshot: return .io
  case .embed, .index: return .embed
  case .understand, .relate, .organizeBatch, .consolidate: return .ai
  }
}

/// Base priority per stage: understand > extract > index > previews > relate/embed > batch > consolidate.
public func stageBasePriority(_ stage: Stage) -> Double {
  switch stage {
  case .understand: return 30
  case .extract: return 25
  case .index: return 20
  case .thumbnail, .snapshot: return 15
  case .relate, .embed, .organizeBatch: return 10
  case .consolidate: return 0
  }
}

/// Priority penalty for children of folders so a big drop never starves single items.
public let CHILD_PRIORITY_PENALTY: Double = 5

/// Every stage of the graph for `type`, in declaration order.
public func stagesFor(_ type: ItemType) -> [Stage] {
  graph(type).map(\.stage)
}

/// Enqueued at capture.
public func initialStages(_ type: ItemType) -> [Stage] {
  graph(type).filter { $0.after.isEmpty }.map(\.stage)
}

/// Stages unlocked by `finished` given the set of stages that have finished so far (which must
/// include `finished` itself). Stages already in `finishedSet` are not returned again.
public func nextStages(_ type: ItemType, _ finished: Stage, _ finishedSet: Set<Stage>) -> [Stage] {
  graph(type)
    .filter { $0.after.contains(finished) }
    .filter { !finishedSet.contains($0.stage) }
    .filter { $0.after.allSatisfy(finishedSet.contains) }
    .map(\.stage)
}

/// True when nothing in the graph waits for `stage` (lets `next()` settle the item).
public func isLastStage(_ type: ItemType, _ stage: Stage) -> Bool {
  let g = graph(type)
  guard g.contains(where: { $0.stage == stage }) else { return false }
  return !g.contains(where: { $0.after.contains(stage) })
}

/// `from` plus everything downstream of it (what `items:reprocess { from }` re-runs).
public func stagesFrom(_ type: ItemType, _ from: Stage) -> [Stage] {
  let g = graph(type)
  guard g.contains(where: { $0.stage == from }) else { return [] }
  var out: Set<Stage> = [from]
  var grew = true
  while grew {
    grew = false
    for n in g where !out.contains(n.stage) && n.after.contains(where: out.contains) {
      out.insert(n.stage)
      grew = true
    }
  }
  return g.filter { out.contains($0.stage) }.map(\.stage)
}

/// Effective priority for a job.
public func stagePriority(_ stage: Stage, isChild: Bool = false) -> Double {
  stageBasePriority(stage) - (isChild ? CHILD_PRIORITY_PENALTY : 0)
}

/// `LIMITS.lanes` as a per-lane capacity lookup.
public func laneCapacity(_ lane: Lane) -> Int {
  switch lane {
  case .io: return LIMITS.lanes.io
  case .embed: return LIMITS.lanes.embed
  case .ai: return LIMITS.lanes.ai
  }
}
