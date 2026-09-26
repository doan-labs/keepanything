import Foundation

/**
 * `library.lock` sits next to `library.db` and names the process that may write. Any app that
 * opens the library uses the same JSON shape: `{ "pid": 123, "app": "electron", "version": "0.1.0",
 * "since": "<ISO>" }`. Port of `storage/library-lock.ts`.
 */
public struct LockOwner: Codable, Equatable, Sendable {
  public var pid: Int
  public var app: String
  public var version: String
  public var since: String
}

/// The lock acquisition result.
public struct LibraryLock: Sendable {
  /// False when this process holds `library.lock`; true when another live process does.
  public let readOnly: Bool
  /// The process that holds the lock (this one unless `readOnly`).
  public let owner: LockOwner
  /// Remove the file if this process still owns it. Safe to call twice.
  public let release: @Sendable () -> Void
}

public struct AcquireLockOptions: Sendable {
  public var pid: Int?
  public var app: String?
  public var version: String?
  public var now: (@Sendable () -> String)?
  /// Liveness probe, `kill(pid, 0)` by default.
  public var isAlive: (@Sendable (Int) -> Bool)?
  public init(pid: Int? = nil, app: String? = nil, version: String? = nil,
              now: (@Sendable () -> String)? = nil, isAlive: (@Sendable (Int) -> Bool)? = nil) {
    self.pid = pid
    self.app = app
    self.version = version
    self.now = now
    self.isAlive = isAlive
  }
}

public let LOCK_FILE_NAME = "library.lock"

public func lockFile(_ userData: String) -> String {
  (userData as NSString).appendingPathComponent(LOCK_FILE_NAME)
}

public func processIsAlive(_ pid: Int) -> Bool {
  kill(Int32(pid), 0) == 0 || errno == EPERM
}

public func readLockOwner(_ file: String) -> LockOwner? {
  guard let data = FileManager.default.contents(atPath: file),
        let text = String(data: data, encoding: .utf8),
        let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
  else { return nil }
  guard let pid = parsed["pid"] as? Int, pid > 0 else { return nil }
  return LockOwner(
    pid: pid,
    app: parsed["app"] as? String ?? "unknown",
    version: parsed["version"] as? String ?? "",
    since: parsed["since"] as? String ?? ""
  )
}

/// Take `library.lock` for this process. First writer wins via `O_EXCL`; a lock whose pid is dead
/// (or whose file is unreadable) is stale and taken over; a lock whose pid is alive leaves the
/// caller read-only.
public func acquireLibraryLock(_ userData: String, options: AcquireLockOptions = AcquireLockOptions()) -> LibraryLock {
  let file = lockFile(userData)
  let isAlive = options.isAlive ?? processIsAlive
  let mine = LockOwner(
    pid: options.pid ?? Int(ProcessInfo.processInfo.processIdentifier),
    app: options.app ?? "swift",
    version: options.version ?? "",
    since: (options.now ?? { isoNow() })()
  )
  let payload = (String(data: try! JSONEncoder().encode(mine), encoding: .utf8)!) + "\n"

  let held = { () -> LibraryLock in
    LibraryLock(readOnly: false, owner: mine, release: {
      guard let current = readLockOwner(file), current.pid == mine.pid else { return }
      try? FileManager.default.removeItem(atPath: file)
    })
  }

  let fd = open(file, O_WRONLY | O_CREAT | O_EXCL, 0o600)
  if fd >= 0 {
    payload.withCString { ptr in _ = write(fd, ptr, payload.utf8.count) }
    close(fd)
    return held()
  }
  precondition(errno == EEXIST, "open \(file) failed: \(errno)")

  if let existing = readLockOwner(file), existing.pid != mine.pid, isAlive(existing.pid) {
    return LibraryLock(readOnly: true, owner: existing, release: {})
  }

  // Stale (dead pid, or unreadable): replace atomically so a concurrent reader never sees a torn file.
  let temp = "\(file).\(mine.pid).tmp"
  try? FileManager.default.removeItem(atPath: temp)
  try? payload.write(toFile: temp, atomically: false, encoding: .utf8)
  rename(temp, file) // rename(2) replaces atomically, unlike FileManager.moveItem
  return held()
}
