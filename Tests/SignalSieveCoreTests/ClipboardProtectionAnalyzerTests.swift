// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import Testing

@Test("Active protection detects hidden Unicode and tracked links together")
func detectsClipboardRisks() {
    let analysis = ClipboardProtectionAnalyzer.analyze(
        "Read​ https://example.com/article?q=keep&utm_source=copy",
        recentPatternTexts: []
    )

    #expect(analysis.containsHiddenUnicode)
    #expect(analysis.containsTrackedLinks)
    #expect(analysis.inspection.findings.count == 1)
    #expect(analysis.linkCleaning.text == "Read https://example.com/article?q=keep")
}

@Test("Active protection flags opaque short links without pretending to clean them")
func detectsOpaqueClipboardRedirect() {
    let input = "Open https://pin.it/4AbCdEf"
    let analysis = ClipboardProtectionAnalyzer.analyze(input, recentPatternTexts: [])

    #expect(analysis.containsTrackedLinks)
    #expect(analysis.linkCleaning.text == input)
    #expect(analysis.linkCleaning.linksChanged == 0)
    #expect(analysis.linkCleaning.unresolvedRedirectCount == 1)
}

@Test("Active protection combines UUID and scam-attempt analysis")
func detectsClipboardThreatIntelligence() {
    let analysis = ClipboardProtectionAnalyzer.analyze(
        "AppIe: modo perdido. Ver ubicación https://securityios.us/tvDb id 550e8400-e29b-41d4-a716-446655440000",
        recentPatternTexts: []
    )

    #expect(analysis.containsOpaqueIdentifiers)
    #expect(analysis.containsPotentialScam)
    #expect(analysis.identifierAnalysis.findings.count == 1)
}

@Test("Risk tiers distinguish standard, elevated, and persistent alerts")
func assignsClipboardAlertTiers() {
    let medium = ClipboardProtectionAnalyzer.analyze(
        "ordinary text\u{200B}",
        recentPatternTexts: []
    )
    let high = ClipboardProtectionAnalyzer.analyze(
        "ordinary text\u{202E}",
        recentPatternTexts: []
    )

    #expect(medium.inspection.highestRiskLevel == .medium)
    #expect(ClipboardProtectionAnalyzer.alertPriority(
        hiddenUnicodeRisk: medium.inspection.highestRiskLevel,
        codeRisk: medium.codeAnalysis.highestRiskLevel
    ) == .elevated)
    #expect(high.inspection.highestRiskLevel == .high)
    #expect(ClipboardProtectionAnalyzer.alertPriority(
        hiddenUnicodeRisk: high.inspection.highestRiskLevel,
        codeRisk: high.codeAnalysis.highestRiskLevel
    ) == .high)
    #expect(ClipboardProtectionAnalyzer.alertPriority(
        hiddenUnicodeRisk: nil,
        codeRisk: nil
    ) == .standard)
    #expect(ClipboardProtectionAnalyzer.alertPriority(
        hiddenUnicodeRisk: nil,
        codeRisk: nil,
        hasElevatedSignal: true
    ) == .elevated)
}

@Test("Alert priority obeys the complete risk-boundary matrix")
func enforcesAlertPriorityBoundaryMatrix() {
    let standardPairs: [(HiddenElementRiskLevel?, HiddenElementRiskLevel?)] = [
        (nil, nil),
        (.suspicious, nil),
        (nil, .suspicious)
    ]
    for (hiddenRisk, codeRisk) in standardPairs {
        #expect(ClipboardProtectionAnalyzer.alertPriority(
            hiddenUnicodeRisk: hiddenRisk,
            codeRisk: codeRisk
        ) == .standard)
    }

    let elevatedPairs: [(HiddenElementRiskLevel?, HiddenElementRiskLevel?)] = [
        (.medium, nil),
        (nil, .medium),
        (.medium, .suspicious),
        (.suspicious, .medium)
    ]
    for (hiddenRisk, codeRisk) in elevatedPairs {
        #expect(ClipboardProtectionAnalyzer.alertPriority(
            hiddenUnicodeRisk: hiddenRisk,
            codeRisk: codeRisk
        ) == .elevated)
    }

    let highPairs: [(HiddenElementRiskLevel?, HiddenElementRiskLevel?)] = [
        (.high, nil),
        (nil, .high),
        (.high, .suspicious),
        (.medium, .high),
        (.high, .high)
    ]
    for (hiddenRisk, codeRisk) in highPairs {
        #expect(ClipboardProtectionAnalyzer.alertPriority(
            hiddenUnicodeRisk: hiddenRisk,
            codeRisk: codeRisk
        ) == .high)
    }
}

@Test("Active protection reports source-code risks")
func detectsClipboardCodeRisks() {
    let analysis = ClipboardProtectionAnalyzer.analyze(
        "let p\u{0430}ssword = true; // copied code",
        recentPatternTexts: []
    )

    #expect(analysis.containsCodeRisk)
    #expect(analysis.codeAnalysis.isLikelyCode)
    #expect(analysis.codeAnalysis.findings.contains { $0.kind == .confusableIdentifier })
}

@Test("Active protection alerts on a pattern in exactly the latest three copies")
func detectsRecentClipboardPattern() {
    let first = "Privacy tools should remain entirely local and transparent for everyone. First sample."
    let second = "Privacy tools should remain entirely local and transparent for everyone. Second sample."
    let third = "Privacy tools should remain entirely local and transparent for everyone. Third sample."

    let one = ClipboardProtectionAnalyzer.analyze(first, recentPatternTexts: [])
    let two = ClipboardProtectionAnalyzer.analyze(second, recentPatternTexts: one.updatedPatternTexts)
    let three = ClipboardProtectionAnalyzer.analyze(third, recentPatternTexts: two.updatedPatternTexts)

    #expect(!one.containsRecentPattern)
    #expect(!two.containsRecentPattern)
    #expect(three.containsRecentPattern)
    #expect(three.recentPatternReport.sampleCount == 3)
}

@Test("Short and duplicate clipboard copies do not pollute pattern memory")
func ignoresUnhelpfulClipboardSamples() {
    let substantial = "A substantial clipboard sample that is long enough for private pattern comparison."
    let one = ClipboardProtectionAnalyzer.analyze(substantial, recentPatternTexts: [])
    let duplicate = ClipboardProtectionAnalyzer.analyze(substantial, recentPatternTexts: one.updatedPatternTexts)
    let short = ClipboardProtectionAnalyzer.analyze("Too short", recentPatternTexts: duplicate.updatedPatternTexts)

    #expect(one.addedPatternSample)
    #expect(!duplicate.addedPatternSample)
    #expect(!short.addedPatternSample)
    #expect(short.updatedPatternTexts == [substantial])
}

@Test("Active clipboard pattern memory remains bounded")
func boundsClipboardMemory() {
    let samples = (0..<15).map {
        "Unique clipboard sample number \($0) with enough content for deterministic local pattern analysis."
    }
    let final = samples.reduce(into: [String]()) { memory, sample in
        memory = ClipboardProtectionAnalyzer.appendingPatternSample(sample, to: memory).texts
    }

    #expect(final.count == ClipboardProtectionAnalyzer.maximumPatternSamples)
    #expect(final.first == samples[5])
    #expect(final.last == samples[14])
}

@Test("Active protection refuses oversized text without returning a green verdict")
func refusesOversizedClipboardAnalysis() {
    let oversized = String(
        repeating: "a",
        count: TextAnalysisBudget.maximumInteractiveUTF8Bytes + 1
    )
    let analysis = ClipboardProtectionAnalyzer.analyze(
        oversized,
        recentPatternTexts: []
    )

    #expect(analysis.limitation?.observedUTF8Bytes == oversized.utf8.count)
    #expect(analysis.cleanReceiptPriority == .elevated)
    #expect(analysis.cleanReceiptAlertCount == 1)
    #expect(!analysis.addedPatternSample)
    #expect(analysis.inspection.findings.isEmpty)
}

@Test("Pattern Memory rejects oversized samples and caps total retained bytes")
func boundsPatternMemoryBytes() {
    let oversized = String(
        repeating: "x",
        count: TextAnalysisBudget.maximumPatternSampleUTF8Bytes + 1
    )
    let rejected = ClipboardProtectionAnalyzer.appendingPatternSample(
        oversized,
        to: []
    )
    #expect(!rejected.added)
    #expect(rejected.rejectionReason == .inputTooLarge)

    var memory: [String] = []
    for index in 0..<6 {
        let sample = "sample-\(index)-" + String(repeating: "z", count: 60 * 1_024)
        memory = ClipboardProtectionAnalyzer.appendingPatternSample(
            sample,
            to: memory
        ).texts
    }
    #expect(memory.count == 4)
    #expect(memory.reduce(0) { $0 + $1.utf8.count }
        <= TextAnalysisBudget.maximumPatternMemoryUTF8Bytes)
}
