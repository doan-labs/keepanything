/// IPC contract names (port of `electron/src/shared/ipc.ts`). The request/response payload types
/// live in `Types.swift`; only the channel/event wire names and the error envelope are here.

/// Every request channel. Keys are for code, values are the wire names (declaration order
/// preserved — `IPC_CHANNEL_LIST` and the parity fixture depend on it).
public let IPC_CHANNELS: [(key: String, channel: String)] = [
  ("itemsList", "items:list"),
  ("itemsGet", "items:get"),
  ("itemsUpdate", "items:update"),
  ("itemsTrash", "items:trash"),
  ("itemsRestore", "items:restore"),
  ("itemsDeleteForever", "items:deleteForever"),
  ("itemsCancel", "items:cancel"),
  ("itemsReprocess", "items:reprocess"),
  ("itemsReprocessAll", "items:reprocessAll"),
  ("itemsOpenOriginal", "items:openOriginal"),
  ("itemsRevealInFinder", "items:revealInFinder"),
  ("itemsQuickLook", "items:quickLook"),
  ("itemsOpenUrl", "items:openUrl"),
  ("itemsReadContent", "items:readContent"),
  ("captureFiles", "capture:files"),
  ("captureUrl", "capture:url"),
  ("captureText", "capture:text"),
  ("captureBlob", "capture:blob"),
  ("captureDrop", "capture:drop"),
  ("collectionsList", "collections:list"),
  ("collectionsCreate", "collections:create"),
  ("collectionsRename", "collections:rename"),
  ("collectionsDelete", "collections:delete"),
  ("collectionsAddItems", "collections:addItems"),
  ("collectionsRemoveItem", "collections:removeItem"),
  ("relationshipsCreate", "relationships:create"),
  ("relationshipsRemove", "relationships:remove"),
  ("searchQuick", "search:quick"),
  ("agentCommand", "agent:command"),
  ("agentCancel", "agent:cancel"),
  ("agentRun", "agent:run"),
  ("agentRuns", "agent:runs"),
  ("agentUndo", "agent:undo"),
  ("agentUndoRun", "agent:undoRun"),
  ("agentApplyProposals", "agent:applyProposals"),
  ("settingsGet", "settings:get"),
  ("settingsResetData", "settings:resetData"),
  ("settingsUpdate", "settings:update"),
  ("settingsTestConnection", "settings:testConnection"),
  ("systemStats", "system:stats"),
  ("systemContextMenu", "system:contextMenu"),
  ("systemOpenExternal", "system:openExternal"),
  ("systemChooseFiles", "system:chooseFiles"),
  ("systemRevealLibrary", "system:revealLibrary"),
  ("systemUpdateStatus", "system:updateStatus"),
  ("systemCheckForUpdates", "system:checkForUpdates"),
  ("systemInstallUpdate", "system:installUpdate"),
  ("jobsStatus", "jobs:status")
]

/// All request channel names in declaration order.
public let IPC_CHANNEL_LIST: [String] = IPC_CHANNELS.map(\.channel)

public func isIpcChannel(_ value: String) -> Bool { IPC_CHANNEL_LIST.contains(value) }

/// Every push event. Keys are for code, values are the wire names.
public let IPC_EVENTS: [(key: String, event: String)] = [
  ("itemsChanged", "items:changed"),
  ("jobsProgress", "jobs:progress"),
  ("collectionsChanged", "collections:changed"),
  ("agentRun", "agent:run"),
  ("shelfDropped", "shelf:dropped"),
  ("shelfPresence", "shelf:presence"),
  ("shelfDrag", "shelf:drag"),
  ("settingsChanged", "settings:changed"),
  ("themeChanged", "theme:changed"),
  ("updateStatus", "update:status")
]

/// All push event names in declaration order.
public let IPC_EVENT_LIST: [String] = IPC_EVENTS.map(\.event)

public func isIpcEventName(_ value: String) -> Bool { IPC_EVENT_LIST.contains(value) }

/// Error codes a handler may surface to the UI.
public enum IpcErrorCode: String, Codable, Sendable, CaseIterable {
  case validation = "VALIDATION"
  case notFound = "NOT_FOUND"
  case conflict = "CONFLICT"
  case notImplemented = "NOT_IMPLEMENTED"
  case aiNotConfigured = "AI_NOT_CONFIGURED"
  case aiUnavailable = "AI_UNAVAILABLE"
  case offline = "OFFLINE"
  case cancelled = "CANCELLED"
  case internalError = "INTERNAL"
}

/// Error half of the envelope. `message` is safe to show to the user.
public struct IpcError: Codable, Sendable, Equatable {
  public var code: IpcErrorCode
  public var message: String
  public init(code: IpcErrorCode, message: String) {
    self.code = code
    self.message = message
  }
}

/// Every request result: `{ ok: true, data } | { ok: false, error }`.
public enum IpcEnvelope<T> {
  case ok(T)
  case error(IpcError)

  public var data: T? {
    if case .ok(let d) = self { return d }
    return nil
  }

  public var errorValue: IpcError? {
    if case .error(let e) = self { return e }
    return nil
  }
}
