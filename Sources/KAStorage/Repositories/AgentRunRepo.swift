import Foundation
import GRDB
import KAModel

/// `SELECT` list for run queries: the row plus `undoable` (an audited change of the run that has
/// not been undone), so summaries can offer Undo without a second query per run.
private let RUN_COLUMNS = """
  agent_runs.*, EXISTS (
    SELECT 1 FROM audit_log WHERE audit_log.agent_run_id = agent_runs.id AND audit_log.undone_at IS NULL
  ) AS undoable
  """

/// Map an `agent_runs` row to the full detail (steps parsed).
func rowToRunDetail(_ row: Row) throws -> AgentRunDetail {
  let steps: [AgentStep] = parseJson(row["steps"], [])
  var summary = AgentRunSummary()
  summary.id = try requireText(row["id"], "id")
  summary.itemId = text(row["item_id"])
  summary.batchId = text(row["batch_id"])
  summary.task = AgentTask(rawValue: try requireText(row["task"], "task")) ?? .command
  summary.status = AgentRunStatus(rawValue: try requireText(row["status"], "status")) ?? .failed
  summary.model = try requireText(row["model"], "model")
  summary.startedAt = try requireText(row["started_at"], "started_at")
  summary.completedAt = text(row["completed_at"])
  summary.stepCount = steps.count
  summary.error = text(row["error"])
  summary.steps = steps
  summary.undoable = numOr(row["undoable"], 0) == 1
  return AgentRunDetail(
    summary: summary,
    usage: parseJson(row["usage"], nil),
    result: parseJson(row["result"], nil)
  )
}

/// Strip result and usage for list payloads (steps stay: the activity panel renders them).
public func toRunSummary(_ detail: AgentRunDetail) -> AgentRunSummary { detail.summary }

/// Fields updatable while a run progresses; `nil`-valued keys write SQL NULL.
public struct AgentRunUpdate {
  public var patch: [(key: String, value: DatabaseValueConvertible?)] = []
  public init() {}
  public mutating func status(_ v: AgentRunStatus) { patch.append(("status", v.rawValue)) }
  public mutating func completedAt(_ v: String?) { patch.append(("completedAt", v)) }
  public mutating func steps(_ v: [AgentStep]) { patch.append(("steps", jsonEncode(v))) }
  public mutating func result(_ v: AgentResult?) { patch.append(("result", v.map { jsonEncode($0) })) }
  public mutating func error(_ v: String?) { patch.append(("error", v)) }
  public mutating func usage(_ v: AgentUsage?) { patch.append(("usage", v.map { jsonEncode($0) })) }
}

/// Agent run repository (transcripts without reasoning).
public struct AgentRunRepo: Sendable {
  let db: Db
  public init(db: Db) { self.db = db }

  public func insert(_ run: AgentRunDetail) throws {
    try db.run { d in
      try d.execute(sql: """
        INSERT INTO agent_runs (id, item_id, batch_id, task, status, model, started_at, completed_at, steps, result, error, usage)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          run.summary.id, run.summary.itemId, run.summary.batchId, run.summary.task.rawValue,
          run.summary.status.rawValue, run.summary.model, run.summary.startedAt,
          run.summary.completedAt, jsonEncode(run.summary.steps),
          run.result.map { jsonEncode($0) }, run.summary.error, run.usage.map { jsonEncode($0) }
        ])
    }
  }

  public func update(_ id: String, patch: AgentRunUpdate) throws {
    var sets: [String] = []
    var params: [DatabaseValueConvertible?] = []
    for p in patch.patch {
      switch p.key {
      case "status": sets.append("status = ?"); params.append(p.value)
      case "completedAt": sets.append("completed_at = ?"); params.append(p.value)
      case "steps": sets.append("steps = ?"); params.append(p.value)
      case "result": sets.append("result = ?"); params.append(p.value)
      case "error": sets.append("error = ?"); params.append(p.value)
      case "usage": sets.append("usage = ?"); params.append(p.value)
      default: break
      }
    }
    if sets.isEmpty { return }
    try db.run { d in
      try d.execute(sql: "UPDATE agent_runs SET \(sets.joined(separator: ", ")) WHERE id = ?",
                    arguments: StatementArguments(params + [id]))
    }
  }

  public func get(_ id: String) throws -> AgentRunDetail? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT \(RUN_COLUMNS) FROM agent_runs WHERE id = ?",
                       arguments: [id]).map(rowToRunDetail)
    }
  }

  public func latestForItem(_ itemId: String, _ limit: Int) throws -> [AgentRunSummary] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: """
        SELECT \(RUN_COLUMNS) FROM agent_runs
        WHERE item_id = ? OR batch_id IN (SELECT capture_batch_id FROM items WHERE id = ? AND capture_batch_id IS NOT NULL)
        ORDER BY started_at DESC LIMIT ?
        """, arguments: [itemId, itemId, max(1, limit)]).map { try toRunSummary(rowToRunDetail($0)) }
    }
  }

  public func forBatch(_ batchId: String) throws -> [AgentRunSummary] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT \(RUN_COLUMNS) FROM agent_runs WHERE batch_id = ? ORDER BY started_at DESC",
                       arguments: [batchId]).map { try toRunSummary(rowToRunDetail($0)) }
    }
  }

  /// Newest first, across all items.
  public func recent(_ limit: Int) throws -> [AgentRunSummary] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT \(RUN_COLUMNS) FROM agent_runs ORDER BY started_at DESC LIMIT ?",
                       arguments: [max(1, limit)]).map { try toRunSummary(rowToRunDetail($0)) }
    }
  }

  /// Runs still marked `running` (crash recovery at boot).
  public func running() throws -> [AgentRunDetail] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT \(RUN_COLUMNS) FROM agent_runs WHERE status = 'running'").map(rowToRunDetail)
    }
  }
}
