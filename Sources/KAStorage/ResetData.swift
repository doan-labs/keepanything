import Foundation

/// Port of `storage/reset-data.ts`.
private let RESET_MARKER = "reset-pending"
/// Only app-owned entries; never derive deletion targets from item original paths.
private let RESET_ENTRIES = [
  "library.db",
  "library.db-wal",
  "library.db-shm",
  "library.db-journal",
  "objects",
  "thumbs",
  "snapshots",
  "content",
  "logs",
  "url-cache",
  "config.json"
]

private func join(_ dir: String, _ name: String) -> String {
  (dir as NSString).appendingPathComponent(name)
}

public func requestDataReset(_ userData: String) throws {
  try "".write(toFile: join(userData, RESET_MARKER), atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: join(userData, RESET_MARKER))
}

/// Run in the next process, before opening the database or starting any producers. Leaves the
/// marker on failure so a partial reset is retried on the next launch. Returns whether a reset ran.
@discardableResult
public func applyPendingDataReset(_ userData: String) -> Bool {
  let marker = join(userData, RESET_MARKER)
  guard FileManager.default.fileExists(atPath: marker) else { return false }
  for entry in RESET_ENTRIES { try? FileManager.default.removeItem(atPath: join(userData, entry)) }
  return true
}

public func finishDataReset(_ userData: String) {
  try? FileManager.default.removeItem(atPath: join(userData, RESET_MARKER))
}
