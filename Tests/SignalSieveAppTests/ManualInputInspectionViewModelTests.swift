// SPDX-License-Identifier: MPL-2.0
@testable import SignalSieve
import Foundation
import SignalSieveCore
import Testing

private actor ControlledManualInputInspectionWorker: ManualInputInspectionProviding {
    private var requests: [ManualInputInspectionRequest] = []
    private var completions: [UInt64: CheckedContinuation<ManualInputInspectionCompletion?, Never>] = [:]
    private var cancelledOperationIDs: [UInt64] = []

    func analyze(_ request: ManualInputInspectionRequest) async -> ManualInputInspectionCompletion? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                requests.append(request)
                completions[request.operationID] = continuation
            }
        } onCancel: {
            Task { await self.cancel(operationID: request.operationID) }
        }
    }

    var requestCount: Int { requests.count }
    var cancelledIDs: [UInt64] { cancelledOperationIDs }

    func request(at index: Int) -> ManualInputInspectionRequest? {
        guard requests.indices.contains(index) else { return nil }
        return requests[index]
    }

    func finish(operationID: UInt64, source: String? = nil) {
        guard let continuation = completions.removeValue(forKey: operationID) else { return }
        let resultSource = source ?? requests.first(where: { $0.operationID == operationID })?.source ?? ""
        continuation.resume(returning: ManualInputInspectionCompletion(
            operationID: operationID,
            source: resultSource,
            analysis: ManualInputInspectionAnalyzer.analyze(
                resultSource,
                adaptiveModel: AdaptiveCopyModel(),
                isAdaptiveModelEnabled: false
            )
        ))
    }

    private func cancel(operationID: UInt64) {
        cancelledOperationIDs.append(operationID)
        completions.removeValue(forKey: operationID)?.resume(returning: nil)
    }
}

private actor StaleManualInputInspectionWorker: ManualInputInspectionProviding {
    private(set) var requestCount = 0

    func analyze(_ request: ManualInputInspectionRequest) async -> ManualInputInspectionCompletion? {
        requestCount += 1
        let staleSource = "stale \u{202E} payload"
        return ManualInputInspectionCompletion(
            operationID: request.operationID &- 1,
            source: staleSource,
            analysis: ManualInputInspectionAnalyzer.analyze(
                staleSource,
                adaptiveModel: AdaptiveCopyModel(),
                isAdaptiveModelEnabled: false
            )
        )
    }
}

@MainActor
private func makeModel(
    worker: any ManualInputInspectionProviding
) -> SignalSieveViewModel {
    let suiteName = "SignalSieveManualInspectionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(false, forKey: "activeProtection.enabled")
    defaults.set(false, forKey: "activeProtection.adaptiveModel.enabled")
    defaults.set(true, forKey: "migration.legacyExecutablePreferences.v1")
    defaults.set(AppLanguage.english.rawValue, forKey: "appearance.language")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignalSieveManualInspectionTests-\(UUID().uuidString)", isDirectory: true)
    return SignalSieveViewModel(
        privateRulesURL: directory.appendingPathComponent("private-url-rules.json"),
        adaptiveModelURL: directory.appendingPathComponent("adaptive-copy-model.json"),
        defaults: defaults,
        inputInspectionWorker: worker
    )
}

private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

@Test("Manual Input inspection keeps automatic deterministic Result preparation")
@MainActor
func manualInspectionPreservesAutomaticInputResultPreparation() async {
    let worker = ControlledManualInputInspectionWorker()
    let model = makeModel(worker: worker)
    model.clipboardAutomationProtocol = .safeClean
    model.automaticallyPreparesInputResult = true

    model.input = "Visible\u{200B}carrier"
    model.inputDidChange()
    model.inspect()

    #expect(await waitUntil { model.output == "Visiblecarrier" })
    #expect(await waitUntil { await worker.requestCount == 1 })
}

@Test("Manual Input inspection applies only the newest rapid successive input")
@MainActor
func manualInspectionDiscardsRapidSupersededInput() async {
    let worker = ControlledManualInputInspectionWorker()
    let model = makeModel(worker: worker)

    model.input = "first \u{202E} payload"
    model.inspect()
    #expect(await waitUntil { await worker.requestCount == 1 })
    let firstID = await worker.request(at: 0)?.operationID

    model.input = "second visible text"
    model.inspect()
    #expect(await waitUntil { await worker.requestCount == 2 })
    let secondID = await worker.request(at: 1)?.operationID

    #expect(firstID != nil)
    #expect(secondID != nil)
    #expect(firstID != secondID)
    #expect((firstID ?? 0) < (secondID ?? 0))

    if let secondID {
        await worker.finish(operationID: secondID)
    }
    #expect(await waitUntil { model.status == "No known hidden Unicode elements were found." })
    #expect(model.inspection.isClean)

    if let firstID {
        await worker.finish(operationID: firstID)
    }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(model.input == "second visible text")
    #expect(model.inspection.isClean)
}

@Test("Manual Input inspection ignores a stale worker completion")
@MainActor
func manualInspectionDiscardsStaleCompletionIdentity() async {
    let worker = StaleManualInputInspectionWorker()
    let model = makeModel(worker: worker)

    model.input = "current visible text"
    model.inspect()

    #expect(await waitUntil { await worker.requestCount == 1 })
    try? await Task.sleep(for: .milliseconds(50))
    #expect(model.inspection.isClean)
    #expect(model.status == "Paste text to get started.")
}

@Test("Manual Input inspection cancellation prevents a superseded result from applying")
@MainActor
func manualInspectionCancellationPreventsSupersededResult() async {
    let worker = ControlledManualInputInspectionWorker()
    let model = makeModel(worker: worker)

    model.input = "cancelled \u{202E} payload"
    model.inspect()
    #expect(await waitUntil { await worker.requestCount == 1 })
    let firstID = await worker.request(at: 0)?.operationID

    model.input = "replacement visible text"
    model.inspect()
    #expect(await waitUntil { await worker.cancelledIDs.contains(firstID ?? 0) })

    if let firstID {
        await worker.finish(operationID: firstID)
    }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(model.inspection.isClean)
    #expect(model.status == "Paste text to get started.")
}

@Test("Manual Input inspection refuses oversized text before scheduling worker analysis")
@MainActor
func manualInspectionRefusesOversizedInputBeforeWorker() async {
    let worker = ControlledManualInputInspectionWorker()
    let model = makeModel(worker: worker)
    model.input = String(
        repeating: "a",
        count: TextAnalysisBudget.maximumInteractiveUTF8Bytes + 1
    )

    model.inspect()

    #expect(await worker.requestCount == 0)
    #expect(model.inspection.isClean)
    #expect(model.revealedFragments.isEmpty)
    #expect(model.status.contains("Analysis stopped at the safety limit:"))
    #expect(model.status.contains("No safety verdict was produced."))
}
