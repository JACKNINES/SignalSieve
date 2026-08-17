// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import SignalSieveCore

@Test("Finds a repeated phrase across three recent texts")
func findsRepeatedPhrase() {
    let texts = [
        "Privacy tools should remain entirely local and transparent for everyone. This first sample discusses links.",
        "Our view is that privacy tools should remain entirely local and transparent for everyone. This sample discusses Unicode.",
        "In practice, privacy tools should remain entirely local and transparent for everyone. This sample discusses patterns."
    ]
    let report = PatternAnalyzer.analyze(texts)

    #expect(report.sampleCount == 3)
    #expect(report.hasSuspiciousRepetition)
    #expect(report.findings.contains { finding in
        finding.kind == .repeatedPhrase
            && finding.pattern.contains("privacy tools should remain entirely local")
            && finding.matchingSampleCount == 3
    })
}

@Test("Finds repeated multi-item list structure")
func findsRepeatedListStructure() {
    let texts = [
        "Checklist:\n- Inspect text\n- Clean links\n- Review output",
        "Actions:\n1. Paste text\n2. Inspect findings\n3. Copy result",
        "A paragraph without a list is different."
    ]
    let report = PatternAnalyzer.analyze(texts)

    #expect(report.findings.contains { $0.kind == .repeatedListStructure })
}

@Test("Does not claim a pattern from unrelated samples")
func ignoresUnrelatedSamples() {
    let texts = [
        "A short report about coastal weather and changing temperatures.",
        "Software teams review database migrations before deployment begins.",
        "The museum opened a collection of nineteenth-century landscape paintings."
    ]
    let report = PatternAnalyzer.analyze(texts)

    #expect(!report.hasSuspiciousRepetition)
}

@Test("Requires multiple samples")
func requiresMultipleSamples() {
    let report = PatternAnalyzer.analyze(["Only one substantial text is available for analysis."])

    #expect(report.sampleCount == 1)
    #expect(report.findings.isEmpty)
}

@Test("Matches repeated wording without case sensitivity")
func matchesCaseInsensitively() {
    let report = PatternAnalyzer.analyze([
        "LOCAL PRIVACY TOOLS should always explain every transformation clearly.",
        "Local privacy tools should always explain every transformation clearly to users."
    ])

    #expect(report.findings.contains { finding in
        finding.kind == .repeatedPhrase
            && finding.pattern.contains("local privacy tools should always explain")
    })
}

@Test("Keeps the longest repeated phrase instead of contained fragments")
func deduplicatesContainedPhrases() {
    let sentence = "transparent local tools protect private text without remote processing"
    let report = PatternAnalyzer.analyze([sentence, sentence])
    let phraseFindings = report.findings.filter { $0.kind == .repeatedPhrase }

    #expect(phraseFindings.count == 1)
    #expect(phraseFindings.first?.pattern.split(separator: " ").count == 6)
}

@Test("Requires three samples before reporting an em-dash pattern")
func appliesPunctuationThreshold() {
    let twoSamples = PatternAnalyzer.analyze([
        "Alpha — a unique discussion of astronomy and distant stars.",
        "Beta — a separate discussion of cooking and fresh vegetables."
    ])
    let threeSamples = PatternAnalyzer.analyze([
        "Alpha — a unique discussion of astronomy and distant stars.",
        "Beta — a separate discussion of cooking and fresh vegetables.",
        "Gamma — a third discussion of architecture and public plazas."
    ])

    #expect(!twoSamples.findings.contains { $0.kind == .repeatedPunctuation })
    #expect(threeSamples.findings.contains { $0.kind == .repeatedPunctuation })
}

@Test("Ignores empty samples when reporting sample count")
func ignoresEmptySamples() {
    let report = PatternAnalyzer.analyze([
        "  ",
        "A meaningful sample about local privacy safeguards.",
        "\n"
    ])

    #expect(report.sampleCount == 1)
}
