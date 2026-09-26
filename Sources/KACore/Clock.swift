import Foundation

/// Port of `lib/clock.ts` (lib/ has no module of its own; the core needs this first).

/// Wall-clock implementation used in production.
public struct SystemClock: Clock {
  public init() {}
  public func now() -> Date { Date() }
  public func nowIso() -> String { iso(Date()) }
}

public let systemClock: any Clock = SystemClock()

/// A clock that only moves when told to; for scheduler, backoff and batch-gate tests.
public final class ManualClock: Clock, @unchecked Sendable {
  private let lock = NSLock()
  private var current: Date

  /// `start` default: 2026-01-01T00:00:00Z.
  public init(start: String = "2026-01-01T00:00:00.000Z") {
    current = parseIso(start) ?? Date(timeIntervalSince1970: 1_767_225_600)
  }

  public init(start: Date) { current = start }

  public func now() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  public func nowIso() -> String { iso(now()) }

  public func advance(_ ms: Double) {
    lock.lock()
    current = current.addingTimeInterval(ms / 1000)
    lock.unlock()
  }

  public func set(_ date: Date) {
    lock.lock()
    current = date
    lock.unlock()
  }

  public func set(_ iso8601: String) {
    if let d = parseIso(iso8601) { set(d) }
  }
}

/// `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` — the exact JS `toISOString()` shape.
public func iso(_ date: Date) -> String {
  let f = DateFormatter()
  f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
  f.timeZone = TimeZone(identifier: "UTC")
  f.locale = Locale(identifier: "en_US_POSIX")
  return f.string(from: date)
}

func parseIso(_ s: String) -> Date? {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f.date(from: s)
}
