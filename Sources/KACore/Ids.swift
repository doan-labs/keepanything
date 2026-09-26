import Foundation

/// Id generator; injected so tests can produce deterministic ids. Port of `core/ids.ts`.
public typealias IdGenerator = @Sendable () -> String

/// UUID v4 ids for every row (lowercase, like Node `randomUUID`).
public let uuid: IdGenerator = { UUID().uuidString.lowercased() }

/// Sequential ids (`prefix-1`, `prefix-2`, ...) for tests. Thread-safe.
public func sequentialIds(_ prefix: String = "id") -> IdGenerator {
  let counter = IdCounter()
  return { counter.next(prefix) }
}

private final class IdCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var n = 0
  func next(_ prefix: String) -> String {
    lock.lock()
    defer { lock.unlock() }
    n += 1
    return "\(prefix)-\(n)"
  }
}
