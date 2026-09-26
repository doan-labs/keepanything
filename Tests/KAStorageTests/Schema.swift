import Foundation
import GRDB
import Testing
@testable import KAStorage
#if canImport(CryptoKit)
  import CryptoKit
#endif

/// Port of `electron/tests/unit/schema.test.ts`: applies migrations 001+002 verbatim (the TS test
/// joins the .sql files directly, so this does the same via the bundled resources + execScript).
@Suite struct Schema {
  private let NOW = "2026-09-03T10:00:00.000Z"
  private static let migratedSql = Migrations.all.prefix(2).map(\.sql).joined(separator: "\n")

  private func open() throws -> DatabaseQueue {
    let queue = try DatabaseQueue()
    try queue.write { d in
      try d.execute(sql: "PRAGMA foreign_keys = ON")
      try execScript(d, Schema.migratedSql)
    }
    return queue
  }

  private func insert(_ q: DatabaseQueue, _ table: String, _ row: [String: Any?]) throws {
    try q.write { db in try insertRaw(db, table, row) }
  }

  private func insertRaw(_ db: GRDB.Database, _ table: String, _ row: [String: Any?]) throws {
    let cols = row.keys.sorted()
    let sql = "INSERT INTO \(table) (\(cols.joined(separator: ", "))) VALUES (\(cols.map { _ in "?" }.joined(separator: ", ")))"
    var args: [DatabaseValueConvertible?] = []
    for k in cols {
      switch row[k] ?? nil {
      case let s as String?: args.append(s)
      case let n as Int?: args.append(n)
      case let f as Double?: args.append(f)
      case let data as Data?: args.append(data)
      case .some(let other):
        let data = try JSONSerialization.data(withJSONObject: other)
        args.append(String(data: data, encoding: .utf8)!)
      case nil:
        args.append(nil)
      }
    }
    try db.execute(sql: sql, arguments: StatementArguments(args))
  }

  private func itemRow(_ id: String, _ title: String, _ extra: [String: Any?] = [:]) -> [String: Any?] {
    var row: [String: Any?] = [
      "id": id,
      "type": "url",
      "subtype": "article",
      "kind": "article",
      "title": title,
      "url": "https://example.com/\(id)",
      "canonical_url": "https://example.com/\(id)",
      "domain": "example.com",
      "created_at": NOW,
      "captured_at": NOW,
      "modified_at": NOW,
      "last_kept_at": NOW,
      "processing_status": "CAPTURED"
    ]
    for (k, v) in extra { row[k] = v }
    return row
  }

  private func ftsRow(_ id: String, title: String, text: String) -> [String: Any?] {
    [
      "item_id": id, "title": title, "retrieval_hints": "", "topics": "", "entities": "",
      "understanding": "", "why_useful": "", "vision_text": "", "meta_text": "",
      "extracted_text": text, "domain": "example.com", "kind": "article"
    ]
  }

  @Test func createsEveryTableAndFtsIndex() throws {
    let queue = try open()
    let names = try queue.read { d in
      try String.fetchAll(d, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
    }
    for table in ["items", "items_fts", "collections", "collection_items", "relationships",
                  "embeddings", "agent_runs", "jobs", "audit_log", "suppressions", "schema_migrations"] {
      #expect(names.contains(table), "missing table \(table)")
    }
  }

  @Test func acceptsOneRowInEveryTable() throws {
    let queue = try open()
    try queue.write { db in
      try insertRaw(db, "schema_migrations", ["version": 1, "applied_at": NOW])
      try insertRaw(db, "items", itemRow("folder-1", "Research", ["type": "folder", "subtype": nil, "kind": nil, "url": nil]))
      try insertRaw(db, "items", itemRow("item-1", "Batching strategies for LLM inference", ["parent_item_id": "folder-1"]))
      try insertRaw(db, "items", itemRow("item-2", "A second article", ["capture_batch_id": "batch-1"]))
      try insertRaw(db, "items_fts", ftsRow("item-1", title: "Batching strategies for LLM inference", text: "Continuous batching keeps the GPU busy…"))
      try insertRaw(db, "collections", [
        "id": "col-1", "name": "Local LLM inference research", "name_key": "local llm inference research",
        "description": "Notes and articles about running models locally and serving them cheaply.",
        "created_by": "agent", "color": nil, "pinned": 0, "created_at": NOW, "updated_at": NOW
      ])
      try insertRaw(db, "collection_items", [
        "collection_id": "col-1", "item_id": "item-1", "confidence": 0.82,
        "reason": "Compares inference batching strategies like the other members.",
        "added_by": "agent", "agent_run_id": "run-1", "added_at": NOW
      ])
      try insertRaw(db, "relationships", [
        "id": "rel-1", "source_item_id": "item-1", "target_item_id": "item-2", "type": "related_to",
        "description": "Both discuss inference cost.", "confidence": 0.7,
        "evidence": ["itemId": "item-2", "quote": "inference cost"], "created_by": "agent",
        "agent_run_id": "run-1", "created_at": NOW
      ])
      var vector: [Float] = [0.5, 0.5, 0.5, 0.5]
      let blob = Data(bytes: &vector, count: 16)
      try insertRaw(db, "embeddings", [
        "item_id": "item-1", "chunk_index": 0, "role": "summary", "content": "memory document",
        "vector": blob, "model": "Xenova/all-MiniLM-L6-v2", "dims": 4
      ])
      try insertRaw(db, "agent_runs", [
        "id": "run-1", "item_id": "item-1", "batch_id": nil, "task": "organize", "status": "succeeded",
        "model": "MiniMaxAI/MiniMax-M3", "started_at": NOW, "completed_at": NOW,
        "steps": [["n": 1, "tool": "finish", "kind": "finish", "label": "Done", "status": "ok", "durationMs": 12]],
        "result": ["task": "organize", "itemId": "item-1", "relationshipIds": ["rel-1"], "collectionIds": ["col-1"], "summary": "ok"],
        "error": nil,
        "usage": ["promptTokens": 10, "completionTokens": 5, "calls": 1, "latencyMs": 900]
      ])
      try insertRaw(db, "jobs", [
        "id": "job-1", "item_id": "item-1", "batch_id": nil, "stage": "extract", "lane": "io",
        "priority": 0, "status": "done", "attempts": 1, "run_after": nil, "last_error": nil,
        "created_at": NOW, "updated_at": NOW
      ])
      try insertRaw(db, "audit_log", [
        "id": "audit-1", "actor": "agent", "action": "add_to_collection", "entity": "collection_item",
        "entity_id": "col-1:item-1", "before": nil,
        "after": ["collectionId": "col-1", "itemId": "item-1"],
        "agent_run_id": "run-1", "created_at": NOW, "undone_at": nil
      ])
      try insertRaw(db, "suppressions", ["kind": "relationship", "key": "item-1:item-2", "created_at": NOW])
    }
    let counts = try queue.read { d in
      try Row.fetchOne(d, sql: """
        SELECT (SELECT count(*) FROM items) AS items, (SELECT count(*) FROM items_fts) AS fts,
               (SELECT count(*) FROM collections) AS collections, (SELECT count(*) FROM collection_items) AS members,
               (SELECT count(*) FROM relationships) AS rels, (SELECT count(*) FROM embeddings) AS embeddings,
               (SELECT count(*) FROM agent_runs) AS runs, (SELECT count(*) FROM jobs) AS jobs,
               (SELECT count(*) FROM audit_log) AS audit, (SELECT count(*) FROM suppressions) AS suppressions
        """)!
    }
    #expect(counts == [
      "items": 3, "fts": 1, "collections": 1, "members": 1, "rels": 1,
      "embeddings": 1, "runs": 1, "jobs": 1, "audit": 1, "suppressions": 1
    ])
    // JSON1 works on the JSON columns and the BLOB round-trips as float32.
    let p = try queue.read { d in try Int.fetchOne(d, sql: "SELECT json_extract(usage, '$.promptTokens') FROM agent_runs") }
    #expect(p == 10)
    let vector = try queue.read { d in try Data.fetchOne(d, sql: "SELECT vector FROM embeddings")! }
    #expect(vector.count == 16)
    let floats = vector.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(4)) }
    #expect(floats == [0.5, 0.5, 0.5, 0.5])
  }

  @Test func enforcesClosedVocabulariesAndForeignKeys() throws {
    let queue = try open()
    #expect(throws: DatabaseError.self) {
      try insert(queue, "items", itemRow("bad", "x", ["type": "bookmark"]))
    }
    #expect(throws: DatabaseError.self) {
      try insert(queue, "items", itemRow("bad", "x", ["processing_status": "DONE"]))
    }
    #expect(throws: DatabaseError.self) {
      try insert(queue, "collection_items", [
        "collection_id": "missing", "item_id": "missing", "added_by": "user", "added_at": NOW
      ])
    }
    // Deleting an item cascades to its memberships/relationships/embeddings/jobs.
    try queue.write { db in
      try insertRaw(db, "items", itemRow("a", "A"))
      try insertRaw(db, "items", itemRow("b", "B"))
      try insertRaw(db, "relationships", [
        "id": "r", "source_item_id": "a", "target_item_id": "b", "type": "inspired_by",
        "created_by": "user", "created_at": NOW
      ])
      try db.execute(sql: "DELETE FROM items WHERE id = ?", arguments: ["a"])
    }
    let n = try queue.read { d in try Int.fetchOne(d, sql: "SELECT count(*) FROM relationships") }
    #expect(n == 0)
  }

  @Test func supportsFtsMatchWithBm25WeightsAndPrefixQueries() throws {
    let queue = try open()
    let rows = [
      ("i1", "Batching strategies for LLM inference", "continuous batching on GPUs"),
      ("i2", "mnismt landing page", "globe animation with warm typography"),
      ("i3", "Inference providers compared", "cheap inference pricing table")
    ]
    try queue.write { db in
      for r in rows { try insertRaw(db, "items_fts", ftsRow(r.0, title: r.1, text: r.2)) }
    }
    let hits = try queue.read { d in
      try Row.fetchAll(d, sql: """
        SELECT item_id, bm25(items_fts, 0, 8, 6, 4, 4, 3, 3, 3, 2, 1, 2, 2) AS score
        FROM items_fts WHERE items_fts MATCH ? ORDER BY score
        """, arguments: ["\"inference\""])
    }
    #expect(hits.map { $0["item_id"] as String }.sorted() == ["i1", "i3"])
    for h in hits { #expect((h["score"] as Double) < 0) }

    let prefix = try queue.read { d in
      try String.fetchAll(d, sql: "SELECT item_id FROM items_fts WHERE items_fts MATCH ? ORDER BY rank",
                          arguments: ["\"glob\"*"])
    }
    #expect(prefix == ["i2"])

    // Porter stemming + diacritics removal.
    let stemmed = try queue.read { d in
      try String.fetchAll(d, sql: "SELECT item_id FROM items_fts WHERE items_fts MATCH ?",
                          arguments: ["\"strategy\""])
    }
    #expect(stemmed == ["i1"])

    // Column filter and snippet work on the content-storing table.
    let snippet = try queue.read { d in
      try String.fetchOne(d, sql: "SELECT snippet(items_fts, 9, '[', ']', '…', 6) AS s FROM items_fts WHERE items_fts MATCH ?",
                          arguments: ["extracted_text:\"pricing\""])
    }
    #expect(snippet?.contains("[pricing]") == true)
  }

  @Test func rejectsSecondActiveJobForSameItemAndStage() throws {
    let queue = try open()
    try insert(queue, "items", itemRow("a", "A"))
    func job(_ id: String, _ status: String, _ itemId: String? = "a", _ stage: String = "extract") throws {
      try insert(queue, "jobs", [
        "id": id, "item_id": itemId, "batch_id": itemId == nil ? "batch-1" : nil,
        "stage": stage, "lane": "io", "priority": 0, "status": status, "attempts": 0,
        "run_after": nil, "last_error": nil, "created_at": NOW, "updated_at": NOW
      ])
    }
    try job("j1", "queued")
    #expect(throws: DatabaseError.self) { try job("j2", "running") }
    #expect(throws: DatabaseError.self) { try job("j2", "queued") }
    // A different stage for the same item is fine.
    try job("j3", "queued", "a", "thumbnail")
    // Finished jobs do not block a new active one.
    try queue.write { d in try d.execute(sql: "UPDATE jobs SET status = 'done' WHERE id = 'j1'") }
    try job("j4", "queued")
    // Batch-level jobs (item_id NULL) are not constrained by the partial index.
    try job("b1", "queued", nil, "organize_batch")
    try job("b2", "queued", nil, "organize_batch")
    let n = try queue.read { d in try Int.fetchOne(d, sql: "SELECT count(*) FROM jobs") }
    #expect(n == 5)
  }
}

/// Migration resource integrity: bundled .sql files must be byte-identical to the Electron
/// sources they were copied from, as recorded by Tests/Fixtures/parity/migrations.json.
@Suite struct MigrationsFixture {
  @Test func bundledMigrationsMatchElectronFixture() throws {
    #if canImport(CryptoKit)
      let rows = loadParityFixture("migrations") as! [[String: Any]]
      #expect(rows.count == Migrations.files.count)
      for (entry, row) in zip(Migrations.files, rows) {
        #expect(entry.version == row["version"] as! Int)
        #expect(entry.name == row["name"] as! String)
        #expect(entry.file == row["file"] as! String)
        let url = Bundle.module.url(forResource: entry.file, withExtension: nil, subdirectory: "Migrations")
          ?? Bundle.module.url(forResource: entry.file, withExtension: nil)
        let data = try Data(contentsOf: try #require(url))
        let sha = CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(sha == row["sha256"] as? String, Comment(rawValue: entry.file))
      }
    #else
      // CryptoKit is absent on Linux; the byte check is covered by macOS runs.
    #endif
  }
}
