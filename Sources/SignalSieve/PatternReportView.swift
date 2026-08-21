// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import SignalSieveCore

struct PatternReportView: View {
    let report: PatternReport
    let sampleCount: Int
    let language: AppLanguage
    let onClear: () -> Void
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(
            title: localized("Pattern Memory"),
            subtitle: localized("Session-only analysis · nothing is saved to disk"),
            systemImage: "brain.head.profile",
            doneTitle: localized("Done"),
            onDone: { dismiss() },
            headerBadge: formatted("%d samples", sampleCount),
            footerNote: localized("Correlation is not proof of authorship, AI generation, or watermarking."),
            content: { reportContent },
            footer: {
                if !report.findings.isEmpty {
                    Button(localized("Copy Findings"), systemImage: "doc.on.doc") {
                        onCopy(FindingReportFormatter.patternReport(report, language: language))
                    }
                    .sieveSheetButton()
                }
                Button(localized("Clear"), role: .destructive, action: onClear)
                    .sieveSheetButton(.destructive)
                    .disabled(sampleCount == 0)
            }
        )
        .frame(minWidth: 660, minHeight: 540)
    }

    private var reportContent: some View {
        Group {
            if sampleCount < 2 {
                emptyState(
                    icon: "text.badge.plus",
                    title: localized("More samples are needed"),
                    detail: localized("Remember at least two substantial texts to compare repeated wording and structure.")
                )
            } else if report.findings.isEmpty {
                emptyState(
                    icon: "checkmark.shield",
                    title: localized("No strong repetition found"),
                    detail: localized("The current samples do not share patterns that cross SignalSieve's reporting thresholds.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(report.findings) { finding in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(AppLocalization.patternKind(finding.kind, language: language))
                                        .font(.headline)
                                    Spacer()
                                    Label(
                                        AppLocalization.evidenceConfidenceLabel(
                                            finding.evidenceConfidence,
                                            language: language
                                        ),
                                        systemImage: "waveform.badge.magnifyingglass"
                                    )
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                    Text(formatted(
                                        "%d%% signal",
                                        Int((finding.confidence * 100).rounded())
                                    ))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text("“\(AppLocalization.patternValue(finding, language: language))”")
                                    .font(.system(.body, design: .monospaced))
                                Text(AppLocalization.patternDetail(finding, language: language))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                ProgressView(value: finding.confidence)
                                    .tint(.orange)
                            }
                            .padding(.bottom, 28)
                            .padding(14)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .bottomTrailing) {
                                FindingCopyButton(title: localized("Copy Finding")) {
                                    onCopy(FindingReportFormatter.patternFinding(
                                        finding,
                                        language: language
                                    ))
                                }
                                .padding(8)
                            }
                            .contextMenu {
                                Button(localized("Copy Finding"), systemImage: "doc.on.doc") {
                                    onCopy(FindingReportFormatter.patternFinding(
                                        finding,
                                        language: language
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding()
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    private func formatted(_ englishFormat: String, _ arguments: CVarArg...) -> String {
        String(
            format: AppLocalization.text(englishFormat, language: language),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }
}
