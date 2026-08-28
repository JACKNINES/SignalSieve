// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

struct ClipboardHistoryView: View {
    let entries: [ClipboardHistoryEntry]
    let language: AppLanguage
    let onOpen: (ClipboardHistoryEntry) -> Void
    let onCopyCleanResult: (ClipboardHistoryEntry) -> Void
    let onRestoreOriginal: (ClipboardHistoryEntry) -> Void
    let onDelete: (ClipboardHistoryEntry) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(
            title: localized("Copy History"),
            subtitle: localized("Session only · stored locally in memory"),
            systemImage: "clock.arrow.circlepath",
            doneTitle: localized("Done"),
            onDone: { dismiss() },
            headerBadge: formatted("%d copies", entries.count),
            footerNote: localized("The source is inferred from the active app. Browser tab and page URLs are not available. Concealed and transient copies are not stored."),
            content: { historyContent },
            footer: {
                Button(localized("Clear History"), role: .destructive, action: onClear)
                    .sieveSheetButton(.destructive)
                    .disabled(entries.isEmpty)
            }
        )
        .frame(minWidth: 740, minHeight: 640)
    }

    @ViewBuilder
    private var historyContent: some View {
        if entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(entries) { entry in
                        historyCard(entry)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(localized("No copies recorded this session"))
                .font(.headline)
            Text(localized("While Active Guard is on, new text copies appear here with their time and probable source application."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func historyCard(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                sourceIcon(entry)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.sourceApplicationName ?? localized("Unknown application"))
                        .font(.headline)
                    Text(localized("Probable source application"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(dateText(entry.capturedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(entry.visiblePreview)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))

            HStack(spacing: 7) {
                if entry.hiddenUnicodeCount > 0 {
                    badge(formatted("%d hidden Unicode", entry.hiddenUnicodeCount), color: .orange)
                }
                if entry.codeRiskCount > 0 {
                    badge(formatted("%d code risks", entry.codeRiskCount), color: .red)
                }
                if entry.trackedLinkCount > 0 {
                    badge(formatted("%d tracked links", entry.trackedLinkCount), color: .orange)
                }
                if let binaryKind = entry.binaryKind {
                    badge(AppLocalization.text(binaryKind.rawValue, language: language), color: .yellow)
                }
                if entry.scamSignalCount > 0 {
                    badge(
                        formatted("Possible scam · %d signal(s)", entry.scamSignalCount),
                        color: entry.scamThreatLevel == .high ? .red : .orange
                    )
                }
                if !entry.hasKnownRisk {
                    badge(localized("No known risk"), color: .green)
                }
                if let audit = entry.automaticCleaningAudit,
                   audit.originalAlertCount > 0 {
                    automaticCleaningBadge(audit)
                }
                if entry.wasAutomaticallyCleaned,
                   entry.automaticCleaningAudit?.didWriteCleanedText != true {
                    badge(localized("Link auto-cleaned"), color: .blue)
                }
                Spacer()
            }

            if let audit = entry.automaticCleaningAudit,
               audit.originalAlertCount > 0 {
                automaticCleaningSummary(audit)
            }
            if let audit = entry.automaticCleaningAudit {
                cleanReceiptSummary(audit.receipt)
            }

            HStack {
                Text(formatted("%d characters", entry.originalCharacterCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.isTruncated {
                    Label(localized("Stored text truncated"), systemImage: "scissors")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if entry.cleanedText != nil {
                    Button(localized("Copy Clean Result")) {
                        onCopyCleanResult(entry)
                    }
                    .help(localized("Copies the cleaned text only if the clipboard still matches this history item."))
                    Button(localized("Restore Original")) {
                        onRestoreOriginal(entry)
                    }
                    .disabled(entry.isTruncated)
                    .help(localized("Restores the original text only if the clipboard still holds the clean result."))
                }
                Button(localized("Open in Signal Sieve"), systemImage: "arrow.up.left.and.arrow.down.right") {
                    onOpen(entry)
                    dismiss()
                }
                Button(role: .destructive) {
                    onDelete(entry)
                } label: {
                    Image(systemName: "trash")
                }
                .help(localized("Delete from history"))
                .accessibilityLabel(localized("Delete from history"))
            }
        }
        .padding(14)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(entry.hasKnownRisk ? Color.orange.opacity(0.30) : Color.secondary.opacity(0.18))
        }
    }


    private func sourceIcon(_ entry: ClipboardHistoryEntry) -> some View {
        Group {
            if let identifier = entry.sourceBundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: 32, height: 32)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private func automaticCleaningBadge(
        _ audit: ClipboardAutomaticCleaningAudit
    ) -> some View {
        let mode = protocolName(audit.selectedProtocol)
        switch audit.outcome {
        case .cleanedAllDetectedAlerts:
            badge(formatted("%@ · alerts cleaned successfully", mode), color: .green)
        case .cleanedSomeDetectedAlerts:
            badge(formatted("%@ · some alerts cleaned", mode), color: .orange)
        case .alertsRemain:
            badge(formatted("%@ · alerts remain", mode), color: .red)
        case .skipped:
            badge(
                formatted("%@ · cleaning skipped", mode),
                color: audit.redRiskRemains ? .red : .orange
            )
        case .noDetectedAlerts:
            EmptyView()
        }
    }

    private func automaticCleaningSummary(
        _ audit: ClipboardAutomaticCleaningAudit
    ) -> some View {
        let mode = protocolName(audit.selectedProtocol)
        let successful = audit.outcome == .cleanedAllDetectedAlerts
        let text = successful
            ? formatted(
                "%@ reanalysis: %d original alert(s), none remaining after automatic cleaning.",
                mode,
                audit.originalAlertCount
            )
            : formatted(
                "%@ reanalysis: %d original alert(s), %d remaining after automatic cleaning.",
                mode,
                audit.originalAlertCount,
                audit.remainingAlertCount
            )
        let color: Color = successful ? .green : (audit.redRiskRemains ? .red : .orange)
        return Label(
            text,
            systemImage: successful ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
        )
        .font(.caption)
        .foregroundStyle(color)
    }

    private func cleanReceiptSummary(
        _ receipt: ClipboardCleanReceipt
    ) -> some View {
        let color: Color
        let title: String
        switch receipt.verdict {
        case .noSupportedRiskRemains:
            color = .green
            title = localized("Clean Receipt: no supported cleaning risks remain")
        case .cleanedSourceNeedsReview:
            color = .orange
            title = localized("Clean Receipt: cleaned, but review the source")
        case .riskRemainsDoNotShare:
            color = .red
            title = localized("Clean Receipt: risk remains — do not share")
        }
        return VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "checklist")
                .font(.caption.weight(.semibold))
            Text(formatted(
                "Protocol: %@",
                protocolName(receipt.selectedProtocol)
            ))
            Text(formatted(
                "Original alerts: %d · highest severity: %@",
                receipt.originalAlertCount,
                priorityName(receipt.originalPriority)
            ))
            Text(formatted(
                "Remaining alerts: %d · highest severity: %@",
                receipt.remainingAlertCount,
                priorityName(receipt.remainingPriority)
            ))
        }
        .font(.caption)
        .foregroundStyle(color)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func protocolName(_ selection: ClipboardAutomationProtocol) -> String {
        switch selection {
        case .reviewAll:
            localized("Review all enabled warnings")
        case .safeClean:
            localized("Safe Clean")
        case .strictClean:
            localized("Strict Clean")
        case .visualTransfer:
            localized("Visual Transfer")
        }
    }

    private func priorityName(_ priority: ClipboardAlertPriority) -> String {
        switch priority {
        case .standard:
            localized("standard")
        case .elevated:
            localized("elevated")
        case .high:
            localized("high")
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
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
