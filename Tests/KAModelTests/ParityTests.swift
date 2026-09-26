import Foundation
import Testing
@testable import KAModel

/// Sweeps `Tests/Fixtures/parity/{vocab,limits,status-table,text}.json` against the Swift port.
/// The fixture is written by `cd electron && pnpm run parity:export` and is never hand-edited.
@Suite struct ParityTests {
  private func str(_ v: Any?) -> String? { v as? String }
  private func dbl(_ v: Any?) -> Double? {
    switch v {
    case let n as Int: Double(n)
    case let n as Double: n
    default: nil
    }
  }

  // MARK: status-table.json

  @Test func statusTableParity() {
    let d = loadParityFixture("status-table") as! [String: Any]
    let transitions = d["transitions"] as! [[String: Any]]
    #expect(transitions.count == 594)
    for row in transitions {
      let status = ProcessingStatus(rawValue: row["status"] as! String)!
      let stage = Stage(rawValue: row["stage"] as! String)!
      let outcome = StageOutcome(rawValue: row["outcome"] as! String)!
      let isLast = row["isLast"] as! Bool
      let expected = row["next"] as! String
      let got = next(status, stage, outcome, ctx: TransitionContext(isLast: isLast))
      #expect(got.rawValue == expected, "next(\(status.rawValue), \(stage.rawValue), \(outcome.rawValue), isLast: \(isLast)) -> \(got.rawValue), want \(expected)")
    }
    let entries = d["stageEntryStatus"] as! [[String: Any]]
    #expect(entries.count == 108)
    for row in entries {
      let stage = Stage(rawValue: row["stage"] as! String)!
      let current = (row["current"] as? String).flatMap(ProcessingStatus.init(rawValue:))
      let expected = row["status"] as? String
      let got = stageEntryStatus(stage, current)
      #expect(got?.rawValue == expected, "stageEntryStatus(\(stage.rawValue), \(current?.rawValue ?? "nil")) -> \(got?.rawValue ?? "nil"), want \(expected ?? "nil")")
    }
  }

  // MARK: text.json

  @Test func textParity() {
    let d = loadParityFixture("text") as! [String: Any]
    let nowIso = d["nowIso"] as! String
    for c in d["cases"] as! [[String: Any]] {
      let fn = c["fn"] as! String
      let args = c["args"] as! [Any]
      let out = c["out"]
      var got: Any?
      switch fn {
      case "truncate":
        got = truncate(args[0] as! String, dbl(args[1]).map(Int.init)!)
      case "slugify":
        got = slugify(args[0] as! String)
      case "normalizeName":
        got = normalizeName(args[0] as! String)
      case "relativeTime":
        got = relativeTime(iso: args[0] as! String, nowIso: args.count > 1 ? args[1] as! String : nowIso)
      case "formatBytes":
        got = formatBytes(args.first.map { dbl($0) ?? .nan } ?? .nan)
      case "formatDuration":
        got = formatDuration(args.first.map { dbl($0) ?? .nan } ?? .nan)
      case "isProbablyNaturalLanguage":
        got = isProbablyNaturalLanguage(args[0] as! String)
      case "tokenize":
        got = tokenize(args[0] as! String)
      default:
        Issue.record("unknown fn \(fn)")
      }
      if let expected = out as? [String] {
        #expect((got as? [String]) == expected, "\(fn)\(args)")
      } else if let expected = out as? Bool {
        #expect((got as? Bool) == expected, "\(fn)\(args)")
      } else {
        #expect((got as? String) == (out as? String), "\(fn)\(args) -> \(String(describing: got)), want \(String(describing: out))")
      }
    }
  }

  // MARK: limits.json

  @Test func limitsParity() {
    let d = loadParityFixture("limits") as! [String: Any]
    let limits = d["LIMITS"] as! [String: Any]
    let ints: [String: Double] = [
      "maxExtractedChars": Double(LIMITS.maxExtractedChars),
      "understandTextChars": Double(LIMITS.understandTextChars),
      "readDocumentChars": Double(LIMITS.readDocumentChars),
      "summaryUnderstandingMaxChars": Double(LIMITS.summaryUnderstandingMaxChars),
      "excerptChars": Double(LIMITS.excerptChars),
      "bodyChunkChars": Double(LIMITS.bodyChunkChars),
      "maxBodyChunks": Double(LIMITS.maxBodyChunks),
      "folderMaxFiles": Double(LIMITS.folderMaxFiles),
      "folderMaxDepth": Double(LIMITS.folderMaxDepth),
      "folderSampleFiles": Double(LIMITS.folderSampleFiles),
      "folderSampleFileBytes": Double(LIMITS.folderSampleFileBytes),
      "folderChildrenBodyEmbedLimit": Double(LIMITS.folderChildrenBodyEmbedLimit),
      "thumbnailMaxPx": Double(LIMITS.thumbnailMaxPx),
      "snapshotWidth": Double(LIMITS.snapshotWidth),
      "snapshotHeight": Double(LIMITS.snapshotHeight),
      "snapshotTimeoutMs": Double(LIMITS.snapshotTimeoutMs),
      "fetchTimeoutMs": Double(LIMITS.fetchTimeoutMs),
      "aiTimeoutMs": Double(LIMITS.aiTimeoutMs),
      "batchGateMs": Double(LIMITS.batchGateMs),
      "organizeSteps": Double(LIMITS.organizeSteps),
      "organizeBatchSteps": Double(LIMITS.organizeBatchSteps),
      "commandSteps": Double(LIMITS.commandSteps),
      "runPromptTokenCeiling": Double(LIMITS.runPromptTokenCeiling),
      "cosineFloor": LIMITS.cosineFloor,
      "nearDuplicateCosine": LIMITS.nearDuplicateCosine,
      "minCollectionConfidence": LIMITS.minCollectionConfidence,
      "minNewCollectionMembers": Double(LIMITS.minNewCollectionMembers),
      "minCollectionDescriptionChars": Double(LIMITS.minCollectionDescriptionChars),
      "collectionNameFold": LIMITS.collectionNameFold,
      "maxAttempts": Double(LIMITS.maxAttempts)
    ]
    for (key, value) in ints {
      #expect(dbl(limits[key]) == value, "LIMITS.\(key): \(String(describing: limits[key])) != \(value)")
    }
    #expect(limits["retryBackoffMs"] as? [Int] == LIMITS.retryBackoffMs)
    let lanes = limits["lanes"] as! [String: Int]
    #expect(lanes["io"] == LIMITS.lanes.io && lanes["embed"] == LIMITS.lanes.embed && lanes["ai"] == LIMITS.lanes.ai)
    #expect(dbl(d["STRUCTURED_MAX_TOKENS"]) == Double(STRUCTURED_MAX_TOKENS))
    #expect(dbl(d["STRUCTURED_MAX_TOKENS_CAP"]) == Double(STRUCTURED_MAX_TOKENS_CAP))
    #expect(d["STRUCTURED_FAILURE_MESSAGE"] as? String == STRUCTURED_FAILURE_MESSAGE)
    #expect(dbl(d["AGENT_MAX_TOKENS"]) == Double(AGENT_MAX_TOKENS))
    #expect(dbl(d["RUN_PROMPT_TOKEN_CEILING"]) == Double(RUN_PROMPT_TOKEN_CEILING))
    #expect(limits.count == ints.count + 2, "LIMITS key count drifted — new key needs a parity row")
  }

  // MARK: vocab.json

  @Test func vocabParity() {
    let v = loadParityFixture("vocab") as! [String: Any]

    #expect(v["KINDS"] as? [String] == KINDS)
    let kindLabel = v["KIND_LABEL"] as! [String: String]
    for kind in Kind.allCases { #expect(kindLabel[kind.rawValue] == KIND_LABEL[kind], "KIND_LABEL.\(kind.rawValue)") }

    let relTypes = v["RELATIONSHIP_TYPES"] as! [String: [String: Any]]
    for (id, info) in relTypes {
      let t = RelationshipType(rawValue: id)!
      #expect(RELATIONSHIP_TYPES[t]!.symmetric == info["symmetric"] as! Bool, Comment(rawValue: id))
      #expect(RELATIONSHIP_TYPES[t]!.label == info["label"] as! String, Comment(rawValue: id))
      #expect(RELATIONSHIP_TYPES[t]!.inverseLabel == info["inverseLabel"] as! String, Comment(rawValue: id))
    }
    #expect(v["RELATIONSHIP_TYPE_IDS"] as? [String] == RELATIONSHIP_TYPE_IDS.map(\.rawValue))
    let symmetric = v["symmetric"] as! [String: Bool]
    for (id, flag) in symmetric { #expect(isSymmetric(RelationshipType(rawValue: id)!) == flag, Comment(rawValue: id)) }
    let relLabel = v["relationshipLabel"] as! [String: [String: String]]
    for (id, dirs) in relLabel {
      let t = RelationshipType(rawValue: id)!
      #expect(relationshipLabel(t, .out) == dirs["out"], "\(id).out")
      #expect(relationshipLabel(t, .in) == dirs["in"], "\(id).in")
    }

    #expect(v["PROCESSING_STATUSES"] as? [String] == PROCESSING_STATUSES)
    let statusLabel = v["STATUS_LABEL"] as! [String: String]
    for s in ProcessingStatus.allCases { #expect(statusLabel[s.rawValue] == STATUS_LABEL[s], Comment(rawValue: s.rawValue)) }
    let stageLabel = v["STAGE_LABEL"] as! [String: String]
    for s in Stage.allCases { #expect(stageLabel[s.rawValue] == STAGE_LABEL[s], Comment(rawValue: s.rawValue)) }

    let stages = v["USER_STAGES"] as! [[String: Any]]
    #expect(stages.count == USER_STAGES.count)
    for (i, row) in stages.enumerated() {
      #expect(row["id"] as? String == USER_STAGES[i].id.rawValue)
      #expect(row["label"] as? String == USER_STAGES[i].label)
      #expect(row["statuses"] as? [String] == USER_STAGES[i].statuses.map(\.rawValue))
    }
    let stageFor = v["userStageFor"] as! [String: String?]
    for s in ProcessingStatus.allCases {
      #expect(stageFor[s.rawValue]! == userStageFor(s)?.id.rawValue, "userStageFor(\(s.rawValue))")
    }
    let sticky = v["STICKY_STATUSES"] as! [String]
    #expect(sticky == STICKY_STATUSES.map(\.rawValue))
    let failed = v["isFailed"] as! [String: Bool]
    for (s, flag) in failed { #expect(isFailed(ProcessingStatus(rawValue: s)!) == flag, Comment(rawValue: s)) }
    let terminal = v["isTerminal"] as! [String: Bool]
    for (s, flag) in terminal { #expect(isTerminal(ProcessingStatus(rawValue: s)!) == flag, Comment(rawValue: s)) }

    let copy = v["COPY"] as! [String: Any]
    let strings: [String: String] = [
      "tagline": COPY.tagline, "taglineRest": COPY.taglineRest, "saved": COPY.saved,
      "cantReadPage": COPY.cantReadPage, "stillFiguring": COPY.stillFiguring,
      "emptyCollection": COPY.emptyCollection, "trashEmpty": COPY.trashEmpty,
      "askNothing": COPY.askNothing, "askScanning": COPY.askScanning,
      "askScanCaption": COPY.askScanCaption, "askAnswered": COPY.askAnswered,
      "askStopTitle": COPY.askStopTitle, "askStopBody": COPY.askStopBody,
      "dropHint": COPY.dropHint, "dropHere": COPY.dropHere, "dropSub": COPY.dropSub,
      "pasteHint": COPY.pasteHint, "notUnderstood": COPY.notUnderstood,
      "connectHint": COPY.connectHint
    ]
    for (key, value) in strings { #expect(copy[key] as? String == value, "COPY.\(key)") }
    let samples = copy["samples"] as! [String: [String]]
    #expect(samples["foundRelated"] == [COPY.foundRelated(1), COPY.foundRelated(4)])
    #expect(samples["alreadyKept"] == [COPY.alreadyKept("3 days ago")])
    #expect(samples["noMatches"] == [COPY.noMatches("invoice")])
    #expect(samples["askReading"] == [COPY.askReading(1), COPY.askReading(5)])
    #expect(samples["askFound"] == [COPY.askFound(1), COPY.askFound(5)])

    #expect(v["SKIP_DIR_NAMES"] as? [String] == SKIP_DIR_NAMES)
    #expect(v["TEMP_PATH_MARKERS"] as? [String] == TEMP_PATH_MARKERS)
    #expect(v["DEFAULT_MODEL"] as? String == DEFAULT_MODEL)
    #expect(v["DEFAULT_BASE_URL"] as? String == DEFAULT_BASE_URL)
    let defaults = v["AI_PROVIDER_DEFAULTS"] as! [String: [String: String]]
    for (id, row) in defaults {
      let p = AiProviderId(rawValue: id)!
      #expect(AI_PROVIDER_DEFAULTS[p]!.model == row["model"], "\(id).model")
      #expect(AI_PROVIDER_DEFAULTS[p]!.baseUrl == row["baseUrl"], "\(id).baseUrl")
    }
    let labels = v["AI_PROVIDER_LABEL"] as! [String: String]
    for (id, label) in labels { #expect(AI_PROVIDER_LABEL[AiProviderId(rawValue: id)!] == label, Comment(rawValue: id)) }
    #expect(v["SNIPPET_OPEN"] as? String == SNIPPET_OPEN)
    #expect(v["SNIPPET_CLOSE"] as? String == SNIPPET_CLOSE)
    #expect(v["EMBEDDING_MODEL_ID"] as? String == EMBEDDING_MODEL_ID)
    #expect(v["EMBEDDING_DIMS"] as? Int == EMBEDDING_DIMS)
    #expect(v["MEDIA_SCHEME"] as? String == MEDIA_SCHEME)
    #expect(v["MEDIA_ROOTS"] as? [String] == MEDIA_ROOTS)
    #expect(v["INTERNAL_DND_MIME"] as? String == INTERNAL_DND_MIME)

    let layout = v["LAYOUT"] as! [String: Any]
    let win = layout["window"] as! [String: Int]
    #expect(win["width"] == Int(LAYOUT.window.width) && win["height"] == Int(LAYOUT.window.height))
    let margin = layout["margin"] as! [String: Int]
    #expect(margin["top"] == Int(LAYOUT.margin.top) && margin["right"] == Int(LAYOUT.margin.right)
      && margin["bottom"] == Int(LAYOUT.margin.bottom) && margin["left"] == Int(LAYOUT.margin.left))
    let rail = layout["rail"] as! [String: Int]
    #expect(rail["width"] == Int(LAYOUT.rail.width) && rail["notchHeight"] == Int(LAYOUT.rail.notchHeight))
    #expect(layout["cardGap"] as? Int == Int(LAYOUT.cardGap))
    #expect((layout["card"] as! [String: Int])["width"] == Int(LAYOUT.cardWidth))
    #expect(layout["trayGap"] as? Int == Int(LAYOUT.trayGap))
    #expect(layout["anchorMode"] as? String == LAYOUT.anchorMode.rawValue)

    let shelf = v["SHELF"] as! [String: Any]
    let body = shelf["body"] as! [String: Int]
    #expect(body["width"] == Int(SHELF.body.width) && body["height"] == Int(SHELF.body.height))
    #expect(shelf["radius"] as? Int == Int(SHELF.radius) && shelf["fillet"] as? Int == Int(SHELF.fillet)
      && shelf["shadow"] as? Int == Int(SHELF.shadow))
    let sw = v["SHELF_WINDOW"] as! [String: Int]
    #expect(sw["width"] == Int(SHELF_WINDOW.width) && sw["height"] == Int(SHELF_WINDOW.height))
    #expect(v["SHELF_EXIT_MS"] as? Int == SHELF_EXIT_MS)
    #expect(v["railAnchorX"] as? Int == Int(railAnchorX()))

    let channels = v["IPC_CHANNELS"] as! [String: String]
    #expect(channels.count == IPC_CHANNELS.count)
    for entry in IPC_CHANNELS { #expect(channels[entry.key] == entry.channel, Comment(rawValue: entry.key)) }
    #expect(v["IPC_CHANNEL_LIST"] as? [String] == IPC_CHANNEL_LIST)
    let events = v["IPC_EVENTS"] as! [String: String]
    #expect(events.count == IPC_EVENTS.count)
    for entry in IPC_EVENTS { #expect(events[entry.key] == entry.event, Comment(rawValue: entry.key)) }
    #expect(v["IPC_EVENT_LIST"] as? [String] == IPC_EVENT_LIST)
  }
}
