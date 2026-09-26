import Foundation
import KAModel

/// Library layout under `userData`. The caller passes `app.getPath('userData')` and, when
/// packaged, `<resourcesPath>/models`. Port of `storage/paths.ts`.
public struct Paths: Sendable, Equatable {
  public var userData: String
  public var dbFile: String
  public var objectsDir: String
  public var thumbsDir: String
  public var snapshotsDir: String
  public var contentDir: String
  public var modelsDir: String
  public var logsDir: String
  public var urlCacheDir: String
  public var resourcesModelsDir: String?
}

public func buildPaths(_ userData: String, resourcesModelsDir: String? = nil) -> Paths {
  let join = { (a: String) in (userData as NSString).appendingPathComponent(a) }
  return Paths(
    userData: userData,
    dbFile: join("library.db"),
    objectsDir: join("objects"),
    thumbsDir: join("thumbs"),
    snapshotsDir: join("snapshots"),
    contentDir: join("content"),
    modelsDir: join("models"),
    logsDir: join("logs"),
    urlCacheDir: join("url-cache"),
    resourcesModelsDir: resourcesModelsDir
  )
}

/// Create every library directory (idempotent).
public func ensureLibraryDirs(_ paths: Paths) throws {
  for dir in [paths.userData, paths.objectsDir, paths.thumbsDir, paths.snapshotsDir,
              paths.contentDir, paths.modelsDir, paths.logsDir, paths.urlCacheDir] {
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
  }
}

/// Absolute path of the config file (settings + encrypted secrets).
public func configFile(_ paths: Paths) -> String {
  (paths.userData as NSString).appendingPathComponent("config.json")
}

/// Directory behind a `ka-media://` root.
public func mediaRootDir(_ paths: Paths, _ root: String) -> String {
  switch root {
  case "objects": paths.objectsDir
  case "thumbs": paths.thumbsDir
  case "snapshots": paths.snapshotsDir
  case "content": paths.contentDir
  default: paths.objectsDir
  }
}

/// Absolute file path for a parsed `ka-media://` URL, or nil when it would escape its root.
public func resolveMediaPath(_ paths: Paths, _ parsed: ParsedMediaUrl) -> String? {
  let rootDir = mediaRootDir(paths, parsed.root)
  let root = (rootDir as NSString).standardizingPath
  let abs = ((rootDir as NSString).appendingPathComponent(parsed.relPath) as NSString).standardizingPath
  if abs == root || !abs.hasPrefix(root + "/") { return nil }
  return abs
}
