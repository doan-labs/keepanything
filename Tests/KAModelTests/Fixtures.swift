import Foundation

/// Locate the repo root by walking up from this file to the dir containing Package.swift,
/// then read `Tests/Fixtures/parity/<name>.json` (read-only; never edit).
func repoRoot(file: String = #filePath) -> URL {
  var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
  while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
    let parent = dir.deletingLastPathComponent()
    precondition(parent != dir, "Package.swift not found above \(file)")
    dir = parent
  }
  return dir
}

func loadParityFixture(_ name: String) -> Any {
  let url = repoRoot()
    .appendingPathComponent("Tests/Fixtures/parity/\(name).json")
  let data = try! Data(contentsOf: url)
  return try! JSONSerialization.jsonObject(with: data)
}
