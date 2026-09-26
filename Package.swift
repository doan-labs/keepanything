// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "KeepAnythingKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "KAModel", targets: ["KAModel"]),
    .library(name: "KAStorage", targets: ["KAStorage"]),
    .library(name: "KACore", targets: ["KACore"]),
    .library(name: "KACapture", targets: ["KACapture"]),
    .library(name: "KAExtraction", targets: ["KAExtraction"]),
    .library(name: "KAPreviews", targets: ["KAPreviews"]),
    .library(name: "KAEmbeddings", targets: ["KAEmbeddings"]),
    .library(name: "KAAI", targets: ["KAAI"]),
    .library(name: "KARetrieval", targets: ["KARetrieval"]),
    .library(name: "KAAgent", targets: ["KAAgent"]),
    .library(name: "KAPipeline", targets: ["KAPipeline"]),
    .library(name: "KALibrary", targets: ["KALibrary"]),
    .library(name: "KAUI", targets: ["KAUI"]),
    .library(name: "KATestSupport", targets: ["KATestSupport"])
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.24.2")
  ],
  targets: [
    .target(name: "KAModel", path: "Sources/KAModel"),
    .target(
      name: "KAStorage",
      dependencies: ["KAModel", .product(name: "GRDB", package: "GRDB.swift")],
      path: "Sources/KAStorage"
    ),
    .target(name: "KACore", dependencies: ["KAModel", "KAStorage"], path: "Sources/KACore"),
    .target(name: "KACapture", dependencies: ["KAModel", "KACore"], path: "Sources/KACapture"),
    .target(name: "KAExtraction", dependencies: ["KAModel", "CZlib"], path: "Sources/KAExtraction"),
    .target(name: "KAPreviews", dependencies: ["KAModel"], path: "Sources/KAPreviews"),
    .target(
      name: "KAEmbeddings",
      dependencies: [
        "KAModel",
        .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager", condition: .when(platforms: [.macOS]))
      ],
      path: "Sources/KAEmbeddings"
    ),
    .target(name: "KAAI", dependencies: ["KAModel"], path: "Sources/KAAI"),
    .target(
      name: "KARetrieval",
      dependencies: ["KAModel", "KAStorage", "KAEmbeddings"],
      path: "Sources/KARetrieval"
    ),
    .target(
      name: "KAAgent",
      dependencies: ["KAModel", "KACore", "KAAI", "KARetrieval"],
      path: "Sources/KAAgent"
    ),
    .target(
      name: "KAPipeline",
      dependencies: ["KAModel", "KACore", "KAStorage"],
      path: "Sources/KAPipeline"
    ),
    .target(
      name: "KALibrary",
      dependencies: [
        "KAModel", "KAStorage", "KACore", "KACapture", "KAExtraction", "KAPreviews",
        "KAEmbeddings", "KAAI", "KARetrieval", "KAAgent", "KAPipeline"
      ],
      path: "Sources/KALibrary"
    ),
    .target(name: "KAUI", dependencies: ["KAModel", "KALibrary"], path: "Sources/KAUI"),
    .target(name: "KATestSupport", dependencies: ["KALibrary"], path: "Sources/KATestSupport"),
    .systemLibrary(name: "CZlib", path: "Sources/CZlib"),

    .testTarget(name: "KAModelTests", dependencies: ["KAModel"], path: "Tests/KAModelTests"),
    .testTarget(name: "KAStorageTests", dependencies: ["KAStorage"], path: "Tests/KAStorageTests"),
    .testTarget(name: "KACoreTests", dependencies: ["KACore"], path: "Tests/KACoreTests"),
    .testTarget(name: "KACaptureTests", dependencies: ["KACapture"], path: "Tests/KACaptureTests"),
    .testTarget(name: "KAExtractionTests", dependencies: ["KAExtraction"], path: "Tests/KAExtractionTests"),
    .testTarget(name: "KAPreviewsTests", dependencies: ["KAPreviews"], path: "Tests/KAPreviewsTests"),
    .testTarget(name: "KAEmbeddingsTests", dependencies: ["KAEmbeddings"], path: "Tests/KAEmbeddingsTests"),
    .testTarget(name: "KAAITests", dependencies: ["KAAI"], path: "Tests/KAAITests"),
    .testTarget(name: "KARetrievalTests", dependencies: ["KARetrieval"], path: "Tests/KARetrievalTests"),
    .testTarget(name: "KAAgentTests", dependencies: ["KAAgent"], path: "Tests/KAAgentTests"),
    .testTarget(name: "KAPipelineTests", dependencies: ["KAPipeline"], path: "Tests/KAPipelineTests"),
    .testTarget(name: "KALibraryTests", dependencies: ["KALibrary"], path: "Tests/KALibraryTests"),
    .testTarget(
      name: "KAE2ETests",
      dependencies: ["KALibrary", "KATestSupport"],
      path: "Tests/KAE2ETests"
    )
  ]
)
