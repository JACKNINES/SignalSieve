// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import Testing

@Test("Manual Input core analysis preserves the existing deterministic findings")
func manualInputCoreAnalysisMatchesExistingAnalyzers() {
    let source = "let safeURL = \"https://example.com/path?utm_source=mail&id=42\" // marker\u{200B}\u{200C}\u{200D}\u{2060}"
    let analysis = ManualInputInspectionAnalyzer.analyze(
        source,
        adaptiveModel: AdaptiveCopyModel(),
        isAdaptiveModelEnabled: true
    )

    #expect(analysis.limitation == nil)
    #expect(analysis.inspection == HiddenTextAnalyzer.inspect(source))
    #expect(analysis.covertChannelReport == CovertTextChannelAnalyzer.analyze(source))
    #expect(analysis.codeAnalysis == CodeGuardAnalyzer.analyze(source))
    #expect(analysis.binaryAnalysis == BinaryContentDetector.analyze(source))
    #expect(analysis.identifierAnalysis == OpaqueIdentifierAnalyzer.analyze(source))
    #expect(analysis.scamAnalysis == ScamAttemptDetector.analyze(source))
    #expect(analysis.linkCleaningReport == URLTrackerCleaner.cleanLinks(in: source))
    #expect(analysis.revealedFragments == InvisibleFragmentRevealer.reveal(in: source))
}

@Test("Manual Input core analysis refuses oversized text without a partial verdict")
func manualInputCoreAnalysisRefusesOversizedText() {
    let oversized = String(
        repeating: "a",
        count: TextAnalysisBudget.maximumInteractiveUTF8Bytes + 1
    )
    let analysis = ManualInputInspectionAnalyzer.analyze(
        oversized,
        adaptiveModel: AdaptiveCopyModel(),
        isAdaptiveModelEnabled: true
    )

    #expect(analysis.limitation != nil)
    #expect(analysis.inspection.isClean)
    #expect(analysis.covertChannelReport.findings.isEmpty)
    #expect(!analysis.codeAnalysis.isLikelyCode)
    #expect(!analysis.binaryAnalysis.isDetected)
    #expect(analysis.identifierAnalysis.findings.isEmpty)
    #expect(!analysis.scamAnalysis.isPotentialScam)
    #expect(analysis.linkCleaningReport.linksFound == 0)
    #expect(analysis.revealedFragments.isEmpty)
    #expect(!analysis.adaptiveAnalysis.wasEligibleForLearning)
}
