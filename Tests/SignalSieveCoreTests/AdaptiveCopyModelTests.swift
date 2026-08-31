// SPDX-License-Identifier: MPL-2.0
import Foundation
import SignalSieveCore
import Testing

@Test("Personal Baseline warms up before reporting anomalies")
func warmsUpAdaptiveCopyModel() {
    var model = AdaptiveCopyModel()
    for index in 0..<AdaptiveCopyModel.minimumTrainingSamples {
        let analysis = model.evaluateAndLearn(
            "This is a calm ordinary paragraph number \(index) with consistent words and a short conclusion."
        )
        #expect(!analysis.isAnomalous)
    }

    let unusual = model.evaluateAndLearn(
        "URGENT 9999 HTTPS://EXAMPLE.COM HTTPS://EXAMPLE.ORG $$$ !!! 1234567890\n\n\n\n\n"
    )
    #expect(unusual.isWarmedUp)
    #expect(unusual.isAnomalous)
    #expect(unusual.deviations.count >= 2)
    #expect(!unusual.wasEligibleForLearning)
    #expect(model.sampleCount == AdaptiveCopyModel.minimumTrainingSamples)
}

@Test("Personal Baseline persists aggregates without copied text")
func persistsOnlyAdaptiveAggregates() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("adaptive.json")
    let secret = "PRIVATE-COPY-CONTENT-DO-NOT-PERSIST"
    var model = AdaptiveCopyModel()
    _ = model.evaluateAndLearn(secret + " with enough characters to become a sample")

    try AdaptiveCopyModelStore.save(model, to: url)
    let data = try Data(contentsOf: url)
    let serialized = String(decoding: data, as: UTF8.self)
    let restored = try AdaptiveCopyModelStore.load(from: url)

    #expect(restored == model)
    #expect(!serialized.contains(secret))
    #expect(!serialized.lowercased().contains("clipboard"))
}

@Test("Short text is not learned by Personal Baseline")
func ignoresShortAdaptiveSamples() {
    var model = AdaptiveCopyModel()
    let analysis = model.evaluateAndLearn("short")
    #expect(!analysis.wasEligibleForLearning)
    #expect(model.sampleCount == 0)
}

@Test("Personal Baseline does not learn deterministic risks or explicit rejections")
func rejectsUnsafeAdaptiveLearning() {
    let ordinaryText = "An ordinary paragraph with enough words to establish a local writing sample."
    let suspiciousText = "AppIe urgent account alert: open https://securityios.us/verify immediately."
    let ordinary = ClipboardProtectionAnalyzer.analyze(
        ordinaryText,
        recentPatternTexts: []
    )
    let suspicious = ClipboardProtectionAnalyzer.analyze(
        suspiciousText,
        recentPatternTexts: []
    )
    var model = AdaptiveCopyModel()

    let learned = model.evaluateAndLearn(
        ordinaryText,
        allowLearning: AdaptiveCopyLearningPolicy.allowsLearning(from: ordinary)
    )
    let rejected = model.evaluateAndLearn(
        suspiciousText,
        allowLearning: AdaptiveCopyLearningPolicy.allowsLearning(from: suspicious)
    )

    #expect(learned.wasEligibleForLearning)
    #expect(!rejected.wasEligibleForLearning)
    #expect(model.sampleCount == 1)
}

@Test("Personal Baseline refuses oversized samples before feature allocation")
func rejectsOversizedAdaptiveSample() {
    let oversized = String(
        repeating: "a",
        count: TextAnalysisBudget.maximumAdaptiveSampleUTF8Bytes + 1
    )
    var model = AdaptiveCopyModel()
    let analysis = model.evaluateAndLearn(oversized)

    #expect(!analysis.wasEligibleForLearning)
    #expect(model.sampleCount == 0)
}

@Test("Personal Baseline screens poisoning outliers before alert warmup")
func screensEarlyAdaptiveOutlier() {
    var model = AdaptiveCopyModel()
    for index in 0..<AdaptiveCopyModel.minimumOutlierScreeningSamples {
        _ = model.evaluateAndLearn(
            "This is a calm ordinary paragraph number \(index) with consistent words and a short conclusion."
        )
    }
    let unusual = model.evaluateAndLearn(
        "URGENT 9999 HTTPS://EXAMPLE.COM HTTPS://EXAMPLE.ORG $$$ !!! 1234567890\n\n\n\n\n"
    )

    #expect(!unusual.isWarmedUp)
    #expect(unusual.isLearningOutlier)
    #expect(!unusual.wasEligibleForLearning)
    #expect(model.sampleCount == AdaptiveCopyModel.minimumOutlierScreeningSamples)
}

@Test("Personal Baseline rejects oversized and invalid persisted state")
func rejectsUnsafeAdaptiveModelFiles() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let oversizedURL = directory.appendingPathComponent("oversized.json")
    try Data(
        repeating: 0x20,
        count: TextAnalysisBudget.maximumAdaptiveModelFileBytes + 1
    ).write(to: oversizedURL)
    #expect(throws: AdaptiveCopyModelStoreError.self) {
        try AdaptiveCopyModelStore.load(from: oversizedURL)
    }

    let invalidURL = directory.appendingPathComponent("invalid.json")
    try Data("{\"schemaVersion\":1,\"sampleCount\":-1,\"statistics\":{}}".utf8)
        .write(to: invalidURL)
    #expect(throws: AdaptiveCopyModelStoreError.invalidModel) {
        try AdaptiveCopyModelStore.load(from: invalidURL)
    }
}
