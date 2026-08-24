// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

struct ThreatInsightsView: View {
    let identifiers: OpaqueIdentifierAnalysis
    let scam: ScamAttemptAnalysis
    let adaptive: AdaptiveCopyAnalysis
    let adaptiveSampleCount: Int
    let isAdaptiveEnabled: Bool
    let language: AppLanguage
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(localized("Privacy & Threat Insights"), systemImage: "shield.checkered")
                    .font(.headline)
                Spacer()
                Text(localized("Offline · explainable"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }

            if !scam.signals.isEmpty {
                insightCard(color: scam.isPotentialScam ? (scam.threatLevel == .high ? .red : .orange) : .yellow) {
                    HStack {
                        Label(
                            localized(scam.isPotentialScam ? "Possible scam attempt" : "Scam signals for review"),
                            systemImage: "exclamationmark.bubble.fill"
                        )
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(scam.score)/100")
                            .font(.caption.monospacedDigit().weight(.bold))
                    }
                    Text(localized("This is a risk estimate, not a verdict. SignalSieve did not open or contact any link."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(scam.signals) { signal in
                        Button {
                            if let url = signal.researchURL { NSWorkspace.shared.open(url) }
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(AppLocalization.text(signal.kind.rawValue, language: language))
                                        .font(.caption.weight(.semibold))
                                    Text(signal.evidence).font(.caption.monospaced())
                                    Text(AppLocalization.scamSignalDetail(signal.kind, language: language))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square").font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(localized("Research this signal category without including your copied text."))
                    }
                    copyButton(title: localized("Copy Scam Findings")) {
                        onCopy(FindingReportFormatter.scamReport(scam, language: language))
                    }
                }
            }

            if identifiers.containsIdentifiers {
                insightCard(color: .yellow) {
                    Label(localized("Opaque identifiers"), systemImage: "number.square.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(localized("UUIDs are often legitimate. Review them when a copy should not carry a correlatable identifier."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(identifiers.findings) { finding in
                        Button {
                            if let url = finding.researchURL { NSWorkspace.shared.open(url) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(finding.value).font(.caption.monospaced())
                                    Text(formatted("Line %d · Column %d", finding.line, finding.column))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let version = finding.version {
                                    Text("v\(version)").font(.caption2.monospacedDigit())
                                }
                                Image(systemName: "arrow.up.right.square").font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(localized("Research UUID privacy without including the identifier value."))
                    }
                    copyButton(title: localized("Copy Identifier Findings")) {
                        onCopy(FindingReportFormatter.identifierReport(identifiers, language: language))
                    }
                }
            }

            insightCard(color: adaptive.isAnomalous ? .orange : .blue) {
                HStack {
                    Label(localized("My Usual Copy Patterns"), systemImage: "waveform.path.ecg.rectangle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(formatted("%d learned copy/copies", adaptiveSampleCount))
                        .font(.caption.monospacedDigit())
                }
                Text(localized("SignalSieve learns only measurements such as length and punctuation. It never stores the copied text."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !isAdaptiveEnabled {
                    Text(localized("Learning usual copy patterns is off. New copies are not compared or learned."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if adaptive.isAnomalous {
                    Text(localized("Several writing measurements looked different from your usual copies."))
                        .font(.caption.weight(.semibold))
                    ForEach(adaptive.deviations) { deviation in
                        Text(formatted(
                            "%@ was much %@ than usual",
                            localized(deviation.feature),
                            localized(deviation.direction)
                        ))
                        .font(.caption2)
                    }
                } else if adaptiveSampleCount < AdaptiveCopyModel.minimumTrainingSamples {
                    Text(formatted(
                        "Learning locally · %d more substantial copy/copies needed",
                        max(0, AdaptiveCopyModel.minimumTrainingSamples - adaptiveSampleCount)
                    ))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
                } else {
                    Text(localized("No multi-feature anomaly was found for this copy."))
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func insightCard<Content: View>(
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(color.opacity(0.38), lineWidth: 1)
            }
    }

    private func copyButton(title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(title, systemImage: "doc.on.doc", action: action)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    private func formatted(_ format: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(format),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }
}
