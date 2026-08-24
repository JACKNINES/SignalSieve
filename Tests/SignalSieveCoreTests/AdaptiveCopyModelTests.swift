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
