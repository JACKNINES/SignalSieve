// SPDX-License-Identifier: MPL-2.0
import Foundation
import SignalSieveCore
import Testing

@Test("Copied hidden-Unicode reports localize labels without copying invisible scalars")
func formatsSafeHiddenUnicodeReport() throws {
    let invisible = "\u{200B}"
    let inspection = HiddenTextAnalyzer.inspect("alpha\(invisible)beta")
    let report = FindingReportFormatter.hiddenReport(inspection, language: .spanish)

    #expect(report.contains("Hallazgos de Unicode oculto"))
    #expect(report.contains("U+200B"))
    #expect(report.contains("Riesgo:"))
    #expect(report.contains("Confianza de evidencia: Detección exacta"))
    #expect(!report.contains(invisible))
}

@Test("Code, pattern, and binary finding reports include useful audit metadata")
func formatsAnalyzerReports() throws {
    let code = CodeGuardAnalyzer.analyze(
        "func read() {\n    let access\u{200B}Level = \"admin\"\n}\n"
    )
    let codeReport = FindingReportFormatter.codeReport(code, language: .english)
    #expect(codeReport.contains("Code Guard Findings"))
    #expect(codeReport.contains("line 2"))
    #expect(codeReport.contains("High risk"))

    let pattern = PatternFinding(
        kind: .repeatedPhrase,
        pattern: "privacy remains\u{200B} local",
        detail: "",
        matchingSampleCount: 3,
        confidence: 0.82
    )
    let patternText = FindingReportFormatter.patternFinding(pattern, language: .english)
    #expect(patternText.contains("82%"))
    #expect(patternText.contains("Evidence confidence: Heuristic indication"))
    #expect(patternText.contains("⟦U+200B⟧"))
    #expect(!patternText.contains("\u{200B}"))

    let binary = BinaryContentAnalysis(
        kind: .base64,
        confidence: .high,
        byteCount: 64,
        evidence: "Structurally valid"
    )
    let binaryText = FindingReportFormatter.binaryFinding(binary, language: .norwegianBokmal)
    #expect(binaryText.contains("Binærbeskyttelse"))
    #expect(binaryText.contains("64"))
}

@Test("File-provenance and rewrite reports preserve confidence boundaries")
func formatsNewEvidenceReports() {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let provenance = FileProvenanceAnalyzer.analyze(png, fileName: "empty.png")
    let provenanceText = FindingReportFormatter.fileProvenanceReport(
        provenance,
        language: .english
    )
    #expect(provenanceText.localizedCaseInsensitiveContains("read-only"))
    #expect(provenanceText.contains("No embedded C2PA container"))

    let rewrite = RewriteIntegrityAnalyzer.analyze(
        original: "The value is 39.",
        candidate: "The value is 40."
    )
    let rewriteText = FindingReportFormatter.rewriteIntegrityReport(
        rewrite,
        language: .english
    )
    #expect(rewriteText.contains("Semantic equivalence: Not testable"))
    #expect(rewriteText.contains("Number or date"))
    #expect(rewriteText.contains("Exact detection"))
}

@Test("Reveal reports expose binary mapping without hidden characters")
func formatsRevealReport() {
    let fragment = RevealedInvisibleFragment(
        id: 0,
        findingNumber: 1,
        codePoint: "U+200C",
        line: 1,
        column: 8,
        presentation: .decodedPayload,
        text: "u suck",
        hiddenScalarCount: 48,
        scalarPositions: Array(1...48),
        zeroWidthBinary: ZeroWidthBinaryDetails(
            zeroCodePoint: "U+200C",
            oneCodePoint: "U+200D",
            bits: "011101010010000001110011011101010110001101101011",
            completeByteCount: 6,
            trailingBitCount: 0,
            isPreviewTruncated: false
        )
    )
    let report = FindingReportFormatter.revealedReport([fragment], language: .english)

    #expect(report.contains("u suck"))
    #expect(report.contains("U+200C = 0 · U+200D = 1"))
    #expect(!report.contains("\u{200C}"))
    #expect(!report.contains("\u{200D}"))
}

@Test("Reveal reports distinguish a probable equivalence from exact decoding")
func formatsProbableRevealEquivalence() {
    let equivalence = ProbablePayloadEquivalence(
        text: "u suck",
        characterCount: 6,
        unicodeCodePoints: ["U+0075", "U+0020", "U+0073", "U+0075", "U+0063", "U+006B"],
        bitEditDistance: 4,
        similarityPercent: 92,
        confidence: .low
    )
    let fragment = RevealedInvisibleFragment(
        id: 0,
        findingNumber: 1,
        codePoint: "U+200C",
        line: 1,
        column: 39,
        presentation: .incompletePayload,
        text: "11101000010000001110011011101001100001101101011",
        hiddenScalarCount: 47,
        scalarPositions: Array(39...85),
        zeroWidthBinary: ZeroWidthBinaryDetails(
            zeroCodePoint: "U+200C",
            oneCodePoint: "U+200D",
            bits: "11101000010000001110011011101001100001101101011",
            completeByteCount: 5,
            trailingBitCount: 7,
            isPreviewTruncated: false,
            probableTextEquivalence: equivalence
        )
    )
    let report = FindingReportFormatter.revealedFragment(fragment, language: .spanish)

    #expect(report.contains("Equivalencia probable detectada: \"u suck\""))
    #expect(report.contains("Código Unicode: U+0075 U+0020 U+0073 U+0075 U+0063 U+006B"))
    #expect(report.contains("Confianza: Confianza baja (92%)"))
    #expect(report.contains("Distancia binaria: 4 cambios de bit"))
    #expect(report.contains("no es una decodificación exacta byte por byte"))
}

@Test("Signature reports visualize invisible diff content")
func formatsSafeSignatureReport() {
    let baseReport = VaccineScanReport(
        rootURL: URL(fileURLWithPath: "/tmp/project"),
        scannedFileCount: 1,
        binaryFileCount: 0,
        skippedFileCount: 0,
        excludedDirectoryCount: 0,
        ignoredPathCount: 0,
        isSignalSieveTarget: false,
        findings: []
    )
    let occurrence = SignatureOccurrence(
        id: "one.swift:1",
        relativePath: "one.swift",
        line: 1,
        column: 4,
        codePoint: "U+200B",
        fragment: nil,
        encoding: .utf8,
        changePreview: VaccineChangePreview(
            line: 1,
            before: "let\u{200B} value = 1",
            after: "let value = 1"
        )
    )
    let group = SignatureGroup(
        id: "SIG-12345678",
        technique: .hiddenUnicode,
        disposition: .safeToNeutralize,
        confidence: .high,
        codePoint: "U+200B",
        revealedFragment: "let\u{200B} value = 1",
        occurrences: [occurrence]
    )
    let report = FindingReportFormatter.signatureReport(
        SignatureHuntReport(vaccineReport: baseReport, groups: [group]),
        language: .spanish
    )

    #expect(report.contains("SIG-12345678"))
    #expect(report.contains("⟦U+200B⟧"))
    #expect(!report.contains("\u{200B}"))
}
