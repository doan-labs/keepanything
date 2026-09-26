import Foundation
@testable import KAStorage

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
  let url = repoRoot().appendingPathComponent("Tests/Fixtures/parity/\(name).json")
  let data = try! Data(contentsOf: url)
  return try! JSONSerialization.jsonObject(with: data)
}

func tempDbFile() -> (dir: URL, file: String) {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ka-db-\(UUID().uuidString)")
  try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return (dir, dir.appendingPathComponent("library.db").path)
}

func cleanup(_ dir: URL) {
  try? FileManager.default.removeItem(at: dir)
}
