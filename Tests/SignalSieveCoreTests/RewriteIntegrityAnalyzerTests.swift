// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import Testing

@Test("Flags exact number, URL, and quotation changes")
func flagsProtectedRewriteValues() {
    let original = #"The total was 39.50% on 2026-08-14. Read https://example.com/a and keep “quoted fact”."#
    let candidate = #"The total became 40% on 2026-08-15. Read https://example.com/b and keep “different fact”."#
    let report = RewriteIntegrityAnalyzer.analyze(original: original, candidate: candidate)

    #expect(report.assessment == .protectedValuesChanged)
    #expect(report.findings.contains { $0.kind == .number && $0.change == .removed })
    #expect(report.findings.contains { $0.kind == .url && $0.change == .added })
    #expect(report.findings.contains { $0.kind == .quotation })
    #expect(report.findings.allSatisfy { $0.evidenceConfidence == .exact })
    #expect(report.semanticEquivalenceConfidence == .notTestable)
}

@Test("Uses Unicode-aware tokens for multilingual prose")
func comparesMultilingualProse() {
    let report = RewriteIntegrityAnalyzer.analyze(
        original: "Doña Laura era una persona muy admirada en la sociedad.",
        candidate: "Doña Laura fue una individua demasiado admirada en lo que es la sociedad."
    )

    #expect(report.assessment == .reviewRequired)
    #expect(report.originalTokenCount == 10)
    #expect(report.candidateTokenCount == 13)
    #expect(report.lexicalDivergence > 0)
}

@Test("Blocks rewrite comparison for source code")
func blocksCodeRewriteComparison() {
    let report = RewriteIntegrityAnalyzer.analyze(
        original: "func total() -> Int { return 39 }",
        candidate: "func sum() -> Int { return 40 }"
    )

    #expect(report.assessment == .codeNotSupported)
}

@Test("Never treats lexical change as semantic proof")
func semanticEquivalenceRemainsUntestable() {
    let report = RewriteIntegrityAnalyzer.analyze(
        original: "The project starts tomorrow.",
        candidate: "Tomorrow is when the project begins."
    )

    #expect(report.assessment == .reviewRequired)
    #expect(report.semanticEquivalenceConfidence == .notTestable)
}
