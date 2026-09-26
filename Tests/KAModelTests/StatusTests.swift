import Testing
@testable import KAModel

/// Port of `electron/tests/unit/status.test.ts` plus the status-table.json parity sweep.
@Suite struct StatusTests {
  private let statuses = ProcessingStatus.allCases
  private let stages = Stage.allCases
  private let outcomes = StageOutcome.allCases
  private let beforeUnderstanding: [ProcessingStatus] = [.captured, .extracting, .extracted, .embedding]

  @Test func listsEveryStatusOnce() {
    #expect(Set(statuses).count == statuses.count)
    #expect(isProcessingStatus("READY"))
    #expect(!isProcessingStatus("ready"))
  }

  @Test func classifiesFailedAndTerminal() {
    for status in statuses {
      #expect(isFailed(status) == (status == .extractionFailed || status == .aiFailed))
      #expect(isTerminal(status) == (status == .ready || status == .partial))
    }
  }

  @Test func mapsFlowStatusesToUserStages() {
    #expect(USER_STAGES.map(\.id) == [.reading, .understanding, .connecting])
    #expect(userStageFor(.extracting)?.id == .reading)
    #expect(userStageFor(.extracted)?.id == .reading)
    #expect(userStageFor(.embedding)?.id == .reading)
    #expect(userStageFor(.understanding)?.id == .understanding)
    #expect(userStageFor(.relating)?.id == .connecting)
    for status in [ProcessingStatus.captured, .ready, .partial, .extractionFailed, .aiFailed, .waitingForAi] {
      #expect(userStageFor(status) == nil)
    }
  }

  @Test func hasCopyForEveryStatusAndStage() {
    for status in statuses { #expect(STATUS_LABEL[status] != nil) }
    for stage in stages { #expect(!(STAGE_LABEL[stage] ?? "").isEmpty) }
    #expect(STATUS_LABEL[.captured] == "Saved.")
    #expect(STATUS_LABEL[.ready] == "")
    #expect(STATUS_LABEL[.partial] == "Kept. Partly understood.")
    #expect(STATUS_LABEL[.extractionFailed] == "Couldn't read this, but it's kept.")
    #expect(STATUS_LABEL[.aiFailed] == "Still figuring this one out.")
    #expect(STATUS_LABEL[.waitingForAi] == "Kept. Not understood yet.")
  }

  @Test func extractTransitions() {
    for status in statuses {
      #expect(next(status, .extract, .ok) == .extracted)
      #expect(next(status, .extract, .partial) == .extracted)
      #expect(next(status, .extract, .failed) == .extractionFailed)
    }
  }

  @Test func passiveStagesNeverChangeUnlessLast() {
    for stage in [Stage.thumbnail, .snapshot, .index] {
      for status in statuses {
        for outcome in outcomes {
          #expect(next(status, stage, outcome) == status)
          #expect(next(status, stage, outcome, ctx: TransitionContext(isLast: false)) == status)
        }
      }
    }
  }

  @Test func passiveStagesSettleWhenLast() {
    for stage in [Stage.thumbnail, .snapshot, .index] {
      for status in statuses {
        let sticky = STICKY_STATUSES.contains(status)
        #expect(next(status, stage, .ok, ctx: TransitionContext(isLast: true)) == (sticky ? .partial : .ready))
        #expect(next(status, stage, .partial, ctx: TransitionContext(isLast: true)) == .partial)
        #expect(next(status, stage, .failed, ctx: TransitionContext(isLast: true)) == .partial)
      }
    }
  }

  @Test func embedMovesPreUnderstandingStatuses() {
    for status in statuses {
      let expected: ProcessingStatus = beforeUnderstanding.contains(status) ? .understanding : status
      #expect(next(status, .embed, .ok) == expected)
      #expect(next(status, .embed, .partial) == expected)
      #expect(next(status, .embed, .failed) == status)
    }
  }

  @Test func understandTransitions() {
    for status in statuses {
      #expect(next(status, .understand, .ok) == (status == .extractionFailed ? .partial : .relating))
      #expect(next(status, .understand, .partial) == .partial)
      #expect(next(status, .understand, .failed) == .aiFailed)
    }
  }

  @Test func relateAndOrganizeBatchTransitions() {
    for stage in [Stage.relate, .organizeBatch] {
      for status in statuses {
        let sticky = STICKY_STATUSES.contains(status)
        #expect(next(status, stage, .ok) == (sticky ? .partial : .ready))
        #expect(next(status, stage, .partial) == .partial)
        #expect(next(status, stage, .failed) == .aiFailed)
      }
    }
  }

  @Test func consolidateNeverChangesStatus() {
    for status in statuses {
      for outcome in outcomes {
        #expect(next(status, .consolidate, outcome) == status)
      }
    }
  }

  @Test func alwaysReturnsAKnownStatus() {
    for status in statuses {
      for stage in stages {
        for outcome in outcomes {
          #expect(statuses.contains(next(status, stage, outcome)))
          #expect(statuses.contains(next(status, stage, outcome, ctx: TransitionContext(isLast: true))))
        }
      }
    }
  }

  /// Simulates the scheduler: apply entry status (if any), then the transition.
  private func run(_ status: ProcessingStatus, _ stage: Stage, _ outcome: StageOutcome, _ isLast: Bool = false) -> ProcessingStatus {
    next(stageEntryStatus(stage, status) ?? status, stage, outcome, ctx: TransitionContext(isLast: isLast))
  }

  @Test func urlFlow() {
    var s = ProcessingStatus.captured
    s = run(s, .extract, .ok); #expect(s == .extracted)
    s = run(s, .snapshot, .ok); #expect(s == .extracted)
    s = run(s, .embed, .ok); #expect(s == .understanding)
    s = run(s, .understand, .ok); #expect(s == .relating)
    s = run(s, .index, .ok); #expect(s == .relating)
    s = run(s, .relate, .ok); #expect(s == .ready)
  }

  @Test func understandMayFinishBeforeEmbed() {
    var s = ProcessingStatus.extracted
    s = run(s, .understand, .ok); #expect(s == .relating)
    s = run(s, .embed, .ok); #expect(s == .relating)
  }

  @Test func extractionFailureEndsPartial() {
    var s = ProcessingStatus.captured
    s = run(s, .extract, .failed); #expect(s == .extractionFailed)
    s = run(s, .embed, .ok); #expect(s == .extractionFailed)
    #expect(stageEntryStatus(.understand, s) == nil)
    s = run(s, .understand, .ok); #expect(s == .partial)
    s = run(s, .index, .ok); #expect(s == .partial)
    #expect(stageEntryStatus(.relate, s) == nil)
    s = run(s, .relate, .ok); #expect(s == .partial)
  }

  @Test func imageFlow() {
    var s = ProcessingStatus.captured
    s = run(s, .thumbnail, .ok); #expect(s == .captured)
    s = run(s, .understand, .ok); #expect(s == .relating)
    s = run(s, .index, .ok)
    s = run(s, .organizeBatch, .ok); #expect(s == .ready)
  }

  @Test func noteFlow() {
    var s = ProcessingStatus.captured
    s = run(s, .embed, .ok)
    s = run(s, .index, .ok, true); #expect(s == .ready)
  }

  @Test func aiFailureAndWaitingForAiResume() {
    #expect(run(.extracted, .understand, .failed) == .aiFailed)
    #expect(run(.aiFailed, .understand, .ok) == .relating)
    #expect(run(.waitingForAi, .understand, .ok) == .relating)
    #expect(run(.waitingForAi, .relate, .ok) == .ready)
    #expect(run(.waitingForAi, .embed, .ok) == .waitingForAi)
  }

  @Test func reindexingSettledItemStaysSettled() {
    #expect(run(.ready, .index, .ok) == .ready)
    #expect(run(.partial, .index, .ok) == .partial)
  }

  @Test func stageEntryRunningStatusPerStage() {
    #expect(stageEntryStatus(.extract) == .extracting)
    #expect(stageEntryStatus(.embed) == .embedding)
    #expect(stageEntryStatus(.understand) == .understanding)
    #expect(stageEntryStatus(.relate) == .relating)
    #expect(stageEntryStatus(.organizeBatch) == .relating)
    for stage in [Stage.thumbnail, .snapshot, .index, .consolidate] {
      #expect(stageEntryStatus(stage) == nil)
    }
  }

  @Test func stageEntryDoesNotOverwriteStickyExceptExtract() {
    for sticky in STICKY_STATUSES {
      #expect(stageEntryStatus(.extract, sticky) == .extracting)
      for stage in [Stage.embed, .understand, .relate, .organizeBatch] {
        #expect(stageEntryStatus(stage, sticky) == nil)
      }
    }
    #expect(stageEntryStatus(.understand, .aiFailed) == .understanding)
    #expect(stageEntryStatus(.understand, .waitingForAi) == .understanding)
    #expect(stageEntryStatus(.relate, .aiFailed) == .relating)
    #expect(stageEntryStatus(.relate, .waitingForAi) == .relating)
  }

  @Test func stageEntryNeverMovesBackwards() {
    #expect(stageEntryStatus(.embed, .relating) == nil)
    #expect(stageEntryStatus(.embed, .understanding) == nil)
    #expect(stageEntryStatus(.embed, .aiFailed) == nil)
    #expect(stageEntryStatus(.embed, .waitingForAi) == nil)
    #expect(stageEntryStatus(.embed, .ready) == nil)
    #expect(stageEntryStatus(.embed, .extracted) == .embedding)
    #expect(stageEntryStatus(.embed, .captured) == .embedding)
    #expect(stageEntryStatus(.understand, .relating) == nil)
    #expect(stageEntryStatus(.understand, .embedding) == .understanding)
    #expect(stageEntryStatus(.relate, .ready) == nil)
    #expect(stageEntryStatus(.relate, .understanding) == .relating)
    #expect(stageEntryStatus(.extract, .ready) == .extracting)
  }
}
