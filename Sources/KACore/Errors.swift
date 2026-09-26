import Foundation
import KAModel

/// The one error type that crosses layer boundaries. Handlers throw it; the IPC router maps
/// `code`/`message` into the error envelope. `details` is for logs only and never reaches the
/// renderer. Honest stubs throw `KaError(.notImplemented, "...")`. Port of `core/errors.ts`.
public struct KaError: Error, Sendable, Equatable {
  public let code: IpcErrorCode
  public let message: String
  /// Log-only; never serialized to the renderer.
  public let details: JSONValue?

  public init(_ code: IpcErrorCode, _ message: String, details: JSONValue? = nil) {
    self.code = code
    self.message = message
    self.details = details
  }
}

/// `KaError` when `error` is one. (TS checks the shape across bundles; Swift has a real type.)
public func isKaError(_ error: any Error) -> Bool {
  error is KaError
}

/// `KaError` when `error` is one (typed accessor).
public func asKaError(_ error: any Error) -> KaError? {
  error as? KaError
}
