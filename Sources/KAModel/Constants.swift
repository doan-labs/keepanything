/// Limits, timeouts, defaults and product copy (port of `electron/src/shared/constants.ts`).

/// Hard limits and tunables for extraction, chunking, previews, the agent and the scheduler.
public enum LIMITS {
  /// `items.extracted_text` cap (chars).
  public static let maxExtractedChars = 60_000
  /// Text handed to the understand task (chars).
  public static let understandTextChars = 12_000
  /// Default `maxChars` of the `read_document` tool.
  public static let readDocumentChars = 8_000
  /// `ItemSummary.understanding` truncation (chars).
  public static let summaryUnderstandingMaxChars = 160
  /// `items.excerpt` cap (chars).
  public static let excerptChars = 280
  /// Body chunk size for embeddings (bge-small-en-v1.5 truncates at 512 wordpieces).
  public static let bodyChunkChars = 1800
  /// Maximum body chunks embedded per item.
  public static let maxBodyChunks = 24
  /// Folder import: maximum files imported as children.
  public static let folderMaxFiles = 500
  /// Folder import: maximum traversal depth.
  public static let folderMaxDepth = 4
  /// Folder task: number of text files sampled.
  public static let folderSampleFiles = 20
  /// Folder task: maximum bytes read per sampled file.
  public static let folderSampleFileBytes = 30_000
  /// Skip body embeddings for children of folders with more files than this.
  public static let folderChildrenBodyEmbedLimit = 50
  /// Thumbnail longest side (px).
  public static let thumbnailMaxPx = 800
  /// URL snapshot viewport width (px).
  public static let snapshotWidth = 1280
  /// URL snapshot viewport height (px).
  public static let snapshotHeight = 800
  /// Snapshot load budget (ms).
  public static let snapshotTimeoutMs = 20_000
  /// HTML fetch budget (ms).
  public static let fetchTimeoutMs = 15_000
  /// One model call budget (ms).
  public static let aiTimeoutMs = 60_000
  /// Batch organize runs at the latest this long after the first sibling was captured (ms).
  public static let batchGateMs = 90_000
  /// Step cap for the single-item organize task.
  public static let organizeSteps = 5
  /// Step cap for the batch organize task.
  public static let organizeBatchSteps = 10
  /// Step cap for the command task (Ask, multi-item, actions).
  public static let commandSteps = 12
  /// Prompt-token ceiling per run; reaching it forces `finish`.
  public static let runPromptTokenCeiling = 60_000
  /// Vector-only hits below this cosine are dropped (see the TS source for the eval rationale).
  public static let cosineFloor = 0.5
  /// Same type and cosine at or above this = `duplicate_of` without a model call.
  public static let nearDuplicateCosine = 0.95
  /// Memberships and new-collection proposals below this confidence are rejected.
  public static let minCollectionConfidence = 0.7
  /// Eligible members a proposed collection must have.
  public static let minNewCollectionMembers = 2
  /// Agent-written descriptions shorter than this are rejected.
  public static let minCollectionDescriptionChars = 40
  /// `nameSimilarity` at or above this folds a proposal into the existing collection.
  public static let collectionNameFold = 0.6
  /// Retry backoff per attempt (ms).
  public static let retryBackoffMs = [30_000, 120_000, 600_000]
  /// Maximum job attempts before `failed`.
  public static let maxAttempts = 3
  /// Scheduler lane concurrency.
  public static let lanes = Lanes(io: 2, embed: 1, ai: 1)

  public struct Lanes: Sendable, Equatable {
    public var io: Int
    public var embed: Int
    public var ai: Int
    public init(io: Int, embed: Int, ai: Int) {
      self.io = io
      self.embed = embed
      self.ai = ai
    }
  }
}

/// Flat top-level AI limits (separate constants in `ai/`).
public let STRUCTURED_MAX_TOKENS = 8192
public let STRUCTURED_MAX_TOKENS_CAP = 16384
public let STRUCTURED_FAILURE_MESSAGE = "Couldn't make sense of the model's answer. Try again in a moment."
public let AGENT_MAX_TOKENS = 8192
public let RUN_PROMPT_TOKEN_CEILING = 60_000

/// Directory names never traversed by the folder importer.
public let SKIP_DIR_NAMES: [String] = [
  "node_modules", ".git", "dist", "build", ".cache", "__pycache__", "Library",
  ".venv", "venv", ".next", ".turbo", "coverage", "DerivedData", "Pods", ".Trash"
]

/// Path fragments that mark macOS temporary locations (drops from browsers etc.): always copy.
public let TEMP_PATH_MARKERS: [String] = ["/private/var/folders", "TemporaryItems"]

/// Product copy. Functions take the variable part.
public enum COPY {
  public static let tagline = "Keep anything."
  public static let taglineRest = "We'll figure out the rest."
  public static let saved = "Saved."
  public static func foundRelated(_ n: Int) -> String {
    n == 1 ? "Linked to 1 thing." : "Linked to \(n) things."
  }
  public static func alreadyKept(_ ago: String) -> String { "Already kept · \(ago)" }
  public static let cantReadPage = "Couldn't read this page, but the link is safe."
  public static let stillFiguring = "Still figuring this one out."
  public static let emptyCollection = "Nothing here yet. Drag things in or let it fill up."
  public static let trashEmpty = "Trash is empty."
  public static func noMatches(_ q: String) -> String { "Nothing matches \"\(q)\"." }
  public static let askNothing = "Couldn't find anything about that."
  public static let askScanning = "Looking through your library"
  public static let askScanCaption = "Text, pages and pictures — all of it on this Mac"
  public static func askReading(_ n: Int) -> String {
    n == 1 ? "Reading 1 match" : "Reading \(n) matches"
  }
  public static func askFound(_ n: Int) -> String {
    n == 1 ? "Found it in 1 thing you kept" : "Found it in \(n) things you kept"
  }
  public static let askAnswered = "Answered from your library"
  public static let askStopTitle = "Stop the search?"
  public static let askStopBody = "It is still looking through your library. Whatever it has found so far stays on screen."
  public static let dropHint = "Drop anywhere"
  /// The shelf's own headline: it exists to be dropped on, so it says so.
  public static let dropHere = "Drop here"
  public static let dropSub = "Keep it for later"
  public static let pasteHint = "Paste a link (⌘V)"
  public static let notUnderstood = "Kept. Not understood yet."
  public static let connectHint = "Connect an AI provider in Settings to understand this."
}

/// Default reasoning model (GMI Cloud).
public let DEFAULT_MODEL = "MiniMaxAI/MiniMax-M3"

/// Default OpenAI-compatible base URL (GMI Cloud).
public let DEFAULT_BASE_URL = "https://api.gmi-serving.com/v1"

public struct AiProviderDefaults: Sendable, Equatable {
  public var model: String
  public var baseUrl: String
  public init(model: String, baseUrl: String) {
    self.model = model
    self.baseUrl = baseUrl
  }
}

public let AI_PROVIDER_DEFAULTS: [AiProviderId: AiProviderDefaults] = [
  .gmi: AiProviderDefaults(model: DEFAULT_MODEL, baseUrl: DEFAULT_BASE_URL),
  .openrouter: AiProviderDefaults(model: "minimax/minimax-m3", baseUrl: "https://openrouter.ai/api/v1")
]

public let AI_PROVIDER_LABEL: [AiProviderId: String] = [.gmi: "GMI", .openrouter: "OpenRouter"]

/// Markers FTS5 wraps around the matched words of a `SearchHit.snippet`; the UI highlights them.
public let SNIPPET_OPEN = "[["
public let SNIPPET_CLOSE = "]]"

/// Local embedding model id (Hugging Face hub layout under `models/`).
public let EMBEDDING_MODEL_ID = "Xenova/bge-small-en-v1.5"

/// Embedding vector size for `EMBEDDING_MODEL_ID` and the hash fallback.
public let EMBEDDING_DIMS = 384

/// Custom protocol serving files from the library (`ka-media://local/...`).
public let MEDIA_SCHEME = "ka-media"

/// DataTransfer MIME type for drags of items inside the app.
public let INTERNAL_DND_MIME = "application/x-keepanything-items"
