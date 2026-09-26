/// Every repository, keyed by the names used in `StageDeps.repos`.
public struct Repositories: Sendable {
  public let items: ItemRepo
  public let collections: CollectionRepo
  public let relationships: RelationshipRepo
  public let embeddings: EmbeddingRepo
  public let agentRuns: AgentRunRepo
  public let jobs: JobRepo
  public let audit: AuditRepo
  public let suppressions: SuppressionRepo
}

public func createRepositories(_ db: Db) -> Repositories {
  Repositories(
    items: ItemRepo(db: db),
    collections: CollectionRepo(db: db),
    relationships: RelationshipRepo(db: db),
    embeddings: EmbeddingRepo(db: db),
    agentRuns: AgentRunRepo(db: db),
    jobs: JobRepo(db: db),
    audit: AuditRepo(db: db),
    suppressions: SuppressionRepo(db: db)
  )
}
