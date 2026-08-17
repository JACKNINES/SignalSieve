// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

struct ClipboardHistoryView: View {
    let entries: [ClipboardHistoryEntry]
    let language: AppLanguage
    let onOpen: (ClipboardHistoryEntry) -> Void
    let onDelete: (ClipboardHistoryEntry) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(entries) { entry in
                            historyCard(entry)
                        }
                    }
                    .padding(18)
                }
            }

            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 620)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("Copy History"))
                    .font(.title2.weight(.semibold))
                Text(localized("Session only · stored locally in memory"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatted("%d copies", entries.count))
                .font(.subheadline.monospacedDigit())
            Button(localized("Done")) { dismiss() }
        }
        .padding(20)
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
                if !entry.hasKnownRisk {
                    badge(localized("No known risk"), color: .green)
                }
                if entry.wasAutomaticallyCleaned {
                    badge(localized("Link auto-cleaned"), color: .blue)
                }
                Spacer()
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

    private var footer: some View {
        HStack {
            Label(
                localized("The source is inferred from the active app. Browser tab and page URLs are not available."),
                systemImage: "hand.raised.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(localized("Concealed and transient copies are not stored."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(localized("Clear History"), role: .destructive, action: onClear)
                .disabled(entries.isEmpty)
        }
        .padding(16)
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
