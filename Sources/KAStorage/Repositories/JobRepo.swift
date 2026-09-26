import GRDB
import KAModel

func rowToJob(_ row: Row) throws -> Job {
  Job(
    id: try requireText(row["id"], "id"),
    itemId: text(row["item_id"]),
    batchId: text(row["batch_id"]),
    stage: Stage(rawValue: try requireText(row["stage"], "stage")) ?? .extract,
    lane: Lane(rawValue: try requireText(row["lane"], "lane")) ?? .io,
    priority: numOr(row["priority"], 0),
    status: JobStatus(rawValue: try requireText(row["status"], "status")) ?? .queued,
    attempts: Int(numOr(row["attempts"], 0)),
    runAfter: text(row["run_after"]),
    lastError: text(row["last_error"]),
    createdAt: try requireText(row["created_at"], "created_at"),
    updatedAt: try requireText(row["updated_at"], "updated_at")
  )
}

/// Persisted job queue. The unique partial index keeps one active job per item+stage.
public struct JobRepo: Sendable {
  let db: Db
  public init(db: Db) { self.db = db }

  /// Insert; returns nil when an active job for the same item+stage already exists.
  @discardableResult
  public func insert(_ job: Job) throws -> Job? {
    do {
      try db.run { d in
        try d.execute(sql: """
          INSERT INTO jobs (id, item_id, batch_id, stage, lane, priority, status, attempts, run_after, last_error, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """, arguments: [
            job.id, job.itemId, job.batchId, job.stage.rawValue, job.lane.rawValue, job.priority,
            job.status.rawValue, job.attempts, job.runAfter, job.lastError, job.createdAt, job.updatedAt
          ])
      }
      return job
    } catch let error as DatabaseError {
      if error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
        return nil
      }
      throw error
    }
  }

  public func get(_ id: String) throws -> Job? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM jobs WHERE id = ?", arguments: [id]).map(rowToJob)
    }
  }

  /// Atomically pick the highest-priority queued job of `lane` whose `run_after` has passed and
  /// mark it running (`attempts + 1`). Wrap in `db.transaction` together with the entry-status update.
  public func claim(_ lane: Lane, _ nowIso: String) throws -> Job? {
    try db.run { d in
      guard let row = try Row.fetchOne(d, sql: """
        SELECT * FROM jobs WHERE status = 'queued' AND lane = ? AND (run_after IS NULL OR run_after <= ?)
        ORDER BY priority DESC, created_at ASC LIMIT 1
        """, arguments: [lane.rawValue, nowIso]) else { return nil }
      let job = try rowToJob(row)
      try d.execute(sql: "UPDATE jobs SET status = 'running', attempts = attempts + 1, updated_at = ? WHERE id = ? AND status = 'queued'",
                    arguments: [nowIso, job.id])
      return try Row.fetchOne(d, sql: "SELECT * FROM jobs WHERE id = ?", arguments: [job.id]).map(rowToJob)
    }
  }

  /// Terminal update.
  public func finish(_ id: String, _ status: JobStatus, _ nowIso: String, lastError: String? = nil) throws {
    try db.run { d in
      try d.execute(sql: "UPDATE jobs SET status = ?, updated_at = ?, last_error = coalesce(?, last_error) WHERE id = ?",
                    arguments: [status.rawValue, nowIso, lastError, id])
    }
  }

  /// Back to `queued`, optionally with a `run_after` (backoff / batch gate).
  public func requeue(_ id: String, _ runAfter: String?, _ nowIso: String, lastError: String? = nil) throws {
    try db.run { d in
      try d.execute(sql: "UPDATE jobs SET status = 'queued', run_after = ?, updated_at = ?, last_error = coalesce(?, last_error) WHERE id = ?",
                    arguments: [runAfter, nowIso, lastError, id])
    }
  }

  /// Change `run_after` of a queued job (release the batch gate).
  public func setRunAfter(_ id: String, _ runAfter: String?, _ nowIso: String) throws {
    try db.run { d in
      try d.execute(sql: "UPDATE jobs SET run_after = ?, updated_at = ? WHERE id = ? AND status = 'queued'",
                    arguments: [runAfter, nowIso, id])
    }
  }

  /// Cancel every queued/running job of the items. Returns the cancelled jobs.
  public func cancelForItems(_ itemIds: [String], _ nowIso: String) throws -> [Job] {
    if itemIds.isEmpty { return [] }
    return try db.run { d in
      let jobs = try Row.fetchAll(d, sql: """
        SELECT * FROM jobs WHERE item_id IN (\(placeholders(itemIds.count))) AND status IN ('queued', 'running')
        """, arguments: StatementArguments(itemIds)).map(rowToJob)
      for job in jobs {
        try d.execute(sql: "UPDATE jobs SET status = 'cancelled', updated_at = ? WHERE id = ?",
                      arguments: [nowIso, job.id])
      }
      return jobs
    }
  }

  /// Drop finished rows of `stages` so `finishedStages` stops treating a re-run stage as done.
  public func forgetStages(_ itemId: String, _ stages: [Stage]) throws {
    if stages.isEmpty { return }
    try db.run { d in
      try d.execute(sql: """
        DELETE FROM jobs WHERE item_id = ? AND stage IN (\(placeholders(stages.count)))
        AND status IN ('done', 'failed', 'cancelled')
        """, arguments: StatementArguments([itemId] + stages.map { $0.rawValue }))
    }
  }

  /// Result of `resetRunning`.
  public struct ResetRunningResult: Sendable, Equatable {
    public var requeued: Int
    public var failed: Int
  }

  /// `running` -> `queued` when `attempts < maxAttempts`, else `failed 'crashed'`.
  public func resetRunning(_ maxAttempts: Int, _ nowIso: String) throws -> ResetRunningResult {
    try db.run { d in
      try d.execute(
        sql: "UPDATE jobs SET status = 'queued', run_after = NULL, updated_at = ? WHERE status = 'running' AND attempts < ?",
        arguments: [nowIso, maxAttempts])
      let requeued = Int(d.changesCount)
      try d.execute(
        sql: "UPDATE jobs SET status = 'failed', last_error = 'crashed', updated_at = ? WHERE status = 'running'",
        arguments: [nowIso])
      return ResetRunningResult(requeued: requeued, failed: Int(d.changesCount))
    }
  }

  /// Active (queued|running) jobs of one item.
  public func activeForItem(_ itemId: String) throws -> [Job] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM jobs WHERE item_id = ? AND status IN ('queued', 'running') ORDER BY created_at",
                       arguments: [itemId]).map(rowToJob)
    }
  }

  /// Active batch-level job (item_id NULL) for a batch and stage.
  public func activeForBatch(_ batchId: String, _ stage: Stage) throws -> Job? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM jobs WHERE batch_id = ? AND item_id IS NULL AND stage = ? AND status IN ('queued', 'running') LIMIT 1",
                       arguments: [batchId, stage.rawValue]).map(rowToJob)
    }
  }

  /// Most recent batch-level job of any status for a batch and stage.
  public func latestForBatch(_ batchId: String, _ stage: Stage) throws -> Job? {
    try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT * FROM jobs WHERE batch_id = ? AND item_id IS NULL AND stage = ? ORDER BY created_at DESC, rowid DESC LIMIT 1",
                       arguments: [batchId, stage.rawValue]).map(rowToJob)
    }
  }

  /// Most recent job per stage for the item (any status).
  public func latestPerStage(_ itemId: String) throws -> [Stage: Job] {
    let rows = try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM jobs WHERE item_id = ? ORDER BY created_at ASC, rowid ASC",
                       arguments: [itemId])
    }
    var latest: [Stage: Job] = [:]
    for row in rows {
      let job = try rowToJob(row)
      latest[job.stage] = job
    }
    return latest
  }

  /// Stages whose most recent job finished (done or failed). Re-enqueued stages count as unfinished.
  public func finishedStages(_ itemId: String) throws -> Set<Stage> {
    let rows = try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM jobs WHERE item_id = ? ORDER BY created_at ASC, rowid ASC",
                       arguments: [itemId])
    }
    var latest: [Stage: JobStatus] = [:]
    for row in rows {
      latest[Stage(rawValue: try requireText(row["stage"], "stage")) ?? .extract] =
        JobStatus(rawValue: try requireText(row["status"], "status")) ?? .queued
    }
    return Set(latest.filter { $0.value == .done || $0.value == .failed }.map(\.key))
  }

  /// Park an ai job without burning an attempt (no key / offline).
  public func park(_ id: String, _ runAfter: String?, _ nowIso: String) throws {
    try db.run { d in
      try d.execute(sql: "UPDATE jobs SET status = 'queued', attempts = max(attempts - 1, 0), run_after = ?, updated_at = ? WHERE id = ?",
                    arguments: [runAfter, nowIso, id])
    }
  }

  /// Every active job joined with the item's current status, for `jobs:status`.
  public func activeProgress() throws -> [JobProgress] {
    let rows = try db.readOnly { d in
      try Row.fetchAll(d, sql: """
        SELECT j.item_id, j.batch_id, j.stage, j.status, j.attempts, i.processing_status
        FROM jobs j LEFT JOIN items i ON i.id = j.item_id
        WHERE j.status IN ('queued', 'running') ORDER BY j.created_at
        """)
    }
    return rows.map { r in
      JobProgress(
        itemId: text(r["item_id"]),
        batchId: text(r["batch_id"]),
        processingStatus: text(r["processing_status"]).flatMap(ProcessingStatus.init(rawValue:)),
        stage: Stage(rawValue: text(r["stage"]) ?? "") ?? .extract,
        jobStatus: JobStatus(rawValue: text(r["status"]) ?? "") ?? .queued,
        attempts: Int(numOr(r["attempts"], 0))
      )
    }
  }

  public func countByStatus(_ status: JobStatus) throws -> Int {
    let row = try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT count(*) AS n FROM jobs WHERE status = ?", arguments: [status.rawValue])
    }
    return Int(numOr(row?["n"], 0))
  }
}
