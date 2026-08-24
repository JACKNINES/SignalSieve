// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import SignalSieveCore

struct CovertChannelView: View {
    @Environment(\.dismiss) private var dismiss

    let report: CovertTextChannelReport
    let language: AppLanguage
    let onCopy: (String) -> Void

    var body: some View {
        SheetScaffold(
            title: localized("Advanced Carrier Lab"),
            subtitle: localized("Detect relationships between ordinary-looking spaces, tabs, zero-width alphabets, and confusable letters."),
            systemImage: "point.3.filled.connected.trianglepath.dotted",
            doneTitle: localized("Close"),
            onDone: { dismiss() },
            headerBadge: formatted("%d covert channel(s)", report.findings.count),
            footerNote: localized("A repeated carrier is evidence for review, not proof of provider, authorship, or intent."),
            content: { content },
            footer: {
                Button(localized("Copy Carrier Report"), systemImage: "doc.on.doc") {
                    onCopy(copyableReport)
                }
                .sieveSheetButton(.primary)
                .disabled(report.findings.isEmpty)
            }
        )
        .frame(minWidth: 720, idealWidth: 800, minHeight: 500, idealHeight: 620)
    }

    private var content: some View {
        Group {
            if report.findings.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.green)
                    Text(localized("No patterned carrier found"))
                        .font(.headline)
                    Text(localized("No supported base-4, mixed-space, trailing-whitespace, or periodic confusable channel was detected."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(report.findings) { finding in
                            findingCard(finding)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func findingCard(_ finding: CovertTextChannelFinding) -> some View {
        let color = color(for: finding.riskLevel)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(localized(finding.kind.rawValue), systemImage: "waveform.path.ecg.rectangle")
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                Text(formatted("Line %d · column %d", finding.line, finding.column))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(localized(finding.evidence))
                .font(.callout)
            HStack(spacing: 12) {
                Text(formatted("%d carrier(s)", finding.carrierCount))
                Text(AppLocalization.evidenceConfidenceLabel(finding.confidence, language: language))
                if let periodicity = finding.periodicityPercent {
                    Text(formatted("%d%% regular spacing", periodicity))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            if let payload = finding.decodedPayload {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("Decoded text"))
                        .font(.caption.weight(.semibold))
                    Text(payload)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(12)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.3)) }
    }

    private var copyableReport: String {
        let entries = report.findings.map { finding in
            var lines = [
                finding.kind.rawValue,
                "Risk: \(finding.riskLevel.label)",
                "Location: line \(finding.line), column \(finding.column)",
                "Carriers: \(finding.carrierCount)",
                "Evidence: \(finding.evidence)"
            ]
            if let periodicity = finding.periodicityPercent { lines.append("Regular spacing: \(periodicity)%") }
            if let decoded = finding.decodedPayload { lines.append("Decoded text: \(decoded)") }
            return lines.joined(separator: "\n")
        }
        return (["Signal Sieve — Advanced Carrier Report"] + entries).joined(separator: "\n\n")
    }

    private func color(for risk: HiddenElementRiskLevel) -> Color {
        switch risk {
        case .clear: .green
        case .suspicious: .yellow
        case .medium: .orange
        case .high: .red
        }
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    private func formatted(_ english: String, _ arguments: CVarArg...) -> String {
        String(format: localized(english), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}
