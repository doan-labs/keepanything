import Foundation
import GRDB
import Testing
@testable import KAStorage

/// Port of `electron/tests/unit/db.test.ts`. The "refuses async bodies" case has no Swift
/// counterpart — `transaction` takes a synchronous, non-async closure so `await` inside it is a
/// compile error, not a runtime throw.
@Suite struct Database {
  private func open(_ file: String = ":memory:") throws -> Db {
    try openDatabase(file: file)
  }

  @Test func createsFileAppliesMigrationsOnceRecordsVersion() throws {
    let (dir, file) = tempDbFile()
    defer { cleanup(dir) }
    let db = try open(file)
    #expect(try db.schemaVersion() == 0)
    try db.migrate()
    #expect(FileManager.default.fileExists(atPath: file))
    #expect(try db.schemaVersion() == Migrations.all.count)
    let tables = try db.raw.read { d in
      try String.fetchAll(d, sql: "SELECT name FROM sqlite_master WHERE type IN ('table') ORDER BY name")
    }
    for t in ["items", "items_fts", "jobs", "collections", "schema_migrations"] {
      #expect(tables.contains(t), "missing table \(t)")
    }
    try db.migrate() // idempotent
    let n = try db.raw.read { d in try Int.fetchOne(d, sql: "SELECT count(*) FROM schema_migrations") }
    #expect(n == Migrations.all.count)
    db.close()
  }

  @Test func upgradesLibraryStoppedAtVersion1() throws {
    let (dir, file) = tempDbFile()
    defer { cleanup(dir) }
    let v1 = try openDatabase(file: file)
    try v1.raw.write { d in
      try d.execute(sql: "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)")
      try execScript(d, Migrations.all[0].sql)
      try d.execute(sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (1, ?)", arguments: ["2026-01-01T00:00:00.000Z"])
    }
    v1.close()

    let db = try open(file)
    try db.migrate()
    #expect(try db.schemaVersion() == Migrations.all.count)
    let columns = try db.raw.read { d in
      try Row.fetchAll(d, sql: "PRAGMA table_info(collections)").map { $0["name"] as String }
    }
    #expect(!columns.contains("type"))
    #expect(throws: Never.self) {
      try db.raw.write { d in
        try d.execute(sql: """
          INSERT INTO collections (id, name, name_key, description, created_by, color, pinned, created_at, updated_at)
          VALUES ('c1', 'Tax 2026', 'tax 2026', NULL, 'user', NULL, 0, '2026-01-01', '2026-01-01')
          """)
      }
    }
    db.close()
  }

  @Test func refusesNewerSchemaVersion() throws {
    let (dir, file) = tempDbFile()
    defer { cleanup(dir) }
    let future = try openDatabase(file: file)
    try future.migrate()
    let newest = Migrations.all.last!.version
    try future.raw.write { d in
      try d.execute(sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                    arguments: [newest + 1, "2099-01-01T00:00:00.000Z"])
      try d.execute(sql: "CREATE TABLE future_only (id TEXT PRIMARY KEY)")
    }
    future.close()

    let db = try open(file)
    var caught: SchemaTooNewError?
    do {
      try db.migrate()
    } catch let error as SchemaTooNewError {
      caught = error
    }
    let guard_ = try #require(caught)
    #expect(guard_.found == newest + 1)
    #expect(guard_.supported == newest)
    #expect(guard_.message == "library schema version \(newest + 1) is newer than this app supports (\(newest)); update the app")
    #expect(try db.schemaVersion() == newest + 1)
    let counts = try db.raw.read { d -> (Int, Bool) in
      let n = try Int.fetchOne(d, sql: "SELECT count(*) FROM schema_migrations")!
      let ok = try Int.fetchOne(d, sql: "SELECT 1 FROM sqlite_master WHERE name = 'future_only'") != nil
      return (n, ok)
    }
    #expect(counts.0 == newest + 1)
    #expect(counts.1)
    db.close()
  }

  @Test func usesWalForeignKeysAndBusyTimeout() throws {
    let (dir, file) = tempDbFile()
    defer { cleanup(dir) }
    let db = try open(file)
    let (mode, fks, timeout) = try db.raw.read { d -> (String, Int, Int) in
      (
        try String.fetchOne(d, sql: "PRAGMA journal_mode")!,
        try Int.fetchOne(d, sql: "PRAGMA foreign_keys")!,
        try Int.fetchOne(d, sql: "PRAGMA busy_timeout")!
      )
    }
    #expect(mode == "wal")
    #expect(fks == 1)
    #expect(timeout == 5000)
    db.close()
  }

  @Test func transactionCommitsAndRollsBackOnThrow() throws {
    let db = try open()
    try db.migrate()
    try db.transaction { d in
      try d.execute(sql: "INSERT INTO suppressions (kind, key, created_at) VALUES ('relationship', 'a:b', 'now')")
    }
    #expect(throws: (any Error).self) {
      try db.transaction { d in
        try d.execute(sql: "INSERT INTO suppressions (kind, key, created_at) VALUES ('relationship', 'c:d', 'now')")
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
      }
    }
    let n = try db.raw.read { d in try Int.fetchOne(d, sql: "SELECT count(*) FROM suppressions") }
    #expect(n == 1)
    #expect(!db.inTransaction())
  }

  @Test func nestedTransactionsAreSavepoints() throws {
    let db = try open()
    try db.migrate()
    try db.transaction { d in
      try d.execute(sql: "INSERT INTO suppressions (kind, key, created_at) VALUES ('relationship', 'outer', 'now')")
      #expect(db.inTransaction())
      do {
        try db.transaction { inner in
          try inner.execute(sql: "INSERT INTO suppressions (kind, key, created_at) VALUES ('relationship', 'inner', 'now')")
          throw NSError(domain: "test", code: 1)
        }
      } catch {}
      #expect(db.inTransaction())
    }
    let keys = try db.raw.read { d in try String.fetchAll(d, sql: "SELECT key FROM suppressions ORDER BY key") }
    #expect(keys == ["outer"])
  }

  @Test func afterCommitRunsAfterOutermostCommitNeverAfterRollback() throws {
    let db = try open()
    try db.migrate()
    final class Log: @unchecked Sendable { var entries: [String] = [] }
    let log = Log()
    try db.transaction { _ in
      try db.transaction { _ in
        db.afterCommit { log.entries.append("inner") }
      }
      #expect(log.entries.isEmpty)
      db.afterCommit { log.entries.append("outer") }
    }
    #expect(log.entries == ["inner", "outer"])
    #expect(throws: (any Error).self) {
      try db.transaction { _ in
        db.afterCommit { log.entries.append("lost") }
        throw NSError(domain: "test", code: 1)
      }
    }
    #expect(log.entries == ["inner", "outer"])
    db.afterCommit { log.entries.append("immediate") }
    #expect(log.entries.contains("immediate"))
  }
}
