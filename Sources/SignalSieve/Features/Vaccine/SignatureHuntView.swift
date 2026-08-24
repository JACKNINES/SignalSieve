// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

struct SignatureHuntView: View {
    let language: AppLanguage
    let onCopy: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rootURL: URL?
    @State private var report: SignatureHuntReport?
    @State private var result: SignatureNeutralizationResult?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var confirmsNeutralization = false

    var body: some View {
        SheetScaffold(
            title: localized("Signature Hunt"),
            subtitle: localized("Find repeated invisible signatures, preview changes, neutralize, and verify"),
            systemImage: "scope",
            doneTitle: localized("Done"),
            onDone: { dismiss() },
            footerNote: localized("Only deterministic safe signatures are eligible. Review-only findings remain unchanged."),
            content: { huntContent },
            footer: {
                Button(localized("Neutralize Safe Signatures…"), systemImage: "shield.checkered") {
                    confirmsNeutralization = true
                }
                .sieveSheetButton(.primary)
                .disabled(isNeutralizationBlocked)
            }
        )
        .frame(minWidth: 960, minHeight: 720)
        .confirmationDialog(
            localized("Neutralize all safe signatures?"),
            isPresented: $confirmsNeutralization,
            titleVisibility: .visible
        ) {
            Button(localized("Create Backup and Neutralize")) { neutralize() }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("Every affected file is backed up first. Review-only signatures, binaries, cryptographic signatures, and files changed since scanning remain untouched."))
        }
    }

    private var isNeutralizationBlocked: Bool {
        guard let report, !isWorking else { return true }
        return report.safeGroupCount == 0 || report.vaccineReport.isSignalSieveTarget
    }

    private var huntContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            folderControls
            safetyBanner

            if isWorking {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(localized("Hunting signatures locally…"))
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if let report {
                summary(report)
                if report.vaccineReport.isSignalSieveTarget {
                    Label(
                        localized("SignalSieve may be analyzed, but self-neutralization is blocked."),
                        systemImage: "hand.raised.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                }
                signatureList(report)
            } else {
                emptyState
            }

            if let result {
                verificationBanner(result)
            }
        }
    }

    private var folderControls: some View {
        HStack(spacing: 9) {
            Button(localized("Choose Folder…"), systemImage: "folder", action: chooseFolder)
                .sieveSheetButton()
            if let rootURL {
                Text(rootURL.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(localized("No folder selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let report, !report.groups.isEmpty {
                Button(localized("Copy Signatures"), systemImage: "doc.on.doc") {
                    onCopy(FindingReportFormatter.signatureReport(report, language: language))
                }
                .sieveSheetButton()
            }
            Button(localized("Hunt"), systemImage: "scope", action: scan)
                .sieveSheetButton(.primary)
                .disabled(rootURL == nil || isWorking)
        }
    }

    private var safetyBanner: some View {
        Label {
            Text(localized("Signature Hunt never executes revealed content. It preserves text encoding and endianness, honors .signalsieveignore, and uses Vaccine's backup safeguards."))
                .font(.caption)
        } icon: {
            Image(systemName: "lock.shield.fill").foregroundStyle(.green)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(localized("Choose a project to hunt signatures"))
                .font(.headline)
            Text(localized("The first pass is read-only and groups matching signatures across files."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summary(_ report: SignatureHuntReport) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            SheetStatTile(value: "\(report.groups.count)", label: localized("Signature groups"))
            SheetStatTile(value: "\(report.totalOccurrenceCount)", label: localized("Occurrences"))
            SheetStatTile(value: "\(report.safeGroupCount)", label: localized("Safe groups"))
            SheetStatTile(value: "\(report.vaccineReport.scannedFileCount)", label: localized("Files scanned"))
            SheetStatTile(value: "\(report.vaccineReport.ignoredPathCount)", label: localized("Ignored paths"))
        }
    }

    private func signatureList(_ report: SignatureHuntReport) -> some View {
        Group {
            if report.groups.isEmpty {
                Label(localized("No signatures found in scanned text files."), systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(report.groups) { group in
                            signatureCard(group)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func signatureCard(_ group: SignatureGroup) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 9) {
                if let fragment = group.revealedFragment {
                    Text("“\(fragment)”")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
                ForEach(Array(group.occurrences.prefix(12))) { occurrence in
                    occurrenceView(occurrence)
                }
                if group.occurrences.count > 12 {
                    Text(formatted("%d additional occurrence(s)", group.occurrences.count - 12))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 9)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: group.disposition == .safeToNeutralize
                    ? "scope"
                    : "eye.fill")
                    .foregroundStyle(dispositionColor(group.disposition))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(group.id).font(.caption.monospaced().weight(.bold))
                        Text(AppLocalization.text(group.technique.rawValue, language: language))
                            .font(.subheadline.weight(.semibold))
                        if let codePoint = group.codePoint {
                            Text(codePoint).font(.caption.monospaced())
                        }
                    }
                    Text(formatted(
                        "%d occurrence(s) in %d file(s)",
                        group.occurrenceCount,
                        group.fileCount
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(AppLocalization.text(group.disposition.rawValue, language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dispositionColor(group.disposition))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(dispositionColor(group.disposition).opacity(0.10), in: Capsule())
            }
        }
        .padding(.bottom, 30)
        .padding(12)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(dispositionColor(group.disposition).opacity(0.25), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            FindingCopyButton(title: localized("Copy Signature")) {
                onCopy(FindingReportFormatter.signatureGroup(group, language: language))
            }
            .padding(8)
        }
        .contextMenu {
            Button(localized("Copy Signature"), systemImage: "doc.on.doc") {
                onCopy(FindingReportFormatter.signatureGroup(group, language: language))
            }
        }
    }

    private func occurrenceView(_ occurrence: SignatureOccurrence) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(occurrence.relativePath).font(.caption.monospaced().weight(.semibold))
                if occurrence.line > 0 {
                    Text(formatted("line %d, column %d", occurrence.line, occurrence.column))
                }
                Spacer()
                Text(occurrence.encoding.rawValue).font(.caption2.monospaced())
            }
            if let preview = occurrence.changePreview {
                Text(formatted("Preview · line %d", preview.line))
                    .font(.caption2.weight(.semibold))
                diffLine(prefix: "−", text: preview.before, color: .red)
                diffLine(prefix: "+", text: preview.after, color: .green)
            }
        }
        .padding(8)
        .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
    }

    private func diffLine(prefix: String, text: String, color: Color) -> some View {
        Text("\(prefix) \(text)")
            .font(.caption2.monospaced())
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func verificationBanner(_ result: SignatureNeutralizationResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                result.verificationPassed
                    ? formatted("Verified: %d signature group(s) neutralized.", result.neutralizedGroupIDs.count)
                    : formatted("Verification found %d safe signature group(s) still present.", result.remainingSafeGroupIDs.count),
                systemImage: result.verificationPassed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(result.verificationPassed ? .green : .orange)
            Text(formatted("Backup: %@", result.vaccineResult.backupURL.path))
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((result.verificationPassed ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func dispositionColor(_ disposition: SignatureDisposition) -> Color {
        switch disposition {
        case .safeToNeutralize: .green
        case .reviewOnly: .orange
        case .protected: .red
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = localized("Choose")
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        rootURL = selected
        report = nil
        result = nil
        errorMessage = nil
        scan()
    }

    private func scan() {
        guard let rootURL else { return }
        isWorking = true
        errorMessage = nil
        result = nil
        Task {
            do {
                report = try await Task.detached(priority: .userInitiated) {
                    try SignatureHuntEngine.scan(rootURL: rootURL)
                }.value
            } catch {
                errorMessage = localized(error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func neutralize() {
        guard let report else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let base = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first!
                    .appendingPathComponent("SignalSieve", isDirectory: true)
                    .appendingPathComponent("Signature Hunt Backups", isDirectory: true)
                let neutralization = try await Task.detached(priority: .userInitiated) {
                    try SignatureHuntEngine.neutralizeSafeSignatures(
                        in: report,
                        backupBaseURL: base
                    )
                }.value
                result = neutralization
                self.report = neutralization.postScanReport
            } catch {
                errorMessage = localized(error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    private func formatted(_ format: String, _ arguments: CVarArg...) -> String {
        String(
            format: AppLocalization.text(format, language: language),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }
}
