/// Closed vocabularies: `Understanding.kind` values and the relationship graph's edge types
/// (port of `electron/src/shared/kinds.ts`).

/// What a kept object *is*, as decided by the understand task. Queryable (`items.kind`).
/// Case order matches `KINDS` in the TS source and the parity fixture.
public enum Kind: String, Codable, Sendable, CaseIterable {
  case macosApp = "macos_app"
  case cliTool = "cli_tool"
  case library
  case saasProduct = "saas_product"
  case article, paper, docs
  case designReference = "design_reference"
  case screenshot, photo, receipt, video, dataset, note
  case socialPost = "social_post"
  case other
}

/// `KINDS` — the ordered wire values.
public let KINDS: [String] = Kind.allCases.map(\.rawValue)

public func isKind(_ value: String) -> Bool { Kind(rawValue: value) != nil }

/// Human labels for kinds (sentence case, product voice). `KIND_LABEL` in TS.
public let KIND_LABEL: [Kind: String] = [
  .macosApp: "macOS app",
  .cliTool: "Command-line tool",
  .library: "Library",
  .saasProduct: "Product",
  .article: "Article",
  .paper: "Paper",
  .docs: "Documentation",
  .designReference: "Design reference",
  .screenshot: "Screenshot",
  .photo: "Photo",
  .receipt: "Receipt",
  .video: "Video",
  .dataset: "Dataset",
  .note: "Note",
  .socialPost: "Social post",
  .other: "Other"
]

/// Labels and symmetry for one relationship type.
public struct RelationshipTypeInfo: Sendable, Equatable {
  /// Symmetric edges are stored once with `sourceItemId < targetItemId`.
  public let symmetric: Bool
  /// Label read from the source ("A *inspired by* B").
  public let label: String
  /// Label read from the target ("B *inspired* A"). Equals `label` for symmetric types.
  public let inverseLabel: String
}

/// Closed relationship vocabulary (`RelationshipType` in TS). Case order matches the
/// `RELATIONSHIP_TYPES` object key order and `RELATIONSHIP_TYPE_IDS`.
public enum RelationshipType: String, Codable, Sendable, CaseIterable {
  case relatedTo = "related_to"
  case inspiredBy = "inspired_by"
  case sameProject = "same_project"
  case references
  case alternativeTo = "alternative_to"
  case continuationOf = "continuation_of"
  case contradicts
  case duplicateOf = "duplicate_of"
  case createdFrom = "created_from"
  case belongsTo = "belongs_to"
}

/// Every relationship type with its labels and symmetry.
public let RELATIONSHIP_TYPES: [RelationshipType: RelationshipTypeInfo] = [
  .relatedTo: .init(symmetric: true, label: "related to", inverseLabel: "related to"),
  .inspiredBy: .init(symmetric: false, label: "inspired by", inverseLabel: "inspired"),
  .sameProject: .init(symmetric: true, label: "same project", inverseLabel: "same project"),
  .references: .init(symmetric: false, label: "references", inverseLabel: "referenced by"),
  .alternativeTo: .init(symmetric: true, label: "alternative to", inverseLabel: "alternative to"),
  .continuationOf: .init(symmetric: false, label: "continuation of", inverseLabel: "continued by"),
  .contradicts: .init(symmetric: true, label: "contradicts", inverseLabel: "contradicts"),
  .duplicateOf: .init(symmetric: true, label: "duplicate of", inverseLabel: "duplicate of"),
  .createdFrom: .init(symmetric: false, label: "created from", inverseLabel: "source of"),
  .belongsTo: .init(symmetric: false, label: "belongs to", inverseLabel: "contains")
]

/// Ordered list of relationship type ids (for validation and menus).
public let RELATIONSHIP_TYPE_IDS: [RelationshipType] = RelationshipType.allCases

public func isRelationshipType(_ value: String) -> Bool { RelationshipType(rawValue: value) != nil }

/// True for edge types whose meaning does not depend on direction.
public func isSymmetric(_ type: RelationshipType) -> Bool {
  RELATIONSHIP_TYPES[type]!.symmetric
}

/// Label for a relationship as seen from one side (`.out` = this item is the source).
public func relationshipLabel(_ type: RelationshipType, _ direction: RelationshipDirection) -> String {
  let info = RELATIONSHIP_TYPES[type]!
  return direction == .out ? info.label : info.inverseLabel
}

/// Canonical `[source, target]` order for storage: symmetric types are sorted so `source < target`
/// (plain string comparison); directed types keep the given order.
public func normalizePair(_ a: String, _ b: String, _ type: RelationshipType) -> (String, String) {
  if isSymmetric(type), b < a { return (b, a) }
  return (a, b)
}

/// Suppression key for a relationship between two items, regardless of type or direction.
public func relationshipSuppressionKey(_ a: String, _ b: String) -> String {
  a < b ? "\(a):\(b)" : "\(b):\(a)"
}
