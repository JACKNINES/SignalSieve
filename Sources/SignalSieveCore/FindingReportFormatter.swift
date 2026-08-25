// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Produces plain-text findings that are safe to paste into an issue, message,
/// or audit log. Invisible scalars are rendered as explicit U+ tokens instead
/// of being copied back to the pasteboard invisibly.
public enum FindingReportFormatter {
    public static func hiddenFinding(
        _ finding: HiddenElement,
        language: AppLanguage
    ) -> String {
        [
            "\(finding.codePoint) — \(AppLocalization.hiddenKind(finding.kind, language: language))",
            field("Risk", AppLocalization.riskLabel(finding.riskLevel, language: language), language),
            field("Context", AppLocalization.hiddenContext(finding.context, language: language), language),
            field(
                "Evidence confidence",
                AppLocalization.evidenceConfidenceLabel(finding.evidenceConfidence, language: language),
                language
            ),
            field("Name", finding.displayName, language),
            field("Scalar position", String(finding.scalarPosition), language),
            field("UTF-16 position", String(finding.utf16Position), language)
        ].joined(separator: "\n")
    }

    public static func hiddenReport(
        _ inspection: TextInspection,
        language: AppLanguage
    ) -> String {
        report(
            title: localized("Signal Sieve — Hidden Unicode Findings", language),
            summary: countSummary(inspection.totalFindingCount, language),
            entries: inspection.findings.map { hiddenFinding($0, language: language) }
                + (inspection.omittedFindingCount > 0
                    ? [localized("Additional findings were counted but omitted from this bounded report.", language)]
                    : [])
        )
    }

    public static func revealedFragment(
        _ fragment: RevealedInvisibleFragment,
        language: AppLanguage
    ) -> String {
        var lines = [
            localized(fragment.presentation.rawValue, language),
            field("Location", AppLocalization.format(
                "line %d, column %d",
                language: language,
                fragment.line,
                fragment.column
            ), language),
            field("Invisible scalars", String(fragment.hiddenScalarCount), language)
        ]
        if let binary = fragment.zeroWidthBinary {
            lines.append(field(
                "Bit mapping",
                "\(binary.zeroCodePoint) = 0 · \(binary.oneCodePoint) = 1",
                language
            ))
            lines.append(field("Binary", binary.bits + (binary.isPreviewTruncated ? "…" : ""), language))
            if !binary.isByteAligned {
                lines.append(field("Missing bits", String(binary.missingBitCount), language))
            }
            if let equivalence = binary.probableTextEquivalence {
                lines.append(field(
                    "Probable detected equivalence",
                    "\"\(visible(equivalence.text))\"",
                    language
                ))
                lines.append(field("Characters", String(equivalence.characterCount), language))
                lines.append(field(
                    "Unicode code points",
                    equivalence.unicodeCodePoints.joined(separator: " "),
                    language
                ))
                lines.append(field(
                    "Confidence",
                    "\(localized(equivalence.confidence.rawValue, language)) (\(equivalence.similarityPercent)%)",
                    language
                ))
                lines.append(field(
                    "Binary edit distance",
                    AppLocalization.format(
                        "%d bit edits",
                        language: language,
                        equivalence.bitEditDistance
                    ),
                    language
                ))
                lines.append(field(
                    "Method",
                    localized("Local known-payload catalog match", language),
                    language
                ))
                lines.append(localized(
                    "Approximate match; this is not an exact byte-for-byte decode.",
                    language
                ))
            }
        }
        lines.append(field("Revealed content", visible(fragment.text), language))
        return lines.joined(separator: "\n")
    }

    public static func revealedReport(
        _ fragments: [RevealedInvisibleFragment],
        language: AppLanguage
    ) -> String {
        report(
            title: localized("Signal Sieve — Revealed Hidden Content", language),
            summary: field("Revealed fragments", String(fragments.count), language),
            entries: fragments.map { revealedFragment($0, language: language) }
        )
    }

    public static func codeFinding(
        _ finding: CodeGuardFinding,
        language: AppLanguage
    ) -> String {
        [
            "\(finding.codePoint) — \(AppLocalization.codeKind(finding.kind, language: language))",
            field("Risk", AppLocalization.riskLabel(finding.kind.riskLevel, language: language), language),
            field(
                "Evidence confidence",
                AppLocalization.evidenceConfidenceLabel(finding.evidenceConfidence, language: language),
                language
            ),
            field("Name", finding.displayName, language),
            field("Location", AppLocalization.format("line %d, column %d", language: language, finding.line, finding.column), language),
            field("Details", AppLocalization.codeDetail(finding.kind, language: language), language)
        ].joined(separator: "\n")
    }

    public static func codeReport(
        _ analysis: CodeGuardAnalysis,
        language: AppLanguage
    ) -> String {
        let detected = analysis.detectedLanguage.isEmpty
            ? localized("Source code", language)
            : analysis.detectedLanguage
        return report(
            title: localized("Signal Sieve — Code Guard Findings", language),
            summary: [
                field("Detected language", detected, language),
                field("Confidence", localized(analysis.languageConfidence.rawValue, language), language),
                countSummary(analysis.findings.count, language)
            ].joined(separator: "\n"),
            entries: analysis.findings.map { codeFinding($0, language: language) }
        )
    }

    public static func binaryFinding(
        _ analysis: BinaryContentAnalysis,
        language: AppLanguage
    ) -> String {
        report(
            title: localized("Signal Sieve — Binary Guard Finding", language),
            summary: [
                field("Type", localized(analysis.displayName, language), language),
                field("Confidence", localized(analysis.confidence.rawValue, language), language),
                field("Approximate bytes", String(analysis.byteCount), language),
                field("Evidence", visible(analysis.evidence), language)
            ].joined(separator: "\n"),
            entries: []
        )
    }

    public static func patternFinding(
        _ finding: PatternFinding,
        language: AppLanguage
    ) -> String {
        [
            AppLocalization.patternKind(finding.kind, language: language),
            field("Pattern", visible(AppLocalization.patternValue(finding, language: language)), language),
            field("Matches", String(finding.matchingSampleCount), language),
            field("Signal strength", "\(Int((finding.confidence * 100).rounded()))%", language),
            field(
                "Evidence confidence",
                AppLocalization.evidenceConfidenceLabel(finding.evidenceConfidence, language: language),
                language
            ),
            field("Details", visible(AppLocalization.patternDetail(finding, language: language)), language)
        ].joined(separator: "\n")
    }

    public static func patternReport(
        _ reportValue: PatternReport,
        language: AppLanguage
    ) -> String {
        report(
            title: localized("Signal Sieve — Pattern Findings", language),
            summary: [
                field("Samples", String(reportValue.sampleCount), language),
                countSummary(reportValue.findings.count, language)
            ].joined(separator: "\n"),
            entries: reportValue.findings.map { patternFinding($0, language: language) }
        )
    }

    public static func watermarkProbeSignal(
        _ signal: WatermarkProbeSignal,
        language: AppLanguage
    ) -> String {
        [
            AppLocalization.text(signal.kind.rawValue, language: language),
            field(
                "Indicator strength",
                signal.isAvailable
                    ? "\(Int((signal.strength * 100).rounded()))%"
                    : localized("Not available", language),
                language
            ),
            field(
                "Observed value",
                signal.isAvailable
                    ? "\(Int((signal.observedValue * 100).rounded()))%"
                    : localized("Not available", language),
                language
            ),
            field(
                "Details",
                AppLocalization.watermarkSignalDetail(signal, language: language),
                language
            )
        ].joined(separator: "\n")
    }

    public static func watermarkProbeReport(
        _ reportValue: WatermarkProbeReport,
        language: AppLanguage
    ) -> String {
        let summary = [
            field("Assessment", localized(reportValue.assessment.rawValue, language), language),
            field("Words", String(reportValue.tokenCount), language),
            field("Sentences", String(reportValue.sentenceCount), language),
            field(
                "Heuristic score",
                "\(Int((reportValue.heuristicScore * 100).rounded()))%",
                language
            ),
            field("Elevated indicators", String(reportValue.elevatedSignalCount), language),
            field("Hidden Unicode findings", String(reportValue.hiddenUnicodeFindingCount), language),
            field(
                "Evidence confidence",
                localized(EvidenceConfidence.heuristic.rawValue, language),
                language
            ),
            field(
                "Provider watermark",
                localized("Not testable without a compatible detector", language),
                language
            ),
            field(
                "Integrated provider detectors",
                String(ProviderWatermarkRegistry.integratedAdapterProfileIDs.count),
                language
            ),
            localized(
                "This is a keyless heuristic screen, not proof of watermarking or authorship.",
                language
            )
        ].joined(separator: "\n")

        return report(
            title: localized("Signal Sieve — Surface Regularity", language),
            summary: summary,
            entries: reportValue.signals.map { watermarkProbeSignal($0, language: language) }
        )
    }

    public static func fileProvenanceFinding(
        _ finding: FileProvenanceFinding,
        language: AppLanguage
    ) -> String {
        [
            localized(finding.kind.rawValue, language),
            field(
                "Evidence confidence",
                AppLocalization.evidenceConfidenceLabel(
                    finding.evidenceConfidence,
                    language: language
                ),
                language
            ),
            field("Evidence", finding.evidence, language),
            field("Details", localized(finding.detail, language), language)
        ].joined(separator: "\n")
    }

    public static func fileProvenanceReport(
        _ reportValue: FileProvenanceReport,
        language: AppLanguage
    ) -> String {
        let c2paStatus = reportValue.containsC2PAContainer
            ? localized("Container detected · cryptographic validation not performed", language)
            : localized("No embedded C2PA container detected in the scanned data", language)
        return report(
            title: localized("Signal Sieve — File Provenance Findings", language),
            summary: [
                field("File", reportValue.fileName, language),
                field("Type", localized(reportValue.format.rawValue, language), language),
                field("File bytes", String(reportValue.fileSize), language),
                field("Scanned bytes", String(reportValue.scannedByteCount), language),
                field("C2PA status", c2paStatus, language),
                localized(
                    "Read-only inspection. Absence of an embedded container does not rule out external manifests, soft bindings, or invisible pixel/text marks.",
                    language
                )
            ].joined(separator: "\n"),
            entries: reportValue.findings.map {
                fileProvenanceFinding($0, language: language)
            }
        )
    }

    public static func rewriteIntegrityFinding(
        _ finding: RewriteIntegrityFinding,
        language: AppLanguage
    ) -> String {
        [
            "\(localized(finding.kind.rawValue, language)) — \(localized(finding.change.rawValue, language))",
            field(
                "Evidence confidence",
                AppLocalization.evidenceConfidenceLabel(
                    finding.evidenceConfidence,
                    language: language
                ),
                language
            ),
            field("Value", visible(finding.value), language)
        ].joined(separator: "\n")
    }

    public static func rewriteIntegrityReport(
        _ reportValue: RewriteIntegrityReport,
        language: AppLanguage
    ) -> String {
        report(
            title: localized("Signal Sieve — Rewrite Integrity Findings", language),
            summary: [
                field("Assessment", localized(reportValue.assessment.rawValue, language), language),
                field("Original words", String(reportValue.originalTokenCount), language),
                field("Candidate words", String(reportValue.candidateTokenCount), language),
                field(
                    "Lexical divergence",
                    "\(Int((reportValue.lexicalDivergence * 100).rounded()))%",
                    language
                ),
                field(
                    "Length ratio",
                    "\(Int((reportValue.lengthRatio * 100).rounded()))%",
                    language
                ),
                field(
                    "Semantic equivalence",
                    AppLocalization.evidenceConfidenceLabel(
                        reportValue.semanticEquivalenceConfidence,
                        language: language
                    ),
                    language
                ),
                localized(
                    "This comparison does not generate a rewrite and does not prove that meaning or watermark status was preserved.",
                    language
                )
            ].joined(separator: "\n"),
            entries: reportValue.findings.map {
                rewriteIntegrityFinding($0, language: language)
            }
        )
    }

    public static func vaccineFile(
        _ finding: VaccineFileFinding,
        language: AppLanguage
    ) -> String {
        var lines = [finding.relativePath]
        if finding.isTextFile {
            lines.append(field(
                "Encoding",
                "\(finding.textEncoding.rawValue)\(finding.hasByteOrderMark ? " + BOM" : "")",
                language
            ))
        }
        lines.append(contentsOf: [
            field("Unicode findings", String(finding.unicodeFindingCount), language),
            field("Safe changes", String(finding.sanitizableFindingCount), language),
            field("Review only", String(finding.reviewOnlyFindingCount), language)
        ])
        if let detectedLanguage = finding.detectedLanguage {
            lines.append(field("Detected language", detectedLanguage, language))
        }
        if let kind = finding.encodedDataKind {
            lines.append(field("Encoded data", localized(kind.rawValue, language), language))
        }
        if let provenance = finding.provenanceReport {
            lines.append(field("File format", localized(provenance.format.rawValue, language), language))
            lines.append(field("Metadata findings", String(provenance.findings.count), language))
            for metadataFinding in provenance.findings {
                lines.append("  \(localized(metadataFinding.kind.rawValue, language)) · \(localized(metadataFinding.evidence, language))")
            }
        }
        for fragment in finding.revealedFragments {
            let location = AppLocalization.format(
                "line %d, column %d",
                language: language,
                fragment.line,
                fragment.column
            )
            lines.append("  \(fragment.codePoint) · \(location) · \(visible(fragment.text))")
        }
        if let preview = finding.changePreview {
            lines.append(field("Before", visible(preview.before), language))
            lines.append(field("After", visible(preview.after), language))
        }
        return lines.joined(separator: "\n")
    }

    public static func vaccineReport(
        _ reportValue: VaccineScanReport,
        language: AppLanguage
    ) -> String {
        report(
            title: localized("Signal Sieve — Vaccine Findings", language),
            summary: [
                field("Files scanned", String(reportValue.scannedFileCount), language),
                field("Metadata files scanned", String(reportValue.provenanceScannedFileCount), language),
                field("Metadata findings", String(reportValue.totalMetadataFindingCount), language),
                field("Files with findings", String(reportValue.affectedFileCount), language),
                field("Ignored paths", String(reportValue.ignoredPathCount), language)
            ].joined(separator: "\n"),
            entries: reportValue.findings.map { vaccineFile($0, language: language) }
        )
    }

    public static func signatureGroup(
        _ group: SignatureGroup,
        language: AppLanguage
    ) -> String {
        var lines = [
            "\(group.id) — \(localized(group.technique.rawValue, language))",
            field("Disposition", localized(group.disposition.rawValue, language), language),
            field("Occurrences", String(group.occurrenceCount), language),
            field("Files", String(group.fileCount), language)
        ]
        if let codePoint = group.codePoint {
            lines.append(field("Code point", codePoint, language))
        }
        if let fragment = group.revealedFragment {
            lines.append(field("Fragment", visible(fragment), language))
        }
        for occurrence in group.occurrences {
            let location = occurrence.line > 0
                ? AppLocalization.format("line %d, column %d", language: language, occurrence.line, occurrence.column)
                : localized("Location unavailable", language)
            lines.append("  • \(occurrence.relativePath) · \(location) · \(occurrence.encoding.rawValue)")
            if let preview = occurrence.changePreview {
                lines.append("    − \(visible(preview.before))")
                lines.append("    + \(visible(preview.after))")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func signatureReport(
        _ reportValue: SignatureHuntReport,
        language: AppLanguage
    ) -> String {
        report(
            title: localized("Signal Sieve — Signature Hunt Findings", language),
            summary: [
                field("Signature groups", String(reportValue.groups.count), language),
                field("Occurrences", String(reportValue.totalOccurrenceCount), language),
                field("Files scanned", String(reportValue.vaccineReport.scannedFileCount), language),
                field("Ignored paths", String(reportValue.vaccineReport.ignoredPathCount), language)
            ].joined(separator: "\n"),
            entries: reportValue.groups.map { signatureGroup($0, language: language) }
        )
    }

    public static func identifierReport(
        _ analysis: OpaqueIdentifierAnalysis,
        language: AppLanguage
    ) -> String {
        report(
            title: localized("Signal Sieve — Opaque Identifier Findings", language),
            summary: countSummary(analysis.findings.count, language),
            entries: analysis.findings.map { finding in
                [
                    field("Type", localized(finding.kind.rawValue, language), language),
                    field("Value", finding.value, language),
                    field("Line", String(finding.line), language),
                    field("Column", String(finding.column), language)
                ].joined(separator: "\n")
            }
        )
    }

    public static func scamReport(
        _ analysis: ScamAttemptAnalysis,
        language: AppLanguage
    ) -> String {
        report(
            title: localized("Signal Sieve — Possible Scam Findings", language),
            summary: [
                field("Risk score", "\(analysis.score)/100", language),
                field("Assessment", localized(analysis.threatLevel.rawValue, language), language),
                localized("This is a local risk estimate, not proof of fraud. No link was opened or contacted.", language)
            ].joined(separator: "\n"),
            entries: analysis.signals.map { signal in
                [
                    localized(signal.kind.rawValue, language),
                    field("Evidence", signal.evidence, language),
                    field(
                        "Reason",
                        AppLocalization.scamSignalDetail(signal.kind, language: language),
                        language
                    )
                ].joined(separator: "\n")
            }
        )
    }

    public static func linkSanitizationFinding(
        _ finding: LinkSanitizationFinding,
        language: AppLanguage
    ) -> String {
        var lines = [
            "\(localized(finding.platform.rawValue, language)) — \(localized(finding.treatment.rawValue, language))",
            field("Mechanism", localized(finding.mechanism.rawValue, language), language)
        ]
        if !finding.parameterNames.isEmpty {
            lines.append(field(
                "Parameters",
                finding.parameterNames.sorted().joined(separator: ", "),
                language
            ))
        }
        lines.append(field("Original", finding.originalURL, language))
        lines.append(field("Result", finding.resultingURL, language))
        return lines.joined(separator: "\n")
    }

    public static func linkSanitizationReport(
        _ result: URLCleaningResult,
        language: AppLanguage
    ) -> String {
        report(
            title: localized("Signal Sieve — Link Sanitization Report", language),
            summary: [
                field("Links analyzed", String(result.linksFound), language),
                field("Links changed", String(result.linksChanged), language),
                field("Parameters removed", String(result.removedParameterCount), language),
                field("Opaque redirects not resolved", String(result.unresolvedRedirectCount), language),
                localized("No network request was made.", language),
                localized(
                    "Pixels, cookies, fingerprinting, server-side APIs, and in-app telemetry are outside clipboard scope.",
                    language
                )
            ].joined(separator: "\n"),
            entries: result.findings.map {
                linkSanitizationFinding($0, language: language)
            }
        )
    }

    private static func report(title: String, summary: String, entries: [String]) -> String {
        ([title, summary] + entries.enumerated().map { index, entry in
            "\(index + 1). \(entry)"
        }).joined(separator: "\n\n")
    }

    private static func countSummary(_ count: Int, _ language: AppLanguage) -> String {
        field("Findings", String(count), language)
    }

    private static func field(_ englishLabel: String, _ value: String, _ language: AppLanguage) -> String {
        "\(localized(englishLabel, language)): \(value)"
    }

    private static func localized(_ english: String, _ language: AppLanguage) -> String {
        AppLocalization.text(english, language: language)
    }

    private static func visible(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            guard HiddenTextAnalyzer.classify(scalar) != nil else { return String(scalar) }
            return String(format: "⟦U+%04X⟧", scalar.value)
        }.joined()
    }
}
