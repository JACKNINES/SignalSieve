// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

@MainActor
struct FolderTriageView: View {
    let language: AppLanguage
    let onCopy: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rootURL: URL?
    @State private var report: FolderTriageReport?
    @State private var markerResult: FolderTriageMarkerResult?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var confirmsApply = false
    @State private var confirmsRestore = false
    @State private var operationID = UUID()

    var body: some View {
        SheetScaffold(
            title: localized("Folder Triage"),
            subtitle: localized("Recursive local review with report-only defaults"),
            systemImage: "folder.badge.gearshape",
            doneTitle: localized("Done"),
            onDone: { dismiss() },
            footerNote: localized("Folder Triage never rewrites document content. Red means review, not malware."),
            content: { content },
            footer: { footerActions }
        )
        .frame(minWidth: 900, minHeight: 700)
        .confirmationDialog(
            localized("Apply red Finder markers?"),
            isPresented: $confirmsApply,
            titleVisibility: .visible
        ) {
            Button(localized("Apply Red Finder Markers"), role: .destructive) { applyMarkers() }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("Only red files from this report are revalidated and marked with a SignalSieve-owned Finder tag. Existing tags are preserved and document content is never changed."))
        }
        .confirmationDialog(
            localized("Restore Folder Triage markers?"),
            isPresented: $confirmsRestore,
            titleVisibility: .visible
        ) {
            Button(localized("Restore Markers")) { restoreMarkers() }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("SignalSieve removes only its own marker and restores prior Finder labels when the marked file identity still matches."))
        }
        .onDisappear { operationID = UUID() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Button(localized("Choose Folder…"), systemImage: "folder", action: chooseFolder)
                    .sieveSheetButton()
                    .disabled(isWorking)

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

                if let report {
                    Button(localized("Copy Triage Report"), systemImage: "doc.on.doc") {
                        onCopy(formatReport(report))
                    }
                    .sieveSheetButton()
                }

                Button(localized("Scan"), systemImage: "magnifyingglass", action: scan)
                    .sieveSheetButton(.primary)
                    .disabled(rootURL == nil || isWorking)
            }

            safetyBanner

            if isWorking {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(localized("Working locally…"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if let report {
                summary(report)
                if report.isAssessmentBounded {
                    Label(localized("Report is bounded; additional assessed or unassessed files were omitted from the on-screen list."), systemImage: "list.bullet.clipboard")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                triageLists(report)
            } else {
                emptyState
            }

            if let markerResult {
                markerResultBanner(markerResult)
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 8) {
            Button(localized("Restore Markers"), systemImage: "arrow.uturn.backward.circle") {
                confirmsRestore = true
            }
            .sieveSheetButton()
            .disabled(rootURL == nil || isWorking)

            Button(localized("Apply Red Finder Markers"), systemImage: "tag.fill") {
                confirmsApply = true
            }
            .sieveSheetButton(.primary)
            .disabled((report?.redFiles.isEmpty ?? true) || isWorking)
        }
    }

    private var safetyBanner: some View {
        Label {
            Text(localized("Report-only is the default. Skipped, unreadable, binary, symlink, and oversized files are listed as unassessed instead of green."))
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
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(localized("Choose a folder to triage"))
                .font(.headline)
            Text(localized("The recursive scan runs locally, reuses Vaccine bounds, and does not upload, execute, or rewrite files."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summary(_ report: FolderTriageReport) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            SheetStatTile(value: "\(report.count(for: .green))", label: localized("Green"))
            SheetStatTile(value: "\(report.count(for: .yellow))", label: localized("Yellow"))
            SheetStatTile(value: "\(report.count(for: .orange))", label: localized("Orange"))
            SheetStatTile(value: "\(report.count(for: .red))", label: localized("Red"))
            SheetStatTile(value: "\(report.totalUnassessedFileCount)", label: localized("Unassessed"))
            SheetStatTile(value: "\(report.excludedDirectoryCount)", label: localized("Skipped folders"))
        }
    }

    private func triageLists(_ report: FolderTriageReport) -> some View {
        List {
            Section(localized("Assessed files")) {
                if report.assessments.isEmpty {
                    Label(localized("No assessed files were available in this folder."), systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.assessments) { item in
                        assessmentRow(item)
                    }
                }
            }
            Section(localized("Skipped or unassessed files")) {
                if report.unassessedFiles.isEmpty {
                    Label(localized("No skipped or unassessed files were reported."), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(report.unassessedFiles) { skipped in
                        HStack(spacing: 10) {
                            Image(systemName: "questionmark.diamond.fill")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(skipped.relativePath).font(.system(.body, design: .monospaced))
                                Text(AppLocalization.text(skipped.reason.rawValue, language: language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .frame(maxHeight: .infinity)
    }

    private func assessmentRow(_ item: FolderTriageFileAssessment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: item.severity))
                .foregroundStyle(color(for: item.severity))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.relativePath).font(.system(.body, design: .monospaced))
                    Text(AppLocalization.text(item.severity.label, language: language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(for: item.severity))
                }
                Text(AppLocalization.text(item.evidenceSummary, language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if item.severity == .red {
                    Text(localized("Red is a review marker, not a malware verdict."))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button(localized("Reveal in Finder"), systemImage: "finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            }
            .sieveSheetButton()
        }
        .contextMenu {
            Button(localized("Reveal in Finder"), systemImage: "finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            }
        }
    }

    private func markerResultBanner(_ result: FolderTriageMarkerResult) -> some View {
        let blocked = result.count(.ownershipConflict)
            + result.count(.manifestLimit)
            + result.count(.unavailable)
        return VStack(alignment: .leading, spacing: 5) {
            Label(
                formatted(
                    "Marker outcomes: %d applied, %d restored, %d changed, %d blocked, %d failed.",
                    result.count(.applied),
                    result.count(.restored),
                    result.count(.changedSinceScan),
                    blocked,
                    result.count(.failed)
                ),
                systemImage: "tag.fill"
            )
            .foregroundStyle(result.count(.failed) == 0 && blocked == 0 ? .green : .orange)
            Text(formatted("Manifest: %@", result.manifestURL.path))
                .font(.caption.monospaced())
                .textSelection(.enabled)
            ForEach(result.outcomes.prefix(6)) { outcome in
                Text("\(outcome.relativePath) · \(AppLocalization.text(outcome.kind.rawValue, language: language))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
        markerResult = nil
        errorMessage = nil
        scan()
    }

    private func scan() {
        guard let rootURL else { return }
        let currentOperationID = UUID()
        operationID = currentOperationID
        isWorking = true
        errorMessage = nil
        markerResult = nil
        Task { @MainActor in
            do {
                let newReport = try await Task.detached(priority: .userInitiated) {
                    try FolderTriageEngine.scan(rootURL: rootURL)
                }.value
                guard operationID == currentOperationID else { return }
                report = newReport
            } catch {
                guard operationID == currentOperationID else { return }
                errorMessage = localized(error.localizedDescription)
            }
            guard operationID == currentOperationID else { return }
            isWorking = false
        }
    }

    private func applyMarkers() {
        guard let report else { return }
        let manifestDirectory = markerDirectory()
        let currentOperationID = UUID()
        operationID = currentOperationID
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FolderTriageEngine.applyRedMarkers(
                        to: report,
                        manifestDirectory: manifestDirectory
                    )
                }.value
                guard operationID == currentOperationID else { return }
                markerResult = result
            } catch {
                guard operationID == currentOperationID else { return }
                errorMessage = localized(error.localizedDescription)
            }
            guard operationID == currentOperationID else { return }
            isWorking = false
        }
    }

    private func restoreMarkers() {
        guard let rootURL else { return }
        let manifestDirectory = markerDirectory()
        let currentOperationID = UUID()
        operationID = currentOperationID
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FolderTriageEngine.restoreMarkers(
                        rootURL: rootURL,
                        manifestDirectory: manifestDirectory
                    )
                }.value
                guard operationID == currentOperationID else { return }
                markerResult = result
            } catch {
                guard operationID == currentOperationID else { return }
                errorMessage = localized(error.localizedDescription)
            }
            guard operationID == currentOperationID else { return }
            isWorking = false
        }
    }

    private func markerDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SignalSieve", isDirectory: true)
            .appendingPathComponent("Folder Triage Markers", isDirectory: true)
    }

    private func icon(for severity: FolderTriageSeverity) -> String {
        switch severity {
        case .green: "checkmark.circle.fill"
        case .yellow: "exclamationmark.circle.fill"
        case .orange: "exclamationmark.triangle.fill"
        case .red: "exclamationmark.octagon.fill"
        }
    }

    private func color(for severity: FolderTriageSeverity) -> Color {
        switch severity {
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        }
    }

    private func formatReport(_ report: FolderTriageReport) -> String {
        var lines = [
            localized("Signal Sieve — Folder Triage Report"),
            formatted("Root: %@", report.rootURL.path),
            localized("Red is review-only evidence, not a malware verdict."),
            formatted(
                "Green: %d · Yellow: %d · Orange: %d · Red: %d · Unassessed: %d",
                report.count(for: .green),
                report.count(for: .yellow),
                report.count(for: .orange),
                report.count(for: .red),
                report.totalUnassessedFileCount
            )
        ]
        for item in report.assessments.prefix(80) {
            lines.append("- \(localized(item.severity.label)): \(item.relativePath) — \(localized(item.evidenceSummary))")
        }
        if !report.unassessedFiles.isEmpty {
            lines.append(localized("Unassessed:"))
            for skipped in report.unassessedFiles.prefix(80) {
                lines.append("- \(skipped.relativePath) — \(AppLocalization.text(skipped.reason.rawValue, language: language))")
            }
        }
        return lines.joined(separator: "\n")
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
