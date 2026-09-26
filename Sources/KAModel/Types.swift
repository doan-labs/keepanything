/// Domain types shared by every module (port of `electron/src/shared/types.ts`).
/// Row models are camelCase mirrors of `storage/migrations/001-init.sql`; JSON columns are
/// already parsed. Timestamps are ISO-8601 UTC strings; ids are UUID v4 strings.

/// Physical form of a captured object; drives the pipeline graph and the card body.
public enum ItemType: String, Codable, Sendable, CaseIterable {
  case file, folder, image, video, audio, pdf, text, markdown, url, note, unknown
}

/// Subtypes for `type == .url`, detected by the URL adapters.
public enum UrlSubtype: String, Codable, Sendable, CaseIterable {
  case article, githubRepo = "github_repo", youtube, tweet, product, docs, paper, figma, social, generic
}

/// Subtypes for `type == .image`, detected by the image extractor heuristics.
public enum ImageSubtype: String, Codable, Sendable, CaseIterable {
  case screenshot, photo, design, generic
}

/// Subtypes for `type == .file`, derived from mime type / extension.
public enum FileSubtype: String, Codable, Sendable, CaseIterable {
  case document, spreadsheet, presentation, archive, code, data, other
}

/// Union of every subtype; which ones are valid depends on `ItemType`.
public enum ItemSubtype: Hashable, Codable, Sendable {
  case url(UrlSubtype)
  case image(ImageSubtype)
  case file(FileSubtype)

  public var rawValue: String {
    switch self {
    case .url(let s): s.rawValue
    case .image(let s): s.rawValue
    case .file(let s): s.rawValue
    }
  }

  public init?(rawValue: String) {
    if let s = UrlSubtype(rawValue: rawValue) { self = .url(s); return }
    if let s = ImageSubtype(rawValue: rawValue) { self = .image(s); return }
    if let s = FileSubtype(rawValue: rawValue) { self = .file(s); return }
    return nil
  }

  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let v = ItemSubtype(rawValue: raw) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown subtype \(raw)"))
    }
    self = v
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(rawValue)
  }
}

/// Which item columns a user has edited by hand; the agent must not overwrite them.
public enum UserOverridableField: String, Codable, Sendable, CaseIterable {
  case title, understanding, whyUseful, kind, topics, entities
}

/// `items.user_overrides` JSON: `{ "title": true, ... }`.
public struct UserOverrides: Codable, Sendable, Equatable {
  public var title: Bool?
  public var understanding: Bool?
  public var whyUseful: Bool?
  public var kind: Bool?
  public var topics: Bool?
  public var entities: Bool?
  public init() {}
}

/// Open Graph / page metadata captured for URL items.
public struct OpenGraphMetadata: Codable, Sendable, Equatable {
  public var title: String?
  public var description: String?
  public var image: String?
  public var siteName: String?
  public var type: String?
  public var canonical: String?
  public init() {}
}

/// GitHub repository facts shown on the repo card (`ItemSummary.card`).
public struct RepoMetadata: Codable, Sendable, Equatable {
  public var owner: String?
  public var name: String?
  public var description: String?
  public var language: String?
  public var stars: Double?
  public var forks: Double?
  public var topics: [String]?
  public var defaultBranch: String?
  public var homepage: String?
  public var license: String?
  public var pushedAt: String?
  public init() {}
}

/// Folder structure summary captured by the folder extractor.
public struct FolderMetadata: Codable, Sendable, Equatable {
  public var fileCount: Double = 0
  public var dirCount: Double = 0
  public var totalBytes: Double = 0
  public var truncated: Bool = false
  public var extensions: [String: Double] = [:]
  public var sampledFiles: [String]?
  public var tree: String?
  public init() {}
}

/// Source reference stored on generated notes (`metadata.sources`).
public struct NoteSource: Codable, Sendable, Equatable {
  public enum Role: String, Codable, Sendable { case primary, supporting }
  public var itemId: String
  public var role: Role
  public var why: String
  public init(itemId: String, role: Role, why: String) {
    self.itemId = itemId
    self.role = role
    self.why = why
  }
}

/// `items.metadata` JSON. Known keys are typed; extractors may add more — the dynamic remainder
/// stays in `extra` and re-encodes alongside the known keys.
public struct ItemMetadata: Codable, Sendable, Equatable {
  public var og: OpenGraphMetadata?
  public var favicon: String?
  public var siteName: String?
  public var description: String?
  public var repo: RepoMetadata?
  public var folder: FolderMetadata?
  /// Unstructured extractor output (exif, headings, oEmbed payloads, page-type guesses...).
  public var exif: [String: JSONValue]?
  public var headings: [String]?
  public var sources: [NoteSource]?
  /// Original URL an image/file was dragged from (browser drops).
  public var sourceUrl: String?
  /// Filename at capture time (managed copies may be renamed for safety).
  public var originalName: String?
  /// Extension-based hint when mime sniffing was inconclusive.
  public var `extension`: String?
  public var extra: [String: JSONValue] = [:]
  public init() {}
}

/// Full `items` row in camelCase with JSON columns parsed.
public struct Item: Codable, Sendable, Equatable {
  public init(
    id: String = "",
    type: ItemType = .text,
    subtype: ItemSubtype? = nil,
    kind: Kind? = nil,
    title: String = "",
    originalPath: String? = nil,
    managedPath: String? = nil,
    url: String? = nil,
    canonicalUrl: String? = nil,
    domain: String? = nil,
    mimeType: String? = nil,
    size: Double? = nil,
    contentHash: String? = nil,
    width: Double? = nil,
    height: Double? = nil,
    durationMs: Double? = nil,
    pageCount: Double? = nil,
    createdAt: String = "",
    capturedAt: String = "",
    modifiedAt: String = "",
    lastKeptAt: String = "",
    captureBatchId: String? = nil,
    processingStatus: ProcessingStatus = .captured,
    processingError: String? = nil,
    understanding: String? = nil,
    whyUseful: String? = nil,
    topics: [String] = [],
    entities: [String] = [],
    visionText: String? = nil,
    retrievalHints: [String] = [],
    aiConfidence: Double? = nil,
    metadata: ItemMetadata = ItemMetadata(),
    extractedText: String? = nil,
    excerpt: String? = nil,
    thumbnailPath: String? = nil,
    snapshotPath: String? = nil,
    faviconPath: String? = nil,
    dominantColor: String? = nil,
    mediaVersion: Double = 1,
    parentItemId: String? = nil,
    userOverrides: UserOverrides = UserOverrides(),
    isMissing: Bool = false,
    missingCheckedAt: String? = nil,
    deletedAt: String? = nil
  ) {
    self.id = id
    self.type = type
    self.subtype = subtype
    self.kind = kind
    self.title = title
    self.originalPath = originalPath
    self.managedPath = managedPath
    self.url = url
    self.canonicalUrl = canonicalUrl
    self.domain = domain
    self.mimeType = mimeType
    self.size = size
    self.contentHash = contentHash
    self.width = width
    self.height = height
    self.durationMs = durationMs
    self.pageCount = pageCount
    self.createdAt = createdAt
    self.capturedAt = capturedAt
    self.modifiedAt = modifiedAt
    self.lastKeptAt = lastKeptAt
    self.captureBatchId = captureBatchId
    self.processingStatus = processingStatus
    self.processingError = processingError
    self.understanding = understanding
    self.whyUseful = whyUseful
    self.topics = topics
    self.entities = entities
    self.visionText = visionText
    self.retrievalHints = retrievalHints
    self.aiConfidence = aiConfidence
    self.metadata = metadata
    self.extractedText = extractedText
    self.excerpt = excerpt
    self.thumbnailPath = thumbnailPath
    self.snapshotPath = snapshotPath
    self.faviconPath = faviconPath
    self.dominantColor = dominantColor
    self.mediaVersion = mediaVersion
    self.parentItemId = parentItemId
    self.userOverrides = userOverrides
    self.isMissing = isMissing
    self.missingCheckedAt = missingCheckedAt
    self.deletedAt = deletedAt
  }


  public var id: String
  public var type: ItemType
  public var subtype: ItemSubtype?
  /// `Understanding.kind`; closed vocabulary from `kinds.ts`, queryable.
  public var kind: Kind?
  public var title: String
  /// Absolute path of the referenced original (import mode `reference`, or the source of a copy).
  public var originalPath: String?
  /// Path of the managed copy, relative to `<userData>/objects/`.
  public var managedPath: String?
  public var url: String?
  public var canonicalUrl: String?
  public var domain: String?
  public var mimeType: String?
  /// Size in bytes.
  public var size: Double?
  /// sha256 hex of the original bytes.
  public var contentHash: String?
  public var width: Double?
  public var height: Double?
  public var durationMs: Double?
  public var pageCount: Double?
  public var createdAt: String
  public var capturedAt: String
  public var modifiedAt: String
  /// Bumped when the same object is captured again (duplicate detection).
  public var lastKeptAt: String
  /// Items dropped together share a batch; drives `organize_batch`.
  public var captureBatchId: String?
  public var processingStatus: ProcessingStatus
  public var processingError: String?
  public var understanding: String?
  public var whyUseful: String?
  public var topics: [String]
  public var entities: [String]
  /// visualDescription + visibleText from vision, joined.
  public var visionText: String?
  public var retrievalHints: [String]
  public var aiConfidence: Double?
  public var metadata: ItemMetadata
  /// Capped at `LIMITS.maxExtractedChars`.
  public var extractedText: String?
  /// ≤ `LIMITS.excerptChars`, shown on text cards.
  public var excerpt: String?
  /// Relative to `<userData>/thumbs/`.
  public var thumbnailPath: String?
  /// Relative to `<userData>/snapshots/`.
  public var snapshotPath: String?
  /// Relative to `<userData>/objects/`.
  public var faviconPath: String?
  /// CSS hex colour used to fill the card while media loads.
  public var dominantColor: String?
  /// Bumps whenever thumbnail/snapshot regenerate (media URL cache busting).
  public var mediaVersion: Double
  public var parentItemId: String?
  public var userOverrides: UserOverrides
  public var isMissing: Bool
  public var missingCheckedAt: String?
  public var deletedAt: String?
}

/// Small preview facts for GitHub repo cards.
public struct ItemCardFacts: Codable, Sendable, Equatable {
  public var language: String?
  public var stars: Double?
  public var description: String?
  public var owner: String?
  public init() {}
}

/// Card payload for grids, lists and search results. All `*Url` fields are `ka-media://` URLs
/// built only in the library layer (see `Media.swift`).
public struct ItemSummary: Codable, Sendable, Equatable {
  public init(
    id: String = "",
    type: ItemType = .text,
    subtype: ItemSubtype? = nil,
    kind: Kind? = nil,
    title: String = "",
    domain: String? = nil,
    url: String? = nil,
    thumbnailUrl: String? = nil,
    snapshotUrl: String? = nil,
    faviconUrl: String? = nil,
    dominantColor: String? = nil,
    width: Double? = nil,
    height: Double? = nil,
    size: Double? = nil,
    mimeType: String? = nil,
    durationMs: Double? = nil,
    pageCount: Double? = nil,
    excerpt: String? = nil,
    capturedAt: String = "",
    createdAt: String = "",
    processingStatus: ProcessingStatus = .captured,
    processingError: String? = nil,
    understanding: String? = nil,
    collectionIds: [String] = [],
    childCount: Double = 0,
    childThumbnailUrls: [String] = [],
    card: ItemCardFacts? = nil,
    isMissing: Bool = false,
    parentItemId: String? = nil
  ) {
    self.id = id
    self.type = type
    self.subtype = subtype
    self.kind = kind
    self.title = title
    self.domain = domain
    self.url = url
    self.thumbnailUrl = thumbnailUrl
    self.snapshotUrl = snapshotUrl
    self.faviconUrl = faviconUrl
    self.dominantColor = dominantColor
    self.width = width
    self.height = height
    self.size = size
    self.mimeType = mimeType
    self.durationMs = durationMs
    self.pageCount = pageCount
    self.excerpt = excerpt
    self.capturedAt = capturedAt
    self.createdAt = createdAt
    self.processingStatus = processingStatus
    self.processingError = processingError
    self.understanding = understanding
    self.collectionIds = collectionIds
    self.childCount = childCount
    self.childThumbnailUrls = childThumbnailUrls
    self.card = card
    self.isMissing = isMissing
    self.parentItemId = parentItemId
  }

  public var id: String
  public var type: ItemType
  public var subtype: ItemSubtype?
  public var kind: Kind?
  public var title: String
  public var domain: String?
  public var url: String?
  public var thumbnailUrl: String?
  public var snapshotUrl: String?
  public var faviconUrl: String?
  public var dominantColor: String?
  public var width: Double?
  public var height: Double?
  public var size: Double?
  public var mimeType: String?
  public var durationMs: Double?
  public var pageCount: Double?
  public var excerpt: String?
  public var capturedAt: String
  public var createdAt: String
  public var processingStatus: ProcessingStatus
  public var processingError: String?
  /// Truncated to `LIMITS.summaryUnderstandingMaxChars`.
  public var understanding: String?
  public var collectionIds: [String]
  /// Folders: direct child items, or the manifest file count when the folder is a single item; 0 otherwise.
  public var childCount: Double
  /// Up to 4 child thumbnail URLs for the folder collage.
  public var childThumbnailUrls: [String]
  public var card: ItemCardFacts?
  public var isMissing: Bool
  public var parentItemId: String?
}

/// A relationship as seen from one item, with the other side resolved.
public struct ItemDetailRelationship: Codable, Sendable, Equatable {
  public var relationship: Relationship
  /// `.out` when this item is the source, `.in` when it is the target.
  public var direction: RelationshipDirection
  /// Human label for this direction (e.g. "inspired by" vs "inspired").
  public var label: String
  public var other: ItemSummary
}

/// Collection membership of one item, including why it was added.
public struct ItemDetailCollection: Codable, Sendable, Equatable {
  public var collection: Collection
  public var confidence: Double?
  public var reason: String?
  public var addedBy: MembershipActor
  public var agentRunId: String?
  public var addedAt: String
}

/// `items:get` payload.
public struct ItemDetail: Codable, Sendable, Equatable {
  public var item: Item
  /// Card payload with the resolved media URLs.
  public var summary: ItemSummary
  /// `ka-media://` URL of the managed copy for the hero, null for referenced originals.
  public var originalUrl: String?
  public var relationships: [ItemDetailRelationship]
  public var collections: [ItemDetailCollection]
  public var latestRuns: [AgentRunSummary]
  /// Direct children for folders.
  public var children: [ItemSummary]?
}

/// Sidebar views for `items:list`.
public enum ItemsView: String, Codable, Sendable, CaseIterable {
  case library, links, files, trash, collection
}

/// Sort keys for `items:list`.
public enum ItemsSort: String, Codable, Sendable, CaseIterable {
  case captured, created, title
}

/// How a collection was created.
public enum CollectionCreator: String, Codable, Sendable { case user, agent }

/// Who added an item to a collection.
public enum MembershipActor: String, Codable, Sendable { case user, agent }

/// Filters applied to search and agent retrieval tools (dates on `captured_at`).
public struct SearchFilters: Codable, Sendable, Equatable {
  public var types: [ItemType]?
  public var subtypes: [ItemSubtype]?
  public var kinds: [Kind]?
  public var domains: [String]?
  /// ISO timestamp, inclusive lower bound on `captured_at`.
  public var since: String?
  /// ISO timestamp, exclusive upper bound on `captured_at`.
  public var until: String?
  /// When true, type/kind cues are hard filters instead of soft boosts.
  public var strict: Bool?
  public init() {}
}

/// `collections` row.
public struct Collection: Codable, Sendable, Equatable {
  public init(
    id: String = "",
    name: String = "",
    nameKey: String = "",
    description: String? = nil,
    createdBy: CollectionCreator = .user,
    color: String? = nil,
    pinned: Bool = false,
    createdAt: String = "",
    updatedAt: String = ""
  ) {
    self.id = id
    self.name = name
    self.nameKey = nameKey
    self.description = description
    self.createdBy = createdBy
    self.color = color
    self.pinned = pinned
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var id: String
  public var name: String
  /// `normalizeName(name)`; unique.
  public var nameKey: String
  /// Free-form text the agent reads to decide whether new items belong.
  public var description: String?
  public var createdBy: CollectionCreator
  public var color: String?
  public var pinned: Bool
  public var createdAt: String
  public var updatedAt: String
}

/// Sidebar / grid payload for a collection.
public struct CollectionSummary: Codable, Sendable, Equatable {
  public init(
    collection: Collection = Collection(),
    count: Int = 0,
    coverThumbnailUrls: [String] = []
  ) {
    self.collection = collection
    self.count = count
    self.coverThumbnailUrls = coverThumbnailUrls
  }

  public var collection: Collection
  public var count: Int
  /// Up to 4 `ka-media://` thumbnail URLs for the cover collage.
  public var coverThumbnailUrls: [String]
}

/// `collection_items` row.
public struct CollectionItem: Codable, Sendable, Equatable {
  public init(
    collectionId: String = "",
    itemId: String = "",
    confidence: Double? = nil,
    reason: String? = nil,
    addedBy: MembershipActor = .user,
    agentRunId: String? = nil,
    addedAt: String = ""
  ) {
    self.collectionId = collectionId
    self.itemId = itemId
    self.confidence = confidence
    self.reason = reason
    self.addedBy = addedBy
    self.agentRunId = agentRunId
    self.addedAt = addedAt
  }

  public var collectionId: String
  public var itemId: String
  public var confidence: Double?
  public var reason: String?
  public var addedBy: MembershipActor
  public var agentRunId: String?
  public var addedAt: String
}

/// Direction of a relationship relative to a given item.
public enum RelationshipDirection: String, Codable, Sendable { case out, `in` }

/// Who created a relationship.
public enum RelationshipCreator: String, Codable, Sendable { case user, agent, system }

/// Optional quote backing a relationship, verified against the target's text.
public struct RelationshipEvidence: Codable, Sendable, Equatable {
  public init(
    itemId: String = "",
    quote: String = ""
  ) {
    self.itemId = itemId
    self.quote = quote
  }

  public var itemId: String
  public var quote: String
}

/// `relationships` row. Symmetric types are stored with `sourceItemId < targetItemId`.
public struct Relationship: Codable, Sendable, Equatable {
  public init(
    id: String = "",
    sourceItemId: String = "",
    targetItemId: String = "",
    type: RelationshipType = .relatedTo,
    description: String? = nil,
    confidence: Double? = nil,
    evidence: RelationshipEvidence? = nil,
    createdBy: RelationshipCreator = .user,
    agentRunId: String? = nil,
    createdAt: String = ""
  ) {
    self.id = id
    self.sourceItemId = sourceItemId
    self.targetItemId = targetItemId
    self.type = type
    self.description = description
    self.confidence = confidence
    self.evidence = evidence
    self.createdBy = createdBy
    self.agentRunId = agentRunId
    self.createdAt = createdAt
  }

  public var id: String
  public var sourceItemId: String
  public var targetItemId: String
  public var type: RelationshipType
  public var description: String?
  public var confidence: Double?
  public var evidence: RelationshipEvidence?
  public var createdBy: RelationshipCreator
  public var agentRunId: String?
  public var createdAt: String
}

/// Chunk 0 is the memory document (`.summary`); chunks ≥ 1 are body text (`.body`).
public enum EmbeddingRole: String, Codable, Sendable { case summary, body }

/// `embeddings` row without the vector BLOB.
public struct EmbeddingMeta: Codable, Sendable, Equatable {
  public init(
    itemId: String = "",
    chunkIndex: Int = 0,
    role: EmbeddingRole = .summary,
    content: String = "",
    model: String = "",
    dims: Int = 0
  ) {
    self.itemId = itemId
    self.chunkIndex = chunkIndex
    self.role = role
    self.content = content
    self.model = model
    self.dims = dims
  }

  public var itemId: String
  public var chunkIndex: Int
  public var role: EmbeddingRole
  public var content: String
  public var model: String
  public var dims: Int
}

/// Scheduler lanes with fixed concurrency (`Limits.lanes`).
public enum Lane: String, Codable, Sendable, CaseIterable { case io, embed, ai }

/// `jobs.status`.
public enum JobStatus: String, Codable, Sendable, CaseIterable {
  case queued, running, done, failed, cancelled
}

/// `jobs` row.
public struct Job: Codable, Sendable, Equatable {
  public init(
    id: String = "",
    itemId: String? = nil,
    batchId: String? = nil,
    stage: Stage = .extract,
    lane: Lane = .io,
    priority: Double = 0,
    status: JobStatus = .queued,
    attempts: Int = 0,
    runAfter: String? = nil,
    lastError: String? = nil,
    createdAt: String = "",
    updatedAt: String = ""
  ) {
    self.id = id
    self.itemId = itemId
    self.batchId = batchId
    self.stage = stage
    self.lane = lane
    self.priority = priority
    self.status = status
    self.attempts = attempts
    self.runAfter = runAfter
    self.lastError = lastError
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var id: String
  public var itemId: String?
  public var batchId: String?
  public var stage: Stage
  public var lane: Lane
  public var priority: Double
  public var status: JobStatus
  public var attempts: Int
  /// Do not claim before this ISO timestamp (backoff / batch gate).
  public var runAfter: String?
  public var lastError: String?
  public var createdAt: String
  public var updatedAt: String
}

/// Per-job progress pushed by the scheduler (`jobs:progress`) and listed by `jobs:status`.
public struct JobProgress: Codable, Sendable, Equatable {
  public init(
    itemId: String? = nil,
    batchId: String? = nil,
    processingStatus: ProcessingStatus? = nil,
    stage: Stage = .extract,
    jobStatus: JobStatus = .queued,
    attempts: Int = 0,
    message: String? = nil
  ) {
    self.itemId = itemId
    self.batchId = batchId
    self.processingStatus = processingStatus
    self.stage = stage
    self.jobStatus = jobStatus
    self.attempts = attempts
    self.message = message
  }

  /// Nil for batch-level jobs (`organize_batch`, `consolidate`).
  public var itemId: String?
  public var batchId: String?
  /// Item status after this transition; nil for batch-level jobs.
  public var processingStatus: ProcessingStatus?
  public var stage: Stage
  public var jobStatus: JobStatus
  public var attempts: Int
  public var message: String?
}

/// Structured output of the `understand` task.
public struct Understanding: Codable, Sendable, Equatable {
  public var kind: Kind
  public var title: String
  /// One or two specific sentences: what this is and what it contains.
  public var summary: String
  /// Why someone would keep this.
  public var whyUseful: String
  public var topics: [String]
  public var entities: [String]
  /// Vision: what the image/page looks like.
  public var visualDescription: String?
  /// Vision: legible text in the image.
  public var visibleText: String?
  /// 3-6 phrases a person might type months later to find this.
  public var retrievalHints: [String]
  /// 0..1
  public var confidence: Double
}

/// Agent task kinds (`agent_runs.task`).
public enum AgentTask: String, Codable, Sendable, CaseIterable {
  case understand, organize, organizeBatch = "organize_batch", consolidate, folder, command
}

/// `agent_runs.status`.
public enum AgentRunStatus: String, Codable, Sendable, CaseIterable {
  case running, succeeded, failed, cancelled
}

/// Coarse classification of a tool step for the activity view.
public enum AgentStepKind: String, Codable, Sendable {
  case search, read, inspect, compare, write, finish
}

/// One tool step of a run. `label` is product voice, never model reasoning.
public struct AgentStep: Codable, Sendable, Equatable {
  public init(
    n: Int = 0,
    tool: String = "",
    kind: AgentStepKind = .finish,
    label: String = "",
    itemIds: [String]? = nil,
    status: Status = .ok,
    rejectReason: String? = nil,
    durationMs: Double = 0
  ) {
    self.n = n
    self.tool = tool
    self.kind = kind
    self.label = label
    self.itemIds = itemIds
    self.status = status
    self.rejectReason = rejectReason
    self.durationMs = durationMs
  }

  public var n: Int
  public var tool: String
  public var kind: AgentStepKind
  public var label: String
  public var itemIds: [String]?
  public var status: AgentStep.Status
  public var rejectReason: String?
  public var durationMs: Double

  public enum Status: String, Codable, Sendable { case ok, rejected }
}

/// Multi-item templates for `agent:command`.
public enum CommandTemplate: String, Codable, Sendable {
  case compare, common, summarize, extract, custom
}

/// A cited source in an agent answer or note.
public struct AgentSource: Codable, Sendable, Equatable {
  public enum Role: String, Codable, Sendable { case primary, supporting }
  public var itemId: String
  public var role: Role
  public var why: String
}

/// Memory cues the agent extracted from a question (shown in the evidence header).
public struct AgentCues: Codable, Sendable, Equatable {
  public var topics: [String]
  public var types: [ItemType]
  public var timeframe: Timeframe?

  public struct Timeframe: Codable, Sendable, Equatable {
    public var since: String?
    public var until: String?
    public var label: String?
  }
}

/// Token usage of a run, summed over all model calls.
public struct AgentUsage: Codable, Sendable, Equatable {
  public init(
    promptTokens: Int = 0,
    completionTokens: Int = 0,
    calls: Int = 0,
    latencyMs: Double = 0
  ) {
    self.promptTokens = promptTokens
    self.completionTokens = completionTokens
    self.calls = calls
    self.latencyMs = latencyMs
  }

  public var promptTokens: Int
  public var completionTokens: Int
  public var calls: Int
  public var latencyMs: Double
}

/// Kinds of change the agent may stage through `propose_actions`.
public enum AgentProposalKind: String, Codable, Sendable {
  case addToCollection = "add_to_collection"
  case createCollection = "create_collection"
  case relate, tag, rename, trash
}

/// One staged change of a command run: everything needed to apply it later plus a product-voice
/// `label`. Persisted (unapplied ones) inside `agent_runs.result.proposals`.
public struct AgentProposal: Codable, Sendable, Equatable {
  public var label: String
  public var confidence: Double
  public var kind: AgentProposalKind
  public var collectionId: String?
  public var itemId: String?
  public var reason: String?
  public var name: String?
  public var description: String?
  public var itemIds: [String]?
  public var sourceId: String?
  public var targetId: String?
  public var type: RelationshipType?
  public var topics: [String]?
  public var title: String?
}

/// Result of a run, discriminated by task. Persisted as `agent_runs.result` JSON.
public struct AgentResult: Codable, Sendable, Equatable {
  public var task: AgentTask
  // command
  public var kind: String?
  public var answer: String?
  public var noteId: String?
  public var sources: [AgentSource]?
  public var cues: AgentCues?
  public var confidence: Double?
  /// Staged, not yet applied (`agent:applyProposals`).
  public var proposals: [AgentProposal]?
  /// Changes an item-action run applied on its own (undo with `agent:undoRun`).
  public var appliedCount: Int?
  // understand / organize / organize_batch / folder
  public var itemId: String?
  public var understanding: Understanding?
  public var skippedFields: [UserOverridableField]?
  public var batchId: String?
  public var itemIds: [String]?
  public var relationshipIds: [String]?
  public var collectionIds: [String]?
  public var renamedCollectionIds: [String]?
  public var collectionId: String?
  public var summary: String?
}

/// List payload for runs (item detail "How this was organized"): steps included, result/usage not.
public struct AgentRunSummary: Codable, Sendable, Equatable {
  public init(
    id: String = "",
    itemId: String? = nil,
    batchId: String? = nil,
    task: AgentTask = .command,
    status: AgentRunStatus = .running,
    model: String = "",
    startedAt: String = "",
    completedAt: String? = nil,
    stepCount: Int = 0,
    error: String? = nil,
    steps: [AgentStep] = [],
    undoable: Bool = false
  ) {
    self.id = id
    self.itemId = itemId
    self.batchId = batchId
    self.task = task
    self.status = status
    self.model = model
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.stepCount = stepCount
    self.error = error
    self.steps = steps
    self.undoable = undoable
  }

  public var id: String
  public var itemId: String?
  public var batchId: String?
  public var task: AgentTask
  public var status: AgentRunStatus
  public var model: String
  public var startedAt: String
  public var completedAt: String?
  public var stepCount: Int
  public var error: String?
  /// Product-voice steps (never model reasoning).
  public var steps: [AgentStep]
  /// True while the run has audited changes that have not been undone (`agent:undoRun`).
  public var undoable: Bool
}

/// `agent:run` payload: full transcript without model reasoning.
public struct AgentRunDetail: Codable, Sendable, Equatable {
  public init(
    summary: AgentRunSummary = AgentRunSummary(),
    usage: AgentUsage? = nil,
    result: AgentResult? = nil
  ) {
    self.summary = summary
    self.usage = usage
    self.result = result
  }

  public var summary: AgentRunSummary
  public var usage: AgentUsage?
  public var result: AgentResult?
}

/// Why a hit ranked where it did (drives evidence headers and tests).
public struct SearchEvidence: Codable, Sendable, Equatable {
  /// Normalized bm25 (0..1, higher is better).
  public var bm25Norm: Double?
  public var cosine: Double?
  /// FTS columns that matched (e.g. `title`, `retrieval_hints`).
  public var matchedFields: [String]
}

/// One retrieval hit; also the candidate shape handed to the agent.
public struct SearchHit: Codable, Sendable, Equatable {
  public var id: String
  public var title: String
  public var type: ItemType
  public var subtype: ItemSubtype?
  public var kind: Kind?
  public var domain: String?
  public var capturedAt: String
  /// `relativeTime(capturedAt)` computed in the library layer.
  public var capturedAgo: String
  /// Truncated to 140 chars.
  public var understanding: String?
  public var snippet: String?
  public var thumbnailUrl: String?
  public var evidence: SearchEvidence
  public var score: Double
}

/// Same shape as `SearchHit`; the name marks agent-side candidate lists.
public typealias Candidate = SearchHit

/// Import mode for files: copy into `objects/` or reference the original path.
public enum CaptureMode: String, Codable, Sendable { case copy, reference }

/// Where a drop came from.
public enum CaptureDropSource: String, Codable, Sendable { case library, shelf }

/// Every capture entry point, for audit and metadata.
public enum CaptureSource: String, Codable, Sendable {
  case library, shelf, paste, dialog, shortcut, api
}

/// Outcome for one captured object.
public struct CaptureResultItem: Codable, Sendable, Equatable {
  public enum Status: String, Codable, Sendable { case created, duplicate }
  public var id: String
  public var status: Status
  /// Set when `status == .duplicate`: the item that already holds this object.
  public var existingId: String?
  public var title: String
}

public struct CaptureResult: Codable, Sendable, Equatable {
  public var items: [CaptureResultItem]
  public var batchId: String
}

/// Stable identifier of an OpenAI-compatible provider.
public enum AiProviderId: String, Codable, Sendable, CaseIterable { case gmi, openrouter }

/// Which AI provider drives the agent.
public enum AiMode: String, Codable, Sendable { case gmi, openrouter, mock, off }

/// Runtime AI connectivity as shown in the footer.
public enum AiStatus: String, Codable, Sendable { case off, connected, offline, unconfigured }

/// User theme preference.
public enum Theme: String, Codable, Sendable, CaseIterable { case system, light, dark }

/// Effective theme after resolving `system`.
public enum ResolvedTheme: String, Codable, Sendable { case light, dark }

/// Which embedding backend is active.
public enum EmbeddingProviderId: String, Codable, Sendable { case local, localHash = "local-hash", none }

/// `settings:get` payload. Never contains the plain API key.
public struct Settings: Codable, Sendable, Equatable {
  public var aiMode: AiMode
  /// The OpenAI-compatible provider whose model/key/baseUrl are exposed by the flat fields.
  public var provider: AiProviderId
  public var model: String
  public var baseUrl: String
  public var hasApiKey: Bool
  /// e.g. `sk-…9f3a`; nil when no key is stored.
  public var apiKeyMasked: String?
  public var importMode: CaptureMode
  public var theme: Theme
  /// Absolute path of the library (`userData`).
  public var libraryPath: String
  public var embeddings: Embeddings

  public struct Embeddings: Codable, Sendable, Equatable {
    public var provider: EmbeddingProviderId
    public var modelPresent: Bool
    public var dims: Int
  }
}

/// `settings:update` payload; `apiKey` is plain text and is encrypted at rest by the library layer.
public struct SettingsPatch: Codable, Sendable, Equatable {
  public var apiKey: String?
  public var clearApiKey: Bool?
  /// On/off switch; the live mode is `provider` when on.
  public var ai: String?
  /// Selects whose profile and key the other fields apply to; defaults to the current selection.
  public var provider: AiProviderId?
  public var model: String?
  public var baseUrl: String?
  public var importMode: CaptureMode?
  public var theme: Theme?
  public init() {}
}

/// `system:updateStatus` payload and `update:status` event.
public struct UpdateStatus: Codable, Sendable, Equatable {
  /// Version of the running app.
  public var version: String
  /// `unavailable`: not a packaged build, so there is nothing to update.
  public var state: State
  /// Version on the release feed (`downloading`, `ready`).
  public var latest: String?
  /// 0..100 while `downloading`.
  public var percent: Double?
  /// User-safe message (`error`).
  public var error: String?

  public enum State: String, Codable, Sendable {
    case unavailable, idle, checking, downloading, ready, current, error
  }
}

/// `system:stats` payload.
public struct SystemStats: Codable, Sendable, Equatable {
  public var items: Int
  public var connections: Int
  public var collections: Int
  /// Items currently not READY/PARTIAL.
  public var processing: Int
  public var aiStatus: AiStatus
}

/// Which native context menu to show.
public enum ContextMenuKind: String, Codable, Sendable { case item, items, collection, background }

/// Who performed an audited mutation.
public enum AuditActor: String, Codable, Sendable { case user, agent, system }

/// `audit_log` row.
public struct AuditEntry: Codable, Sendable, Equatable {
  public init(
    id: String = "",
    actor: AuditActor = .user,
    action: String = "",
    entity: String = "",
    entityId: String = "",
    before: JSONValue? = nil,
    after: JSONValue? = nil,
    agentRunId: String? = nil,
    createdAt: String = "",
    undoneAt: String? = nil
  ) {
    self.id = id
    self.actor = actor
    self.action = action
    self.entity = entity
    self.entityId = entityId
    self.before = before
    self.after = after
    self.agentRunId = agentRunId
    self.createdAt = createdAt
    self.undoneAt = undoneAt
  }

  public var id: String
  public var actor: AuditActor
  public var action: String
  public var entity: String
  public var entityId: String
  public var before: JSONValue?
  public var after: JSONValue?
  public var agentRunId: String?
  public var createdAt: String
  public var undoneAt: String?
}

/// `suppressions.kind`: facts the agent must never re-create after a user removed them.
public enum SuppressionKind: String, Codable, Sendable { case relationship, collectionMember = "collection_member" }

/// Loose JSON value for open-ended columns (`audit_log.before/after`, `ItemMetadata.extra`).
public enum JSONValue: Codable, Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null; return }
    if let v = try? c.decode(Bool.self) { self = .bool(v); return }
    if let v = try? c.decode(Double.self) { self = .number(v); return }
    if let v = try? c.decode(String.self) { self = .string(v); return }
    if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
    self = .object(try c.decode([String: JSONValue].self))
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .null: try c.encodeNil()
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
}

