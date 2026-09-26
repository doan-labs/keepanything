import Foundation
import KAModel
import KAStorage

/// The port protocols the core services need (`ports.ts`). The rest of ports.ts lands with later
/// features (intake, retrieval, agent, ...).

/// Structured fields attached to a log line. Secrets are redacted by the logger.
public typealias LogFields = [String: JSONValue]

/// JSON-lines logger with child scopes (`lib/logger.ts`).
public protocol Logger: Sendable {
  func debug(_ msg: String, fields: LogFields)
  func info(_ msg: String, fields: LogFields)
  func warn(_ msg: String, fields: LogFields)
  func error(_ msg: String, fields: LogFields)
  /// New logger that merges `fields` into every line.
  func child(_ fields: LogFields) -> Logger
}

public extension Logger {
  func debug(_ msg: String) { debug(msg, fields: [:]) }
  func info(_ msg: String) { info(msg, fields: [:]) }
  func warn(_ msg: String) { warn(msg, fields: [:]) }
  func error(_ msg: String) { error(msg, fields: [:]) }
}

/// Injected clock so schedulers and backoff are testable.
public protocol Clock: Sendable {
  func now() -> Date
  /// `now().toISOString()`.
  func nowIso() -> String
}

/// One domain event, mirroring `DomainEventMap`. `name` returns the TS event name.
public enum DomainEvent: Sendable {
  case itemCreated(ItemsChangedEvent)
  case itemUpdated(ItemsChangedEvent)
  case itemTrashed(ItemsChangedEvent)
  case itemRestored(ItemsChangedEvent)
  case itemDeleted(ItemsChangedEvent)
  case jobProgress(JobProgress)
  case agentRun(AgentRunEvent)
  case collectionsChanged
  case settingsChanged(Settings)
  case aiStatus(AiStatus)

  public var name: String {
    switch self {
    case .itemCreated: return "item.created"
    case .itemUpdated: return "item.updated"
    case .itemTrashed: return "item.trashed"
    case .itemRestored: return "item.restored"
    case .itemDeleted: return "item.deleted"
    case .jobProgress: return "job.progress"
    case .agentRun: return "agent.run"
    case .collectionsChanged: return "collections.changed"
    case .settingsChanged: return "settings.changed"
    case .aiStatus: return "ai.status"
    }
  }
}

public typealias EventCancel = @Sendable () -> Void

/// Typed synchronous event bus. Listeners must not throw; errors are logged, never propagated.
public protocol EventBus: Sendable {
  /// Register a listener for one event name; returns a cancel function.
  @discardableResult
  func on(_ event: String, listener: @escaping @Sendable (DomainEvent) -> Void) -> EventCancel
  func off(_ event: String, listener: @escaping @Sendable (DomainEvent) -> Void)
  func emit(_ event: DomainEvent)
}

/// What the item service needs from the pipeline (implemented by `KAPipeline.Queue`).
public protocol ItemPipeline: Sendable {
  @discardableResult
  func enqueueInitial(_ item: Item) -> [Job]
  @discardableResult
  func enqueueFrom(_ item: Item, from: Stage?) -> [Job]
  @discardableResult
  func cancelForItems(_ itemIds: [String]) -> [Job]
}
