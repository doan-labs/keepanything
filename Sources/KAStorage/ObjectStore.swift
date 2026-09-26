import Foundation

/// Maximum length of a generated file name (conservative for APFS and URLs).
public let MAX_FILENAME_LENGTH = 180

/// Turn any string into a file name that is safe on macOS and inside URLs: no path separators,
/// control characters or leading dots, collapsed whitespace, capped length (extension preserved).
/// Falls back to `fallback` when nothing usable remains. Port of `lib/fs.ts` `safeFilename`.
public func safeFilename(_ name: String, _ fallback: String = "file") -> String {
  let base = URL(fileURLWithPath: name.replacingOccurrences(of: "\\", with: "/")).lastPathComponent
  var cleaned = String(base.map { ch -> Character in
    let bad = ch.unicodeScalars.contains { s in
      s.value <= 0x1f || s.value == 0x7f || s == "/" || s == "\\" || s == ":"
    }
    return bad ? " " : ch
  })
  // collapse whitespace
  cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  cleaned = cleaned.trimmingCharacters(in: .whitespaces)
  while cleaned.hasPrefix(".") { cleaned.removeFirst() }
  if cleaned.isEmpty { cleaned = fallback }
  if cleaned.count > MAX_FILENAME_LENGTH {
    let ext = (cleaned as NSString).pathExtension
    let keepExt = (!ext.isEmpty && ext.count <= 16) ? ".\(ext)" : ""
    cleaned = String(cleaned.dropLast(cleaned.count - (MAX_FILENAME_LENGTH - keepExt.count)))
      .trimmingCharacters(in: .whitespaces) + keepExt
  }
  return cleaned
}

/// Result of storing bytes or a file in the object store.
public struct StoredObject: Sendable, Equatable {
  /// Path relative to `objects/` (goes into `items.managed_path`).
  public var managedPath: String
  public var absolutePath: String
  public var size: Int
  public var sha256: String
}

enum ObjectStoreError: Error, Equatable {
  case absoluteManagedPath
  case escapesObjectStore
}

/**
 * Managed copies live at `objects/<itemId>/<safe-name>`. The store never touches originals except
 * to read them; deleting an item removes only its managed directory. Port of `object-store.ts`
 * (synchronous — the TS async surface is I/O sugar; semantics are identical).
 */
public struct ObjectStore: Sendable {
  let root: String
  public init(paths: Paths) { self.root = paths.objectsDir }

  /// Absolute path for a `managed_path` (relative to `objects/`). Throws on traversal.
  public func resolve(_ managedPath: String) throws -> String {
    if managedPath.hasPrefix("/") { throw ObjectStoreError.absoluteManagedPath }
    let abs = ((root as NSString).appendingPathComponent(managedPath) as NSString).standardizingPath
    let rootStd = (root as NSString).standardizingPath
    if !abs.hasPrefix(rootStd + "/") && abs != rootStd {
      throw ObjectStoreError.escapesObjectStore
    }
    return abs
  }

  private func dirFor(_ itemId: String) throws -> String {
    try resolve(safeFilename(itemId, "item"))
  }

  /// Copy a file into the item's directory. Hashes the copy.
  public func copyFile(_ itemId: String, sourcePath: String, preferredName: String? = nil) throws -> StoredObject {
    let dir = try dirFor(itemId)
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let name = safeFilename(preferredName ?? (sourcePath as NSString).lastPathComponent)
    let target = (dir as NSString).appendingPathComponent(name)
    try FileManager.default.copyItem(atPath: sourcePath, toPath: target)
    let hash = try sha256File(target)
    let size = (try? FileManager.default.attributesOfItem(atPath: target)[.size] as? Int) ?? 0
    return StoredObject(managedPath: "\((dir as NSString).lastPathComponent)/\(name)",
                        absolutePath: target, size: size, sha256: hash)
  }

  /// Write bytes into the item's directory (atomic temp+rename).
  public func writeBytes(_ itemId: String, name: String, bytes: Data) throws -> StoredObject {
    let dir = try dirFor(itemId)
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let safe = safeFilename(name)
    let target = (dir as NSString).appendingPathComponent(safe)
    let tmp = (dir as NSString).appendingPathComponent(".\(safe).\(ProcessInfo.processInfo.processIdentifier).tmp")
    do {
      try bytes.write(to: URL(fileURLWithPath: tmp))
      try FileManager.default.moveItem(atPath: tmp, toPath: target)
    } catch {
      try? FileManager.default.removeItem(atPath: tmp)
      throw error
    }
    return StoredObject(managedPath: "\((dir as NSString).lastPathComponent)/\(safe)",
                        absolutePath: target, size: bytes.count, sha256: sha256Bytes(bytes))
  }

  /// Delete the item's managed directory (no-op when absent).
  public func removeItem(_ itemId: String) throws {
    try FileManager.default.removeItem(atPath: dirFor(itemId))
  }

  /// True when the managed copy is on disk.
  public func managedExists(_ managedPath: String) -> Bool {
    (try? resolve(managedPath)).map { FileManager.default.fileExists(atPath: $0) } ?? false
  }

  /// True when the referenced original is on disk.
  public func originalExists(_ originalPath: String) -> Bool {
    originalPath.hasPrefix("/") && FileManager.default.fileExists(atPath: originalPath)
  }
}
