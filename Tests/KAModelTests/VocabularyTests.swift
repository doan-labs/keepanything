import Testing
@testable import KAModel

/// Port of `electron/tests/unit/vocabulary.test.ts`.
@Suite struct VocabularyTests {
  @Test func labelsEveryKind() {
    #expect(KINDS.count == 16)
    for kind in Kind.allCases { #expect(!(KIND_LABEL[kind] ?? "").isEmpty) }
  }

  @Test func declaresSymmetryAndLabelsForEveryRelationshipType() {
    #expect(RELATIONSHIP_TYPE_IDS.count == 10)
    let symmetric = RELATIONSHIP_TYPE_IDS.filter { isSymmetric($0) }.map(\.rawValue).sorted()
    #expect(symmetric == ["alternative_to", "contradicts", "duplicate_of", "related_to", "same_project"])
    for t in RELATIONSHIP_TYPE_IDS where isSymmetric(t) {
      #expect(RELATIONSHIP_TYPES[t]!.label == RELATIONSHIP_TYPES[t]!.inverseLabel)
    }
    #expect(relationshipLabel(.inspiredBy, .out) == "inspired by")
    #expect(relationshipLabel(.inspiredBy, .in) == "inspired")
    #expect(relationshipLabel(.createdFrom, .in) == "source of")
    #expect(relationshipLabel(.belongsTo, .in) == "contains")
  }

  @Test func normalizesSymmetricPairsKeepsDirected() {
    #expect(normalizePair("b", "a", .relatedTo) == ("a", "b"))
    #expect(normalizePair("a", "b", .relatedTo) == ("a", "b"))
    #expect(normalizePair("b", "a", .inspiredBy) == ("b", "a"))
    #expect(relationshipSuppressionKey("b", "a") == "a:b")
  }

  @Test func keepsTheLaneAndCopyContract() {
    #expect(LIMITS.lanes == .init(io: 2, embed: 1, ai: 1))
    #expect(LIMITS.retryBackoffMs == [30_000, 120_000, 600_000])
    #expect(COPY.foundRelated(4) == "Linked to 4 things.")
    #expect(COPY.foundRelated(1) == "Linked to 1 thing.")
    #expect(COPY.alreadyKept("3 weeks ago") == "Already kept · 3 weeks ago")
    #expect(COPY.noMatches("x") == "Nothing matches \"x\".")
  }
}
