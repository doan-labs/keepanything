import Foundation
import GRDB
import KAModel
import Testing
#if canImport(CryptoKit)
  import CryptoKit
#endif
@testable import KAStorage

/// Port of `electron/tests/unit/reset-data.test.ts`.
@Suite struct ResetData {
  private func tempRoot() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ka-reset-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

  @Test func clearsAppDataOnNextLaunchWhilePreservingOriginalsAndModels() throws {
    let root = try tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let profile = root.appendingPathComponent("profile")
    try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
    let original = root.appendingPathComponent("original.txt")
    try "original content".write(to: original, atomically: true, encoding: .utf8)
    let directories = ["objects", "thumbs", "snapshots", "content", "logs", "url-cache"]
    let files = ["library.db", "library.db-wal", "library.db-shm", "library.db-journal", "config.json"]
    for dir in directories + ["models"] {
      let d = profile.appendingPathComponent(dir)
      try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
      try "stored data".write(to: d.appendingPathComponent("data"), atomically: true, encoding: .utf8)
    }
    try FileManager.default.createSymbolicLink(at: profile.appendingPathComponent("objects/linked-original"),
                                             withDestinationURL: original)
    for file in files {
      try "stored data".write(to: profile.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }
    #expect(applyPendingDataReset(profile.path) == false)
    try requestDataReset(profile.path)
    #expect(exists(profile.appendingPathComponent("library.db")))
    #expect(applyPendingDataReset(profile.path) == true)
    for entry in directories + files {
      #expect(!exists(profile.appendingPathComponent(entry)), Comment(rawValue: entry))
    }
    #expect(try String(contentsOf: original, encoding: .utf8) == "original content")
    #expect(exists(profile.appendingPathComponent("models/data")))
    // Partial reset: marker survives until finish, so a re-run keeps deleting.
    #expect(applyPendingDataReset(profile.path) == true)
    finishDataReset(profile.path)
    #expect(applyPendingDataReset(profile.path) == false)
  }

  @Test func unlinksManagedSymlinksWithoutTraversingOriginalFolders() throws {
    let root = try tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let profile = root.appendingPathComponent("profile")
    let originals = root.appendingPathComponent("originals")
    try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
    try "keep".write(to: originals.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: profile.appendingPathComponent("objects"),
                                             withDestinationURL: originals)
    try requestDataReset(profile.path)
    applyPendingDataReset(profile.path)
    #expect(try String(contentsOf: originals.appendingPathComponent("keep.txt"), encoding: .utf8) == "keep")
  }
}

/// No dedicated TS test files for object-store/paths — smoke coverage of the ported surface.
@Suite struct ObjectStorePaths {
  @Test func buildPathsLayoutAndResolve() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ka-paths-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let paths = buildPaths(dir.path, resourcesModelsDir: "/res/models")
    #expect(paths.dbFile == dir.path + "/library.db")
    #expect(configFile(paths) == dir.path + "/config.json")
    try ensureLibraryDirs(paths)
    for d in [paths.objectsDir, paths.thumbsDir, paths.snapshotsDir, paths.contentDir,
              paths.modelsDir, paths.logsDir, paths.urlCacheDir] {
      #expect(FileManager.default.fileExists(atPath: d))
    }
    #expect(resolveMediaPath(paths, ParsedMediaUrl(root: "thumbs", relPath: "a/b.png", version: 1))
      == paths.thumbsDir + "/a/b.png")
    #expect(resolveMediaPath(paths, ParsedMediaUrl(root: "thumbs", relPath: "../secret", version: 1)) == nil)
    #expect(resolveMediaPath(paths, ParsedMediaUrl(root: "thumbs", relPath: "", version: 1)) == nil)
  }

  @Test func objectStoreStoresRemovesAndRejectsTraversal() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ka-obj-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let paths = buildPaths(dir.path)
    try ensureLibraryDirs(paths)
    let store = ObjectStore(paths: paths)

    let src = dir.appendingPathComponent("src.txt")
    try "hello".write(to: src, atomically: true, encoding: .utf8)
    let copied = try store.copyFile("item-1", sourcePath: src.path, preferredName: "my file?.txt")
    #expect(copied.managedPath == "item-1/my file?.txt")
    #expect(copied.size == 5)
    #expect(copied.sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    #expect(store.managedExists(copied.managedPath))
    #expect(store.originalExists(src.path))

    let written = try store.writeBytes("item-2", name: "note.md", bytes: Data("abc".utf8))
    #expect(written.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(try Data(contentsOf: URL(fileURLWithPath: written.absolutePath)) == Data("abc".utf8))

    #expect(throws: (any Error).self) { try store.resolve("../x") }
    #expect(throws: (any Error).self) { try store.resolve("/abs") }
    #expect(!store.managedExists("../x"))

    try store.removeItem("item-1")
    #expect(!store.managedExists(copied.managedPath))
  }

  /// Pure-Swift SHA-256 vs CryptoKit (macOS) on a few vectors.
  @Test func sha256MatchesCryptoKit() {
    #if canImport(CryptoKit)
      let vectors = [Data(), Data("abc".utf8), Data("hello".utf8),
                     Data((0..<255).map { UInt8($0) }), Data(repeating: 0x61, count: 1_000_000)]
      for v in vectors {
        let expected = CryptoKit.SHA256.hash(data: v).map { String(format: "%02x", $0) }.joined()
        #expect(sha256Bytes(v) == expected)
      }
    #endif
  }
}

/// Port of `electron/tests/unit/library-lock.test.ts`.
@Suite struct LibraryLockTests {
  private func tempLibrary() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ka-lock-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private final class Alive: @unchecked Sendable {
    var pids: Set<Int> = []
  }

  private let alive = Alive()
  private var isAlive: @Sendable (Int) -> Bool { { self.alive.pids.contains($0) } }
  private var now: @Sendable () -> String { { "2026-01-01T00:00:00.000Z" } }
  private let nowIso = "2026-01-01T00:00:00.000Z"

  @Test func firstAppWritesLockWithPidAndHoldsIt() throws {
    let dir = try tempLibrary()
    defer { try? FileManager.default.removeItem(at: dir) }
    alive.pids.insert(100)
    let lock = acquireLibraryLock(dir.path, options: .init(pid: 100, app: "electron", version: "0.1.0", now: now, isAlive: isAlive))
    #expect(!lock.readOnly)
    #expect(lock.owner == LockOwner(pid: 100, app: "electron", version: "0.1.0", since: nowIso))
    #expect(lockFile(dir.path) == dir.path + "/" + LOCK_FILE_NAME)
    let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: lockFile(dir.path)))) as? [String: Any]
    #expect(parsed?["pid"] as? Int == 100)
    #expect(readLockOwner(lockFile(dir.path)) == lock.owner)
    lock.release()
    #expect(!FileManager.default.fileExists(atPath: lockFile(dir.path)))
    lock.release() // safe twice
  }

  @Test func secondAppSeesLiveOwnerAndOpensReadOnly() throws {
    let dir = try tempLibrary()
    defer { try? FileManager.default.removeItem(at: dir) }
    alive.pids.insert(100)
    let first = acquireLibraryLock(dir.path, options: .init(pid: 100, app: "electron", version: "0.1.0", now: now, isAlive: isAlive))
    let second = acquireLibraryLock(dir.path, options: .init(pid: 200, app: "swift", version: "1.0.0", now: now, isAlive: isAlive))
    #expect(second.readOnly)
    #expect(second.owner == first.owner)
    second.release()
    #expect(readLockOwner(lockFile(dir.path)) == first.owner)
    first.release()
    #expect(!FileManager.default.fileExists(atPath: lockFile(dir.path)))
  }

  @Test func staleLockFromDeadPidIsTakenOver() throws {
    let dir = try tempLibrary()
    defer { try? FileManager.default.removeItem(at: dir) }
    let payload = "{\"pid\":999,\"app\":\"electron\",\"version\":\"0.0.9\",\"since\":\"2025-12-31T00:00:00.000Z\"}\n"
    try payload.write(toFile: lockFile(dir.path), atomically: true, encoding: .utf8)
    alive.pids.insert(300)
    let lock = acquireLibraryLock(dir.path, options: .init(pid: 300, app: "electron", version: "0.1.0", now: now, isAlive: isAlive))
    #expect(!lock.readOnly)
    #expect(readLockOwner(lockFile(dir.path)) == LockOwner(pid: 300, app: "electron", version: "0.1.0", since: nowIso))
    #expect(!FileManager.default.fileExists(atPath: "\(lockFile(dir.path)).300.tmp"))
  }

  @Test func unreadableLockFileIsStale() throws {
    let dir = try tempLibrary()
    defer { try? FileManager.default.removeItem(at: dir) }
    try "not json".write(toFile: lockFile(dir.path), atomically: true, encoding: .utf8)
    alive.pids.insert(300)
    #expect(readLockOwner(lockFile(dir.path)) == nil)
    let lock = acquireLibraryLock(dir.path, options: .init(pid: 300, now: now, isAlive: isAlive))
    #expect(!lock.readOnly)
    #expect(readLockOwner(lockFile(dir.path))?.pid == 300)
  }

  @Test func releaseLeavesLockTakenOverByAnotherProcess() throws {
    let dir = try tempLibrary()
    defer { try? FileManager.default.removeItem(at: dir) }
    alive.pids.insert(100)
    let first = acquireLibraryLock(dir.path, options: .init(pid: 100, now: now, isAlive: isAlive))
    alive.pids.remove(100)
    alive.pids.insert(200)
    let second = acquireLibraryLock(dir.path, options: .init(pid: 200, now: now, isAlive: isAlive))
    #expect(!second.readOnly)
    first.release()
    #expect(readLockOwner(lockFile(dir.path))?.pid == 200)
  }

  @Test func processIsAliveAnswers() {
    #expect(processIsAlive(Int(ProcessInfo.processInfo.processIdentifier)))
    #expect(!processIsAlive(1 << 22 - 1))
  }

  @Test func readOnlyDatabaseReadsAndRefusesWrites() throws {
    let dir = try tempLibrary()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("library.db").path
    let writer = try openDatabase(file: file)
    try writer.migrate()
    let version = try writer.schemaVersion()
    writer.close()

    let reader = try openDatabase(file: file, options: .init(readOnly: true))
    defer { reader.close() }
    #expect(try reader.schemaVersion() == version)
    let mode = try reader.raw.read { d in try String.fetchOne(d, sql: "PRAGMA journal_mode") }
    #expect(mode == "wal")
    #expect(throws: (any Error).self) {
      try reader.raw.writeWithoutTransaction { d in
        try d.execute(sql: "INSERT INTO suppressions (kind, key, created_at) VALUES ('x', 'y', '2026-01-01')")
      }
    }
  }
}
