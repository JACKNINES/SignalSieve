// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import Testing

@Test("Finds standard UUIDs with exact positions")
func findsUUIDsWithoutOvermatching() {
    let text = "Reference:\n550e8400-e29b-41d4-a716-446655440000"
    let analysis = OpaqueIdentifierAnalyzer.analyze(text)

    #expect(analysis.findings.count == 1)
    #expect(analysis.findings.first?.line == 2)
    #expect(analysis.findings.first?.column == 1)
    #expect(analysis.findings.first?.version == 4)
    #expect(analysis.findings.first?.researchURL?.absoluteString.contains("550e8400") == false)
    #expect(!OpaqueIdentifierAnalyzer.analyze("550e8400-e29b-too-short").containsIdentifiers)
}

@Test("Detects brand look-alikes and a mismatched domain in a scam-style message")
func detectsExplainableScamCombination() {
    let text = "AppIe. El lPhone 15 Plus en modo perdido fue ubicado hoy a las 11:47 Hrs. Ver ubicación: https://securityios.us/tvDb"
    let analysis = ScamAttemptDetector.analyze(text)

    #expect(analysis.isPotentialScam)
    #expect(analysis.threatLevel == .high)
    #expect(analysis.inspectedHosts == ["securityios.us"])
    #expect(analysis.signals.contains { $0.kind == .brandLookalike && $0.evidence == "AppIe" })
    #expect(analysis.signals.contains { $0.kind == .brandLookalike && $0.evidence == "lPhone" })
    #expect(analysis.signals.contains { $0.kind == .brandDomainMismatch })
    #expect(analysis.signals.contains { $0.kind == .urgencyOrPressure })
    #expect(analysis.signals.contains { $0.kind == .sensitiveAction })
    #expect(analysis.signals.allSatisfy {
        $0.researchURL?.absoluteString.contains("securityios") == false
    })
}

@Test("Repeated look-alikes alone do not inflate a scam verdict")
func capsRepeatedScamSignalKinds() {
    let analysis = ScamAttemptDetector.analyze(
        "This training note compares AppIe and lPhone as typography examples."
    )
    #expect(analysis.signals.count == 2)
    #expect(analysis.score == 40)
    #expect(!analysis.isPotentialScam)
}

@Test("Detects Unicode-script brand confusables")
func detectsUnicodeBrandConfusables() {
    let analysis = ScamAttemptDetector.analyze(
        "Αpple account locked. Sign in now at http://192.0.2.10/login"
    )
    #expect(analysis.signals.contains { $0.kind == .brandLookalike })
    #expect(analysis.signals.contains { $0.kind == .dangerousURLStructure })
    #expect(analysis.isPotentialScam)
}

@Test("Does not flag ordinary brand prose or a recognized brand domain")
func avoidsBasicScamFalsePositives() {
    let legitimate = ScamAttemptDetector.analyze(
        "Apple published a guide for iPhone owners at https://support.apple.com/en-us/guide/iphone"
    )
    let unrelated = ScamAttemptDetector.analyze("We apply careful review before publishing a normal document.")

    #expect(!legitimate.isPotentialScam)
    #expect(!legitimate.signals.contains { $0.kind == .brandDomainMismatch })
    #expect(!unrelated.isPotentialScam)
    #expect(unrelated.signals.isEmpty)
}

@Test("High-confidence scam combinations receive persistent alert priority")
func prioritizesHighScamWarnings() {
    #expect(ClipboardProtectionAnalyzer.alertPriority(
        hiddenUnicodeRisk: nil,
        codeRisk: nil,
        scamThreat: .high
    ) == .high)
    #expect(ClipboardProtectionAnalyzer.alertPriority(
        hiddenUnicodeRisk: nil,
        codeRisk: nil,
        scamThreat: .suspicious
    ) == .elevated)
}
