// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Detects zero-width, bidirectional control, and non-breaking space")
func detectsHiddenElements() {
    let text = "hola\u{200B}mundo\u{202E}\u{00A0}!"
    let result = HiddenTextAnalyzer.inspect(text)

    #expect(result.findings.count == 3)
    #expect(result.findings.map(\.kind) == [
        .zeroWidth,
        .bidirectional,
        .unusualWhitespace
    ])
    #expect(result.findings[0].codePoint == "U+200B")
}

@Test("Classifies ALM, LRM, and RLM as bidirectional controls")
func classifiesDirectionalMarks() {
    let result = HiddenTextAnalyzer.inspect("A\u{061C}B\u{200E}C\u{200F}D")

    #expect(result.findings.map(\.codePoint) == ["U+061C", "U+200E", "U+200F"])
    #expect(result.findings.allSatisfy { $0.kind == .bidirectional })
    #expect(result.findings.allSatisfy { $0.kind.riskLevel == .high })
    #expect(result.findings.map(\.displayName) == [
        "ARABIC LETTER MARK",
        "LEFT-TO-RIGHT MARK",
        "RIGHT-TO-LEFT MARK"
    ])
}

@Test("Assigns semantic risk levels to hidden element categories")
func assignsRiskLevels() {
    #expect(HiddenElementKind.unusualWhitespace.riskLevel == .suspicious)
    #expect(HiddenElementKind.unassigned.riskLevel == .suspicious)
    #expect(HiddenElementKind.zeroWidth.riskLevel == .medium)
    #expect(HiddenElementKind.variationSelector.riskLevel == .medium)
    #expect(HiddenElementKind.bidirectional.riskLevel == .high)
    #expect(HiddenElementKind.control.riskLevel == .high)
    #expect(HiddenElementKind.tag.riskLevel == .high)
    #expect(HiddenTextAnalyzer.inspect("medium\u{200B}").highestRiskLevel == .medium)
    #expect(HiddenTextAnalyzer.inspect("high\u{202E}").highestRiskLevel == .high)
}

@Test("Keeps deterministic evidence confidence separate from risk")
func separatesEvidenceConfidenceFromRisk() {
    let findings = HiddenTextAnalyzer.inspect("A\u{00A0}B\u{202E}C").findings

    #expect(findings.map(\.kind.riskLevel) == [.suspicious, .high])
    #expect(findings.allSatisfy { $0.evidenceConfidence == .exact })
}

@Test("Inspection reports the maximum real risk regardless of finding order")
func reportsMaximumHiddenRisk() {
    let highFirst = HiddenTextAnalyzer.inspect("a\u{202E}b\u{200B}c\u{00A0}")
    let highLast = HiddenTextAnalyzer.inspect("a\u{00A0}b\u{200B}c\u{202E}")
    let mediumOnly = HiddenTextAnalyzer.inspect("a\u{00A0}b\u{200B}")

    #expect(highFirst.highestRiskLevel == .high)
    #expect(highLast.highestRiskLevel == .high)
    #expect(mediumOnly.highestRiskLevel == .medium)
    #expect(HiddenTextAnalyzer.inspect("plain text").highestRiskLevel == nil)
}

@Test("Builds a private web query for a finding")
func buildsFindingResearchURL() throws {
    let original = "private-before\u{200B}private-after"
    let finding = try #require(HiddenTextAnalyzer.inspect(original).findings.first)
    let url = try #require(finding.researchURL)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = try #require(components.queryItems?.first(where: { $0.name == "q" })?.value)

    #expect(url.host == "duckduckgo.com")
    #expect(query.contains("U+200B"))
    #expect(query.contains("ZERO WIDTH SPACE"))
    #expect(!query.contains("private-before"))
    #expect(!query.contains("private-after"))
}

@Test("Allows visible structural whitespace")
func allowsVisibleStructuralWhitespace() {
    let result = HiddenTextAnalyzer.inspect("first\tcolumn\nsecond line\rthird line")

    #expect(result.isClean)
}

@Test("Reports scalar and UTF-16 positions independently")
func reportsUnicodePositions() throws {
    let result = HiddenTextAnalyzer.inspect("😀A\u{200B}B")
    let finding = try #require(result.findings.first)

    #expect(finding.scalarPosition == 3)
    #expect(finding.utf16Position == 4)
    #expect(result.scalarCount == 4)
    #expect(result.utf16Count == 5)
}

@Test("Reports canonical and compatibility normalization changes")
func reportsNormalizationChanges() {
    let decomposedAccent = HiddenTextAnalyzer.inspect("e\u{0301}")
    let fullWidth = HiddenTextAnalyzer.inspect("Ａ")

    #expect(decomposedAccent.changesUnderNFC)
    #expect(decomposedAccent.changesUnderNFKC)
    #expect(!fullWidth.changesUnderNFC)
    #expect(fullWidth.changesUnderNFKC)
}

@Test("Recognizes functional emoji composition without suppressing the finding")
func recognizesEmojiContext() {
    let family = "👨\u{200D}👩\u{200D}👧"
    let styledHeart = "♥\u{FE0F}"

    for text in [family, styledHeart] {
        let result = HiddenTextAnalyzer.inspect(text)
        #expect(!result.findings.isEmpty)
        #expect(result.findings.allSatisfy { $0.riskLevel == .clear })
        #expect(result.findings.allSatisfy { $0.context == .emojiComposition })
        #expect(result.actionableFindings.isEmpty)
        #expect(result.isClean)
        #expect(result.highestRiskLevel == nil)
    }
}

@Test("Distinguishes script joiners from Latin zero-width carriers")
func recognizesScriptShapingContext() {
    let persian = HiddenTextAnalyzer.inspect("نامه\u{200C}ای")
    let devanagari = HiddenTextAnalyzer.inspect("क्\u{200D}ष")
    let latinCarrier = HiddenTextAnalyzer.inspect("A\u{200C}B\u{200D}C")

    #expect(persian.findings.map(\.context) == [.scriptShaping])
    #expect(devanagari.findings.map(\.context) == [.scriptShaping])
    #expect(persian.isClean && devanagari.isClean)
    #expect(latinCarrier.actionableFindings.count == 2)
    #expect(latinCarrier.findings.allSatisfy { $0.riskLevel == .medium })
}

@Test("Recognizes bounded implicit direction marks but keeps explicit controls high risk")
func recognizesBidirectionalContext() {
    let mixedDirection = HiddenTextAnalyzer.inspect("العربية\u{200F} English")
    let explicitOverride = HiddenTextAnalyzer.inspect("العربية\u{202E} English")
    let repeatedMarks = HiddenTextAnalyzer.inspect("العربية\u{200F}\u{061C}\u{200F}")

    #expect(mixedDirection.findings.first?.context == .bidirectionalText)
    #expect(mixedDirection.findings.first?.riskLevel == .clear)
    #expect(mixedDirection.isClean)
    #expect(explicitOverride.highestRiskLevel == .high)
    #expect(repeatedMarks.actionableFindings.count == 3)
}

@Test("Recognizes standardized glyph and subdivision-flag variation sequences")
func recognizesGlyphAndTagSequences() {
    let ideographic = HiddenTextAnalyzer.inspect("邊\u{E0100}")
    let wales = HiddenTextAnalyzer.inspect(
        "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"
    )
    let arbitraryTagPayload = HiddenTextAnalyzer.inspect(
        "\u{1F3F4}\u{E0068}\u{E0065}\u{E006C}\u{E006C}\u{E006F}\u{E007F}"
    )

    #expect(ideographic.findings.first?.context == .glyphVariation)
    #expect(ideographic.isClean)
    #expect(wales.findings.count == 6)
    #expect(wales.findings.allSatisfy { $0.context == .emojiComposition && $0.riskLevel == .clear })
    #expect(arbitraryTagPayload.actionableFindings.count == 6)
    #expect(arbitraryTagPayload.highestRiskLevel == .high)
}
