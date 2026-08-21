// SPDX-License-Identifier: MPL-2.0
import AppKit
import SwiftUI
import SignalSieveCore

struct WatermarkProbeView: View {
    let report: WatermarkProbeReport
    let language: AppLanguage
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(
            title: localized("Surface Regularity"),
            subtitle: localized("Keyless stylometric screen of visible writing patterns"),
            systemImage: "waveform.badge.magnifyingglass",
            doneTitle: localized("Done"),
            onDone: { dismiss() },
            headerBadge: localized("Experimental"),
            footerNote: localized("Processed locally · no text is uploaded"),
            content: { probeContent },
            footer: {
                Button(localized("Copy Findings"), systemImage: "doc.on.doc") {
                    onCopy(FindingReportFormatter.watermarkProbeReport(report, language: language))
                }
                .sieveSheetButton(.primary)
            }
        )
        .frame(minWidth: 700, minHeight: 640)
    }

    private var probeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                assessmentCard
                exactLayerCard
                providerStatusCard
                sampleCard
                signalCards
                limitationCard
            }
        }
    }

    private var assessmentCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: assessmentIcon)
                .font(.title2)
                .foregroundStyle(assessmentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.text(report.assessment.rawValue, language: language))
                    .font(.headline)
                Text(assessmentDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if report.hasEnoughText {
                    HStack(spacing: 8) {
                        ProgressView(value: report.heuristicScore)
                            .tint(assessmentColor)
                        Text(formatted(
                            "%d%% heuristic score",
                            Int((report.heuristicScore * 100).rounded())
                        ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(14)
        .background(assessmentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(assessmentColor.opacity(0.45), lineWidth: 1)
        }
    }

    private var exactLayerCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: report.hiddenUnicodeFindingCount == 0 ? "checkmark.shield" : "exclamationmark.triangle")
                .foregroundStyle(report.hiddenUnicodeFindingCount == 0 ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("Exact text layer"))
                    .font(.headline)
                if report.hiddenUnicodeFindingCount == 0 {
                    Text(localized("No hidden Unicode elements were found. Statistical word-choice signals are a separate layer."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(formatted(
                        "%d hidden Unicode finding(s) were detected separately. Review the main Findings panel.",
                        report.hiddenUnicodeFindingCount
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private var sampleCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(localized("Sample sufficiency"))
                    .font(.headline)
                Spacer()
                Text(formatted("%d words · %d sentences", report.tokenCount, report.sentenceCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: min(Double(report.tokenCount), Double(report.recommendedTokenCount)),
                total: Double(report.recommendedTokenCount)
            )
            .tint(report.hasEnoughText ? .blue : .yellow)
            Text(formatted(
                "At least %d words are required; %d or more produce a more stable screen.",
                report.minimumTokenCount,
                report.recommendedTokenCount
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private var providerStatusCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.diamond")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("Provider watermark status"))
                    .font(.headline)
                Text(localized("Not testable without a compatible detector"))
                    .font(.subheadline.weight(.medium))
                Text(localized("Surface regularity cannot confirm or rule out a provider watermark."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider().padding(.vertical, 4)
                Text(localized("Provider profiles"))
                    .font(.subheadline.weight(.semibold))
                ForEach(ProviderWatermarkRegistry.profiles) { profile in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(profile.provider) · \(profile.product)")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button {
                                NSWorkspace.shared.open(profile.officialDocumentationURL)
                            } label: {
                                Label(
                                    localized("Official provider documentation"),
                                    systemImage: "arrow.up.right.square"
                                )
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                        Text(localized(profile.mechanism.rawValue))
                            .font(.caption)
                        Text(localized(profile.detectorAvailability.rawValue))
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(localized(profile.scopeNote))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatted(
                            "Effective from %@ · profile verified %@",
                            profile.effectiveFrom ?? localized("Unknown"),
                            profile.lastVerified
                        ))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private var signalCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("Observable signals"))
                .font(.headline)
            ForEach(report.signals) { signal in
                Button {
                    if let url = signal.kind.researchURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(
                                AppLocalization.text(signal.kind.rawValue, language: language),
                                systemImage: signal.isElevated ? "exclamationmark.circle.fill" : "circle"
                            )
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(signal.isElevated ? .orange : .primary)
                            Spacer()
                            if signal.isAvailable {
                                Text(formatted("%d%% indicator", Int((signal.strength * 100).rounded())))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(localized("Insufficient structure"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                        Text(AppLocalization.watermarkSignalDetail(signal, language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: signal.isAvailable ? signal.strength : 0)
                            .tint(signal.isElevated ? .orange : .blue)
                    }
                    .padding(11)
                    .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(localized("Open a general research query. The analyzed text is never included."))
            }
        }
    }

    private var limitationCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(localized("What this result means"), systemImage: "info.circle.fill")
                .font(.headline)
            Text(localized("This score is a heuristic, not a probability. It can flag human writing and can miss a real watermark."))
                .font(.subheadline)
            Text(localized("A provider-specific watermark can only be confirmed with a compatible detector and validated provider-specific parameters."))
                .font(.subheadline)
            Text(localized("Shortening, paraphrasing, or back-translation can weaken some published schemes, but none is a guaranteed scrub."))
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .padding(14)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var assessmentDetail: String {
        switch report.assessment {
        case .insufficientText:
            localized("The sample is too short for this screen. No statistical conclusion was made.")
        case .noElevatedRegularity:
            localized("The measured surface features did not cross the reporting threshold. This does not rule out a provider watermark.")
        case .someRegularity:
            localized("Multiple surface features are unusually regular. This deserves review but does not identify a watermark or author.")
        case .elevatedRegularity:
            localized("Several independent surface features are elevated. Treat this as a triage signal, not confirmation.")
        }
    }

    private var assessmentColor: Color {
        switch report.assessment {
        case .insufficientText: .yellow
        case .noElevatedRegularity: .blue
        case .someRegularity: .yellow
        case .elevatedRegularity: .orange
        }
    }

    private var assessmentIcon: String {
        switch report.assessment {
        case .insufficientText: "text.badge.xmark"
        case .noElevatedRegularity: "waveform.badge.magnifyingglass"
        case .someRegularity: "waveform.badge.magnifyingglass"
        case .elevatedRegularity: "exclamationmark.triangle.fill"
        }
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
