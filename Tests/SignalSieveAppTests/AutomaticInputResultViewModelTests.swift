// SPDX-License-Identifier: MPL-2.0
@testable import SignalSieve
import Foundation
import SignalSieveCore
import Testing

private actor ControlledAutomaticInputResultWorker: AutomaticInputResultProviding {
    private var requests: [AutomaticInputResultRequest] = []
    private var completions: [UInt64: CheckedContinuation<AutomaticInputResultCompletion?, Never>] = [:]
    private var cancelledOperationIDs: [UInt64] = []

    func prepare(_ request: AutomaticInputResultRequest) async -> AutomaticInputResultCompletion? {
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

    func request(at index: Int) -> AutomaticInputResultRequest? {
        guard requests.indices.contains(index) else { return nil }
        return requests[index]
    }

    func finish(
        operationID: UInt64,
        source: String? = nil,
        selectedProtocol: ClipboardAutomationProtocol? = nil,
        outcome: AutomaticInputResultOutcome? = nil
    ) {
        guard let continuation = completions.removeValue(forKey: operationID) else { return }
        let request = requests.first { $0.operationID == operationID }
        let resultSource = source ?? request?.source ?? ""
        let resultProtocol = selectedProtocol ?? request?.selectedProtocol ?? .reviewAll
        let resultOutcome = outcome ?? .preparedDeterministic(resultSource)
        continuation.resume(returning: AutomaticInputResultCompletion(
            operationID: operationID,
            source: resultSource,
            selectedProtocol: resultProtocol,
            outcome: resultOutcome
        ))
    }

    private func cancel(operationID: UInt64) {
        cancelledOperationIDs.append(operationID)
    }
}

private actor StaleAutomaticInputResultWorker: AutomaticInputResultProviding {
    private(set) var requestCount = 0

    func prepare(_ request: AutomaticInputResultRequest) async -> AutomaticInputResultCompletion? {
        requestCount += 1
        return AutomaticInputResultCompletion(
            operationID: request.operationID &- 1,
            source: request.source,
            selectedProtocol: request.selectedProtocol,
            outcome: .preparedDeterministic("stale synthetic result")
        )
    }
}

@MainActor
private func makeAutomaticModel(
    worker: any AutomaticInputResultProviding = AutomaticInputResultWorker(),
    selectedProtocol: ClipboardAutomationProtocol = .safeClean,
    automaticallyPreparesInputResult: Bool = true
) -> SignalSieveViewModel {
    let suiteName = "SignalSieveAutomaticInputResultTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(false, forKey: "activeProtection.enabled")
    defaults.set(false, forKey: "activeProtection.adaptiveModel.enabled")
    defaults.set(true, forKey: "migration.legacyExecutablePreferences.v1")
    defaults.set(AppLanguage.english.rawValue, forKey: "appearance.language")
    defaults.set(selectedProtocol.rawValue, forKey: "activeProtection.clipboardAutomationProtocol")
    defaults.set(automaticallyPreparesInputResult, forKey: "workspace.automaticSafeResult")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignalSieveAutomaticInputResultTests-\(UUID().uuidString)", isDirectory: true)
    return SignalSieveViewModel(
        privateRulesURL: directory.appendingPathComponent("private-url-rules.json"),
        adaptiveModelURL: directory.appendingPathComponent("adaptive-copy-model.json"),
        defaults: defaults,
        automaticInputResultWorker: worker
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

@Test("Automatic Input Result uses monotonic identities and applies only the newest burst")
@MainActor
func automaticInputResultDiscardsRapidSupersededBurst() async {
    let worker = ControlledAutomaticInputResultWorker()
    let model = makeAutomaticModel(worker: worker, selectedProtocol: .safeClean)

    model.input = "first synthetic \u{200B}payload"
    model.inputDidChange()
    #expect(await waitUntil { await worker.requestCount == 1 })
    let firstID = await worker.request(at: 0)?.operationID

    model.input = "second synthetic \u{200B}payload"
    model.inputDidChange()
    #expect(await waitUntil { await worker.requestCount == 2 })
    let secondID = await worker.request(at: 1)?.operationID

    #expect(firstID != nil)
    #expect(secondID != nil)
    #expect(firstID != secondID)
    #expect((firstID ?? 0) < (secondID ?? 0))

    if let firstID {
        await worker.finish(
            operationID: firstID,
            outcome: .preparedDeterministic("wrong synthetic result")
        )
    }
    if let secondID {
        await worker.finish(
            operationID: secondID,
            outcome: .preparedDeterministic("second synthetic payload")
        )
    }

    #expect(await waitUntil { model.output == "second synthetic payload" })
    #expect(model.output != "wrong synthetic result")
}

@Test("Automatic Input Result discards protocol changes during work")
@MainActor
func automaticInputResultDiscardsProtocolChangeDuringWork() async {
    let worker = ControlledAutomaticInputResultWorker()
    let model = makeAutomaticModel(worker: worker, selectedProtocol: .safeClean)
    model.input = "heart: \u{2764}\u{FE0F} synthetic\u{200B}payload"

    model.inputDidChange()
    #expect(await waitUntil { await worker.requestCount == 1 })
    let safeID = await worker.request(at: 0)?.operationID

    model.clipboardAutomationProtocol = .strictClean
    #expect(await waitUntil { await worker.requestCount == 2 })
    let strictID = await worker.request(at: 1)?.operationID

    if let safeID {
        await worker.finish(
            operationID: safeID,
            selectedProtocol: .safeClean,
            outcome: .preparedDeterministic("wrong safe synthetic result")
        )
    }
    if let strictID {
        await worker.finish(
            operationID: strictID,
            selectedProtocol: .strictClean,
            outcome: .preparedDeterministic("heart: \u{2764} syntheticpayload")
        )
    }

    #expect(await waitUntil { model.output == "heart: \u{2764} syntheticpayload" })
    #expect(model.output != "wrong safe synthetic result")
}

@Test("Automatic Input Result rejects wrong-protocol completions")
@MainActor
func automaticInputResultRejectsWrongProtocolCompletion() async {
    let worker = ControlledAutomaticInputResultWorker()
    let model = makeAutomaticModel(worker: worker, selectedProtocol: .strictClean)

    model.input = "wrong protocol synthetic \u{200B}payload"
    model.inputDidChange()
    #expect(await waitUntil { await worker.requestCount == 1 })
    let operationID = await worker.request(at: 0)?.operationID

    if let operationID {
        await worker.finish(
            operationID: operationID,
            selectedProtocol: .safeClean,
            outcome: .preparedDeterministic("wrong protocol result")
        )
    }

    try? await Task.sleep(for: .milliseconds(50))
    #expect(model.output == "")
}

@Test("Automatic Input Result discards completions after disablement")
@MainActor
func automaticInputResultDiscardsDisablementDuringWork() async {
    let worker = ControlledAutomaticInputResultWorker()
    let model = makeAutomaticModel(worker: worker, selectedProtocol: .safeClean)

    model.input = "disable synthetic \u{200B}payload"
    model.inputDidChange()
    #expect(await waitUntil { await worker.requestCount == 1 })
    let operationID = await worker.request(at: 0)?.operationID

    model.automaticallyPreparesInputResult = false
    #expect(await waitUntil { await worker.cancelledIDs.contains(operationID ?? 0) })
    if let operationID {
        await worker.finish(
            operationID: operationID,
            outcome: .preparedDeterministic("disabled synthetic result")
        )
    }

    try? await Task.sleep(for: .milliseconds(50))
    #expect(model.output == "")
}

@Test("Automatic Input Result ignores stale operation identities")
@MainActor
func automaticInputResultDiscardsStaleCompletionIdentity() async {
    let worker = StaleAutomaticInputResultWorker()
    let model = makeAutomaticModel(worker: worker, selectedProtocol: .safeClean)

    model.input = "current synthetic \u{200B}payload"
    model.inputDidChange()

    #expect(await waitUntil { await worker.requestCount == 1 })
    try? await Task.sleep(for: .milliseconds(50))
    #expect(model.output == "")
}

@Test("Automatic Input Result discards a completion when the visible source changed")
@MainActor
func automaticInputResultDiscardsSourceMismatchWithoutAnotherRequest() async {
    let worker = ControlledAutomaticInputResultWorker()
    let model = makeAutomaticModel(worker: worker, selectedProtocol: .safeClean)

    model.input = "original synthetic \u{200B}payload"
    model.inputDidChange()
    #expect(await waitUntil { await worker.requestCount == 1 })
    let operationID = await worker.request(at: 0)?.operationID

    // Simulate visible state changing before SwiftUI's change callback has
    // scheduled the replacement request. The source guard must stand alone.
    model.input = "new visible synthetic text"
    if let operationID {
        await worker.finish(
            operationID: operationID,
            outcome: .preparedDeterministic("obsolete synthetic result")
        )
    }

    try? await Task.sleep(for: .milliseconds(50))
    #expect(model.output == "")
}

@Test("Automatic Input Result refuses oversized text without a partial result")
@MainActor
func automaticInputResultRefusesOversizedInput() async {
    let model = makeAutomaticModel(selectedProtocol: .strictClean)
    model.input = String(
        repeating: "a",
        count: TextAnalysisBudget.maximumInteractiveUTF8Bytes + 1
    )

    model.inputDidChange()

    #expect(await waitUntil { model.status.contains("No clean result was produced.") })
    #expect(model.output == "")
    #expect(model.status.contains("Analysis stopped at the safety limit:"))
}

@Test("Automatic Input Result matches core Safe and Strict cleaning semantics")
@MainActor
func automaticInputResultMatchesSafeStrictCorePolicy() async {
    let model = makeAutomaticModel(selectedProtocol: .safeClean)
    let source = "heart: \u{2764}\u{FE0F} synthetic\u{200B}payload"
    let safeExpected = InputResultAutomationPolicy.prepareDeterministicResult(
        from: source,
        isEnabled: true,
        using: .safeClean
    )
    let strictExpected = InputResultAutomationPolicy.prepareDeterministicResult(
        from: source,
        isEnabled: true,
        using: .strictClean
    )

    model.input = source
    model.inputDidChange()
    #expect(await waitUntil { model.output == safeExpected ?? "" })

    model.clipboardAutomationProtocol = .strictClean
    #expect(await waitUntil { model.output == strictExpected ?? "" })
}

@Test("Automatic Input Result cancels superseded OCR preparation")
@MainActor
func automaticInputResultCancelsSupersededOCRPreparation() async {
    let worker = ControlledAutomaticInputResultWorker()
    let model = makeAutomaticModel(worker: worker, selectedProtocol: .visualTransfer)

    model.input = "first synthetic visual text"
    model.inputDidChange()
    #expect(await waitUntil { await worker.requestCount == 1 })
    let firstID = await worker.request(at: 0)?.operationID

    model.input = "second synthetic visual text"
    model.inputDidChange()
    #expect(await waitUntil { await worker.requestCount == 2 })
    let secondID = await worker.request(at: 1)?.operationID
    #expect(await waitUntil { await worker.cancelledIDs.contains(firstID ?? 0) })

    if let firstID {
        await worker.finish(
            operationID: firstID,
            outcome: .preparedVisualTransfer(VisualTransferResult(
                text: "wrong visual result",
                sourceCharacterCount: 27,
                recognizedCharacterCount: 19
            ))
        )
    }
    if let secondID {
        await worker.finish(
            operationID: secondID,
            outcome: .preparedVisualTransfer(VisualTransferResult(
                text: "second synthetic visual text",
                sourceCharacterCount: 28,
                recognizedCharacterCount: 28
            ))
        )
    }

    #expect(await waitUntil { model.output == "second synthetic visual text" })
    #expect(model.output != "wrong visual result")
}
