// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import SignalSieveCore

@Test("Requires a substantial sample before making a statistical assessment")
func watermarkProbeRequiresEnoughText() {
    let report = WatermarkProbeAnalyzer.analyze("A short sentence cannot support a statistical watermark conclusion.")

    #expect(report.assessment == .insufficientText)
    #expect(!report.hasEnoughText)
    #expect(report.minimumTokenCount == 80)
}

@Test("Does not treat verbosity alone as a watermark")
func watermarkProbeDoesNotTreatVerbosityAsProof() {
    let text = """
    I interviewed a research team and spent a month reading its public material. The central idea is that a generator can make small token choices that are individually ordinary. Across a sufficiently long sample, a detector with matching configuration may measure a bias in those choices. That observation does not establish why any particular assistant writes at length. Product style, safety training, user instructions, and ordinary variation can all affect response length. A careful review therefore separates a documented algorithm from claims about one provider's motives. It also avoids treating fluent prose, connective words, or long answers as proof of origin. Paraphrasing can alter token sequences and may weaken some published detectors, although the outcome depends on the scheme, the amount of text, and the strength of the edit. Back translation is another transformation rather than a universal guarantee. A short answer may contain too little evidence for a detector, but absence of evidence in a short sample is not evidence that no watermark exists. Any reliable provider-specific conclusion requires the correct tokenizer, detector settings, secret material, and calibrated reference data.
    """

    let report = WatermarkProbeAnalyzer.analyze(text)

    #expect(report.hasEnoughText)
    #expect(report.assessment == .noElevatedRegularity)
    #expect(report.elevatedSignalCount < 2)
}

@Test("Reports strongly repeated and mechanically regular surface features")
func watermarkProbeFindsArtificialRegularity() {
    let text = (1...16).map { index in
        "Signal pattern keeps the same repeated phrase while numbered sample \(index) preserves cadence."
    }.joined(separator: " ")

    let report = WatermarkProbeAnalyzer.analyze(text)

    #expect(report.hasEnoughText)
    #expect(report.assessment == .elevatedRegularity)
    #expect(report.elevatedSignalCount >= 3)
    #expect(report.signals.first { $0.kind == .repeatedNGrams }?.isElevated == true)
    #expect(report.signals.first { $0.kind == .repeatedSentenceOpenings }?.isElevated == true)
}

@Test("Keeps exact hidden Unicode findings separate from statistical scoring")
func watermarkProbeSeparatesHiddenUnicode() {
    let source = String(repeating: "Ordinary visible words vary across this local sample. ", count: 12) + "hidden\u{200B}mark"
    let report = WatermarkProbeAnalyzer.analyze(source)

    #expect(report.hiddenUnicodeFindingCount == 1)
    #expect(report.assessment != .insufficientText)
}

@Test("Research links never contain analyzed text")
func watermarkProbeResearchLinkIsPrivate() throws {
    let privateMarker = "PRIVATE-WATERMARK-SAMPLE"
    let report = WatermarkProbeAnalyzer.analyze(String(repeating: "\(privateMarker) ordinary prose. ", count: 40))

    for signal in report.signals {
        let url = try #require(signal.kind.researchURL)
        #expect(url.host == "duckduckgo.com")
        #expect(!url.absoluteString.contains(privateMarker))
    }
}

@Test("Copyable probe report preserves the limitation")
func watermarkProbeReportIsQualified() {
    let report = WatermarkProbeAnalyzer.analyze(String(repeating: "A visible sample contains enough ordinary words for local analysis. ", count: 12))
    let formatted = FindingReportFormatter.watermarkProbeReport(report, language: .english)

    #expect(formatted.contains("keyless heuristic screen"))
    #expect(formatted.contains("not proof of watermarking or authorship"))
    #expect(formatted.contains("Heuristic score"))
    #expect(formatted.contains("Provider watermark: Not testable without a compatible detector"))
    #expect(formatted.contains("Integrated provider detectors: 0"))
    #expect(formatted.contains("Signal Sieve — Surface Regularity"))
}
