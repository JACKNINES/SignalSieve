// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import SwiftUI

struct LinkCoverageView: View {
    let report: URLCleaningResult
    let language: AppLanguage
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SheetScaffold(
            title: localized("Link Tracking Coverage"),
            subtitle: localized("20 prioritized platforms · offline rules only"),
            systemImage: "link.badge.plus",
            doneTitle: localized("Done"),
            onDone: { dismiss() },
            headerBadge: localized("20 platforms"),
            footerNote: localized("Signal Sieve never opens a link to inspect or clean it."),
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        analysisSection
                        treatmentLegend
                        coverageMatrix
                        scopeBoundary
                    }
                }
            },
            footer: {
                Button(localized("Copy Link Report"), systemImage: "doc.on.doc") {
                    onCopy(FindingReportFormatter.linkSanitizationReport(report, language: language))
                }
                .sieveSheetButton(.primary)
                .disabled(report.linksFound == 0)
            }
        )
        .frame(minWidth: 850, idealWidth: 940, minHeight: 620, idealHeight: 720)
    }

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Last link analysis", image: "doc.text.magnifyingglass")
            if report.linksFound == 0 {
                Text(localized("No links have been analyzed yet."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 10) {
                    SheetStatTile(value: "\(report.linksFound)", label: localized("Links analyzed"))
                    SheetStatTile(value: "\(report.linksChanged)", label: localized("Links changed"))
                    SheetStatTile(value: "\(report.removedParameterCount)", label: localized("Parameters removed"))
                    SheetStatTile(value: "\(report.unresolvedRedirectCount)", label: localized("Opaque redirects not resolved"))
                }

                ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
                    findingRow(finding)
                }
            }
        }
    }

    private var treatmentLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Treatment legend", image: "checklist")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 8) {
                ForEach(LinkSanitizationTreatment.allCases, id: \.rawValue) { treatment in
                    HStack(spacing: 8) {
                        Circle().fill(color(for: treatment)).frame(width: 9, height: 9)
                        Text(localized(treatment.rawValue))
                            .font(.caption.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(color(for: treatment).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var coverageMatrix: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Coverage matrix", image: "tablecells")
            VStack(spacing: 0) {
                ForEach(Array(LinkCoverageCatalog.entries.enumerated()), id: \.element.id) { index, entry in
                    coverageRow(entry)
                    if index < LinkCoverageCatalog.entries.count - 1 { Divider() }
                }
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            }
        }
    }

    private var scopeBoundary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(localized("Clipboard boundary"), systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
            Text(localized("Pixels, cookies, fingerprinting, server-side APIs, and in-app telemetry are outside clipboard scope."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(localized("Opaque short links are reported without contacting their server, so their final destination remains unresolved."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func findingRow(_ finding: LinkSanitizationFinding) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(localized(finding.platform.rawValue)).font(.subheadline.weight(.semibold))
                treatmentBadge(finding.treatment)
                Spacer()
                Text(localized(finding.mechanism.rawValue))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !finding.parameterNames.isEmpty {
                Text("\(localized("Parameters")): \(finding.parameterNames.sorted().joined(separator: ", "))")
                    .font(.caption.monospaced())
            }
            Text(finding.originalURL)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if finding.originalURL != finding.resultingURL {
                Text("→ \(finding.resultingURL)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
            }
        }
        .padding(11)
        .background(color(for: finding.treatment).opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(color(for: finding.treatment).opacity(0.28), lineWidth: 1)
        }
    }

    private func coverageRow(_ entry: LinkPlatformCoverage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(localized(entry.platform.rawValue)).font(.subheadline.weight(.semibold))
                    if entry.isPriority {
                        Text(localized("Priority"))
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                    }
                }
                Text(entry.domains.joined(separator: " · "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)

            levelBadge(entry.level)
                .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.capabilities.map { localized($0.rawValue) }.joined(separator: " · "))
                    .font(.caption.weight(.medium))
                Text(localized(entry.limitation))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func sectionTitle(_ key: String, image: String) -> some View {
        Label(localized(key), systemImage: image)
            .font(.headline)
    }

    private func treatmentBadge(_ treatment: LinkSanitizationTreatment) -> some View {
        Text(localized(treatment.rawValue))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color(for: treatment))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color(for: treatment).opacity(0.11), in: Capsule())
    }

    private func levelBadge(_ level: LinkCoverageLevel) -> some View {
        let color: Color = switch level {
        case .strong: .green
        case .targeted: .blue
        case .universalOnly: .orange
        case .detectionOnly: .purple
        }
        return Text(localized(level.rawValue))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(color.opacity(0.11), in: Capsule())
    }

    private func color(for treatment: LinkSanitizationTreatment) -> Color {
        switch treatment {
        case .removed: .green
        case .detectedOfflineUnresolvable: .orange
        case .preservedFunctional: .blue
        case .outsideClipboardScope: .secondary
        }
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.025)
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }
}
