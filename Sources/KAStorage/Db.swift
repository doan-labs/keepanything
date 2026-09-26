import Foundation
import GRDB
import KAModel

/// Thin wrapper over a GRDB `DatabaseWriter`: production PRAGMAs, versioned migrations and a
/// nesting `transaction()` helper (BEGIN IMMEDIATE at depth 0, SAVEPOINT below). Port of
/// `electron/src/main/storage/db.ts`. GRDB caches statements per connection, so the `prepare()`
/// cache of the TS wrapper has no counterpart here.
public final class Db: Sendable {
  /// The underlying writer (`DatabasePool` for files, `DatabaseQueue` for `:memory:`).
  public let raw: any DatabaseWriter

  private struct State {
    var depth = 0
    var deferred: [@Sendable () -> Void] = []
    /// The writer connection while an outermost `transaction` runs — nested calls reuse it,
    /// because GRDB writer access is not reentrant on `DatabaseQueue`.
    var db: GRDB.Database?
  }
  private let state = Mutex(State())

  init(raw: any DatabaseWriter) {
    self.raw = raw
  }

  /// Run `body` atomically. Nested calls become savepoints. Rethrows after rolling back.
  /// The body must not suspend: GRDB writers are reentrant on the writer thread, so a nested
  /// `write` runs inline exactly like the TS `transaction()`.
  public func transaction<T>(_ body: (GRDB.Database) throws -> T) throws -> T {
    if let db = state.withLock({ $0.db }) {
      return try runTransaction(on: db, body)
    }
    return try raw.writeWithoutTransaction { db in
      state.withLock { $0.db = db }
      defer { state.withLock { $0.db = nil } }
      return try runTransaction(on: db, body)
    }
  }

  private func runTransaction<T>(on db: GRDB.Database, _ body: (GRDB.Database) throws -> T) throws -> T {
    let level = state.withLock { s -> Int in
      defer { s.depth += 1 }
      return s.depth
    }
    let savepoint = "ka_sp_\(level)"
    do {
      try db.execute(sql: level == 0 ? "BEGIN IMMEDIATE" : "SAVEPOINT \(savepoint)")
      let result: T
      do {
        result = try body(db)
      } catch {
        state.withLock { s in s.depth -= 1 }
        if level == 0 {
          try? db.execute(sql: "ROLLBACK")
          state.withLock { s in s.deferred = [] }
        } else {
          try? db.execute(sql: "ROLLBACK TO \(savepoint); RELEASE \(savepoint)")
        }
        throw error
      }
      state.withLock { s in s.depth -= 1 }
      if level == 0 {
        try db.execute(sql: "COMMIT")
        let callbacks = state.withLock { s -> [@Sendable () -> Void] in
          defer { s.deferred = [] }
          return s.deferred
        }
        for fn in callbacks { fn() }
      } else {
        try db.execute(sql: "RELEASE \(savepoint)")
      }
      return result
    }
  }

  /// True while inside `transaction()`.
  public func inTransaction() -> Bool {
    state.withLock { $0.depth > 0 }
  }

  /// Run `fn` once the outermost transaction commits (immediately when not in one). Discarded on
  /// rollback. Services use it to emit events only for state that actually exists.
  public func afterCommit(_ fn: @Sendable @escaping () -> Void) {
    let run = state.withLock { s -> Bool in
      if s.depth == 0 { return true }
      s.deferred.append(fn)
      return false
    }
    if run { fn() }
  }

  /// Apply pending migrations. Throws `SchemaTooNewError` when the database was written by a
  /// newer app, so an older build never touches a schema it does not know.
  public func migrate() throws {
    try raw.write { db in
      try db.execute(sql: "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)")
    }
    let applied = try schemaVersion()
    let supported = Migrations.all.last?.version ?? 0
    if applied > supported { throw SchemaTooNewError(found: applied, supported: supported) }
    for migration in Migrations.all where migration.version > applied {
      try transaction { db in
        try execScript(db, migration.sql)
        try db.execute(
          sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
          arguments: [migration.version, isoNow()]
        )
      }
    }
  }

  /// Highest applied migration version (0 when none).
  public func schemaVersion() throws -> Int {
    let exists = try raw.read { db in
      try Int.fetchOne(db, sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations'") != nil
    }
    guard exists else { return 0 }
    return try raw.read { db in
      try Int.fetchOne(db, sql: "SELECT coalesce(max(version), 0) FROM schema_migrations") ?? 0
    }
  }

  public func close() {
    try? raw.close()
  }
}

/// Migration files are multi-statement scripts; GRDB executes them verbatim.
func execScript(_ db: GRDB.Database, _ sql: String) throws {
  try db.execute(sql: sql)
}

/// JS `toISOString()` format.
func isoNow() -> String {
  let f = DateFormatter()
  f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
  f.timeZone = TimeZone(identifier: "UTC")
  f.locale = Locale(identifier: "en_US_POSIX")
  return f.string(from: Date())
}

/// The library's `schema_migrations` records a version this build does not know.
public struct SchemaTooNewError: Error, Equatable, Sendable {
  public let found: Int
  public let supported: Int
  public init(found: Int, supported: Int) {
    self.found = found
    self.supported = supported
  }
  public var message: String {
    "library schema version \(found) is newer than this app supports (\(supported)); update the app"
  }
}

/// One schema migration. `sql` may contain many statements.
public struct Migration: Sendable {
  public let version: Int
  public let name: String
  public let sql: String
}

/// Every migration, ascending, loaded verbatim from the bundled `.sql` resources.
public enum Migrations {
  public static let files: [(version: Int, name: String, file: String)] = [
    (1, "001-init", "001-init.sql"),
    (2, "002-one-collection-shape", "002-one-collection-shape.sql"),
    (3, "003-settle-trashed-items", "003-settle-trashed-items.sql")
  ]

  public static let all: [Migration] = files.map { entry in
    let url = Bundle.module.url(forResource: entry.name, withExtension: "sql", subdirectory: "Migrations")
      ?? Bundle.module.url(forResource: entry.file, withExtension: nil, subdirectory: "Migrations")
      ?? Bundle.module.url(forResource: entry.file, withExtension: nil)
    guard let url, let sql = try? String(contentsOf: url, encoding: .utf8) else {
      fatalError("migration resource missing from bundle: \(entry.file)")
    }
    return Migration(version: entry.version, name: entry.name, sql: sql)
  }
}

/// Options for `openDatabase`.
public struct OpenDatabaseOptions: Sendable {
  /// Milliseconds to wait on a locked database (default 5000).
  public var busyTimeoutMs: Int
  /// Open read-only; another process holds `library.lock`. Never migrate then.
  public var readOnly: Bool
  public init(busyTimeoutMs: Int = 5000, readOnly: Bool = false) {
    self.busyTimeoutMs = busyTimeoutMs
    self.readOnly = readOnly
  }
}

/// Open (creating if needed) the library database with the production PRAGMAs. Does not migrate.
public func openDatabase(file: String, options: OpenDatabaseOptions = OpenDatabaseOptions()) throws -> Db {
  var config = Configuration()
  config.readonly = options.readOnly
  config.prepareDatabase { db in
    if file != ":memory:", !options.readOnly {
      try db.execute(sql: "PRAGMA journal_mode = WAL")
    }
    try db.execute(sql: "PRAGMA busy_timeout = \(max(0, options.busyTimeoutMs))")
    try db.execute(sql: "PRAGMA foreign_keys = ON")
    try db.execute(sql: "PRAGMA synchronous = NORMAL")
    try db.execute(sql: "PRAGMA temp_store = MEMORY")
  }
  let raw: any DatabaseWriter =
    file == ":memory:"
    ? try DatabaseQueue(path: file, configuration: config)
    : try DatabasePool(path: file, configuration: config)
  return Db(raw: raw)
}

/// Minimal lock wrapper (no new deps; NSLock is fine too but Mutex is free on this toolchain).
final class Mutex<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value
  init(_ value: Value) { self.value = value }
  func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }
}
