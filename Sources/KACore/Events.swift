import Foundation

/// Typed synchronous in-process event bus. Listener errors are logged and swallowed so one broken
/// subscriber (e.g. a closed window) never breaks a domain mutation. Port of `core/events.ts`.
public func createEventBus(logger: (any Logger)? = nil) -> EventBus {
  EventBusImpl(logger: logger)
}

private final class EventBusImpl: EventBus, @unchecked Sendable {
  private let logger: (any Logger)?
  private let lock = NSLock()
  private var listeners: [String: [(UUID, @Sendable (DomainEvent) -> Void)]] = [:]

  init(logger: (any Logger)?) { self.logger = logger }

  func on(_ event: String, listener: @escaping @Sendable (DomainEvent) -> Void) -> EventCancel {
    let id = UUID()
    lock.lock()
    listeners[event, default: []].append((id, listener))
    lock.unlock()
    return { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.listeners[event]?.removeAll { $0.0 == id }
      self.lock.unlock()
    }
  }

  func off(_ event: String, listener: @escaping @Sendable (DomainEvent) -> Void) {
    // TS deletes by Set identity; `as AnyObject` boxes the closure context, which is stable for
    // the same closure value (a stored function reference), so identity matching mirrors that.
    let id = ObjectIdentifier(listener as AnyObject)
    lock.lock()
    listeners[event]?.removeAll { ObjectIdentifier($0.1 as AnyObject) == id }
    lock.unlock()
  }

  func emit(_ event: DomainEvent) {
    lock.lock()
    let snapshot = listeners[event.name] ?? []
    lock.unlock()
    for (_, listener) in snapshot {
      do {
        try listenerOrThrow(listener, event)
      } catch {
        logger?.error("event listener failed", fields: ["event": .string(event.name)])
      }
    }
  }

  private func listenerOrThrow(_ l: @Sendable (DomainEvent) -> Void, _ e: DomainEvent) throws {
    l(e)
  }
}
