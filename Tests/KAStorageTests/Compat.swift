import Foundation
import KAModel
import Testing
@testable import KAStorage
@testable import KATestSupport

/// S-STORE-03: open the Electron-made library (`Tests/Fixtures/parity/library`, regenerated via
/// `pnpm run parity:library`) and prove the snapshot matches `Tests/E2E/expected/library-compat.json`.
@Suite struct Compat {
  private let fixtureLibrary = repoRoot().appendingPathComponent("Tests/Fixtures/parity/library")
  private let expectedFile = repoRoot().appendingPathComponent("Tests/E2E/expected/library-compat.json")

  private func copyFixture() throws -> URL {
    let dest = FileManager.default.temporaryDirectory.appendingPathComponent("ka-compat-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: fixtureLibrary, to: dest)
    return dest
  }

  /// First difference between two JSONValue trees, for readable failures.
  private func firstDiff(_ a: JSONValue, _ b: JSONValue, path: String) -> String? {
    switch (a, b) {
    case (.object(let x), .object(let y)):
      for k in Set(x.keys).union(y.keys) {
        if let d = firstDiff(x[k] ?? .null, y[k] ?? .null, path: "\(path).\(k)") { return d }
      }
      return nil
    case (.array(let x), .array(let y)):
      if x.count != y.count { return "\(path): array length \(x.count) != \(y.count)" }
      for i in x.indices {
        if let d = firstDiff(x[i], y[i], path: "\(path)[\(i)]") { return d }
      }
      return nil
    case (.number(let x), .number(let y)) where x == y: return nil
    default:
      return a == b ? nil : "\(path): \(a) != \(b)"
    }
  }

  @Test func electronLibrarySnapshotsIdentically() throws {
    let dir = try copyFixture()
    defer { try? FileManager.default.removeItem(at: dir) }

    let lock = acquireLibraryLock(dir.path)
    #expect(!lock.readOnly)
    defer { lock.release() }

    let db = try openDatabase(file: dir.appendingPathComponent("library.db").path)
    defer { db.close() }
    try db.migrate()
    #expect(try db.schemaVersion() == 3)

    var markers = try JSONDecoder()
      .decode([Marker].self, from: Data(contentsOf: fixtureLibrary.appendingPathComponent("markers.json")))
      .map { (find: $0.find, marker: $0.marker) }
    markers.append((find: dir.path, marker: "{library}"))

    let state = Snapshot.normalize(try Snapshot.take(db), prefixes: markers)
    guard case .object(let got) = state else { Issue.record("snapshot is not an object"); return }

    let expected = try JSONDecoder().decode(ExpectedDoc.self, from: Data(contentsOf: expectedFile))
    guard case .object(let want) = expected.results.first?.value else {
      Issue.record("expected results[0] is not an object"); return
    }
    for key in Snapshot.tableKeys {
      if let diff = firstDiff(got[key] ?? .null, want[key] ?? .null, path: key) {
        Issue.record(Comment(rawValue: "snapshot mismatch: \(diff)"))
      }
    }
  }

  @Test func liveLockYieldsReadOnlyDatabase() throws {
    let dir = try copyFixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("library.db").path

    // Another live process (this one) holds the lock.
    let held = acquireLibraryLock(dir.path)
    #expect(!held.readOnly)
    defer { held.release() }

    // A different pid, so the live-lock check (owner.pid != mine) applies, as in the TS tests.
    let second = acquireLibraryLock(dir.path, options: .init(pid: 999_998, app: "other"))
    #expect(second.readOnly)
    #expect(second.owner.pid == ProcessInfo.processInfo.processIdentifier)
    defer { second.release() }

    let reader = try openDatabase(file: file, options: .init(readOnly: true))
    defer { reader.close() }
    #expect(try reader.schemaVersion() == 3)
    #expect(throws: (any Error).self) {
      try reader.raw.writeWithoutTransaction { d in
        try d.execute(sql: "INSERT INTO suppressions (kind, key, created_at) VALUES ('x', 'y', 'now')")
      }
    }
  }

  @Test func staleLockIsTakenOver() throws {
    let dir = try copyFixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let deadPid = 999_999
    let owner = LockOwner(pid: deadPid, app: "electron", version: "0.0.9", since: "2025-12-31T00:00:00.000Z")
    try (String(data: JSONEncoder().encode(owner), encoding: .utf8)! + "\n")
      .write(toFile: lockFile(dir.path), atomically: true, encoding: .utf8)

    let lock = acquireLibraryLock(dir.path)
    #expect(!lock.readOnly)
    #expect(lock.owner.pid == ProcessInfo.processInfo.processIdentifier)
    lock.release()
  }

  private struct Marker: Decodable { let find: String; let marker: String }
  private struct ExpectedDoc: Decodable { let results: [ResultBox] }
  private struct ResultBox: Decodable {
    let value: JSONValue
    init(from decoder: any Decoder) throws { value = try JSONValue(from: decoder) }
  }
}
