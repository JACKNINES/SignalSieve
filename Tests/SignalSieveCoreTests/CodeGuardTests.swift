// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Recognizes source code without classifying ordinary prose")
func recognizesLikelyCode() {
    let code = CodeGuardAnalyzer.analyze("let answer = compute(value);")
    let prose = CodeGuardAnalyzer.analyze("Let the answer remain clear for everyone reading this sentence.")

    #expect(code.isLikelyCode)
    #expect(code.detectedLanguage == "Source code")
    #expect(!prose.isLikelyCode)
    #expect(prose.findings.isEmpty)
}

@Test("Detects Trojan Source controls and invisible code characters")
func detectsInvisibleCodeRisks() {
    let analysis = CodeGuardAnalyzer.analyze(
        "let access\u{200B}Level = true; // guard\u{202E}\nlet value\u{00A0}= 1"
    )

    #expect(analysis.hasRisks)
    #expect(analysis.findings.contains { $0.kind == .invisibleCharacter && $0.codePoint == "U+200B" })
    #expect(analysis.findings.contains { $0.kind == .bidirectionalControl && $0.codePoint == "U+202E" })
    #expect(analysis.findings.contains { $0.kind == .nonASCIIWhitespace && $0.line == 2 })
    #expect(analysis.highestRiskLevel == .high)
}

@Test("Code Guard exposes the maximum risk used by clipboard priority")
func reportsMaximumCodeRisk() {
    let mediumOnly = CodeGuardAnalyzer.analyze("let greeting = “hello”; // rich punctuation")
    let mixed = CodeGuardAnalyzer.analyze("let access\u{200B}Level = “admin”; // mixed risks")

    #expect(mediumOnly.highestRiskLevel == .medium)
    #expect(mixed.highestRiskLevel == .high)
    #expect(CodeGuardAnalyzer.analyze("let value = 1;").highestRiskLevel == nil)
}

@Test("Detects a common Cyrillic look-alike inside a Latin identifier")
func detectsConfusableIdentifier() throws {
    let analysis = CodeGuardAnalyzer.analyze("let p\u{0430}ssword = true;")
    let finding = try #require(
        analysis.findings.first { $0.kind == .confusableIdentifier }
    )

    #expect(finding.codePoint == "U+0430")
    #expect(finding.kind.riskLevel == .high)
    #expect(finding.line == 1)
    #expect(finding.column == 6)
}

@Test("Allows identifiers written consistently in one non-Latin script")
func allowsSingleScriptIdentifier() {
    let analysis = CodeGuardAnalyzer.analyze("let пароль = true;")

    #expect(analysis.isLikelyCode)
    #expect(!analysis.findings.contains { finding in
        finding.kind == .mixedScriptIdentifier || finding.kind == .confusableIdentifier
    })
}

@Test("Sanitizes reviewable code without guessing confusable identifiers")
func sanitizesCodeForReview() {
    let source = "let p\u{0430}ssword\u{200B} = “value”\u{00A0};\u{202E}"
    let result = CodeGuardAnalyzer.sanitize(source)

    #expect(result.text == "let p\u{0430}ssword = \"value\" ;")
    #expect(result.removedCount == 2)
    #expect(result.replacedCount == 3)
    #expect(result.text.contains("\u{0430}"))
}

@Test("Code research queries never contain copied identifiers")
func keepsCodeResearchQueryPrivate() throws {
    let privateIdentifier = "privateSecret\u{0430}Token"
    let analysis = CodeGuardAnalyzer.analyze("let \(privateIdentifier) = true;")
    let finding = try #require(analysis.findings.first)
    let url = try #require(finding.researchURL)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = try #require(components.queryItems?.first(where: { $0.name == "q" })?.value)

    #expect(query.contains(finding.codePoint))
    #expect(!query.contains(privateIdentifier))
    #expect(!query.contains("privateSecret"))
}
