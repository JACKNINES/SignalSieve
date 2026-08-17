// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

struct FileProvenanceView: View {
    let language: AppLanguage
    let onCopy: (String) -> Void
    let onUseClipboardImage: (ClipboardImagePayload, Int) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var report: FileProvenanceReport?
    @State private var selectedURL: URL?
    @State private var clipboardImage: ClipboardImagePayload?
    @State private var cleaningResult: FileMetadataCleaningResult?
    @State private var clipboardCleaningResult: ClipboardImageCleaningResult?
    @State private var clipboardSourceChangeCount: Int?
    @State private var cleanImageIsOnClipboard = false
    @State private var savedCleanImageURL: URL?
    @State private var errorMessage: String?

    init(
        language: AppLanguage,
        initialClipboardImage: ClipboardImagePayload? = nil,
        onCopy: @escaping (String) -> Void,
        onUseClipboardImage: @escaping (ClipboardImagePayload, Int) -> Bool = { _, _ in false }
    ) {
        self.language = language
        self.onCopy = onCopy
        self.onUseClipboardImage = onUseClipboardImage
        _clipboardImage = State(initialValue: initialClipboardImage)
        _clipboardSourceChangeCount = State(
            initialValue: initialClipboardImage == nil ? nil : NSPasteboard.general.changeCount
        )
        _report = State(initialValue: initialClipboardImage.map {
            FileProvenanceAnalyzer.analyze($0.data, fileName: $0.fileName)
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let report {
                        summary(report)
                        c2paStatus(report)
                        findings(report)
                        if let cleaningResult {
                            cleaningResultCard(cleaningResult)
                        }
                        if let clipboardCleaningResult {
                            clipboardCleaningResultCard(clipboardCleaningResult)
                        }
                    } else {
                        emptyState
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    }
                    limitationCard
                }
                .padding(18)
            }

            Divider()
            HStack {
                Label(localized("Original stays untouched · cleaning creates a new copy"), systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let report {
                    Button(localized("Copy Findings"), systemImage: "doc.on.doc") {
                        onCopy(FindingReportFormatter.fileProvenanceReport(
                            report,
                            language: language
                        ))
                    }
                }
                if let report,
                   selectedURL != nil,
                   !report.findings.isEmpty,
                   FileMetadataCleaner.supports(report.format) {
                    Button(localized("Create Clean Copy…"), systemImage: "doc.badge.plus") {
                        createCleanCopy()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if clipboardImage != nil {
                    Button(localized("Create Fresh Clean Image"), systemImage: "photo.badge.checkmark") {
                        createFreshClipboardImage()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(localized("Paste Image"), systemImage: "doc.on.clipboard") {
                    pasteClipboardImage()
                }
                Button(localized("Choose File…"), systemImage: "doc.badge.magnifyingglass", action: chooseFile)
                Button(localized("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 720, minHeight: 620)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("File Provenance Inspector"))
                    .font(.title2.weight(.semibold))
                Text(localized("Local inspection of C2PA and common metadata containers"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(localized("Paste Image"), systemImage: "doc.on.clipboard") {
                pasteClipboardImage()
            }
            .help(localized("Paste the current clipboard image and inspect its bytes locally."))
            Button(localized("Choose File…"), systemImage: "folder", action: chooseFile)
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.magnifyingglass")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(localized("Choose an image or document to inspect"))
                .font(.headline)
            Text(localized("SignalSieve inspects locally. Metadata cleaning is optional and always creates a separate file."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            HStack(spacing: 10) {
                Button(localized("Paste Image"), systemImage: "doc.on.clipboard") {
                    pasteClipboardImage()
                }
                .buttonStyle(.borderedProminent)
                Button(localized("Choose File…"), systemImage: "folder", action: chooseFile)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private func summary(_ report: FileProvenanceReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(report.fileName)
                .font(.headline)
                .textSelection(.enabled)
            HStack(spacing: 16) {
                Label(
                    AppLocalization.text(report.format.rawValue, language: language),
                    systemImage: "doc"
                )
                Label(byteCount(report.fileSize), systemImage: "externaldrive")
                Label(
                    formatted("%d finding(s)", report.findings.count),
                    systemImage: "list.bullet.rectangle"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if report.wasTruncated {
                Label(
                    localized("Only the bounded prefix was inspected because the file exceeds the scan limit."),
                    systemImage: "exclamationmark.triangle"
                )
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let clipboardImage {
                Label(
                    localized(clipboardImage.wasTranscodedToPNG
                        ? "This clipboard representation was normalized to PNG locally before inspection; the normalized copy contains no source-container metadata."
                        : "This report analyzes the image bytes currently pasted from the clipboard."),
                    systemImage: clipboardImage.wasTranscodedToPNG
                        ? "arrow.triangle.2.circlepath"
                        : "doc.on.clipboard"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func c2paStatus(_ report: FileProvenanceReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: report.containsC2PAContainer
                ? "signature"
                : "questionmark.diamond")
                .foregroundStyle(report.containsC2PAContainer ? .orange : .blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("C2PA status"))
                    .font(.headline)
                Text(localized(report.containsC2PAContainer
                    ? "Container detected · cryptographic validation not performed"
                    : "No embedded C2PA container detected in the scanned data"))
                    .font(.subheadline.weight(.medium))
                Text(localized(report.containsC2PAContainer
                    ? "A compatible validator is required to verify the signer, claim, asset binding, and trust chain."
                    : "This does not rule out external manifests, soft bindings, or invisible pixel/text marks."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (report.containsC2PAContainer ? Color.orange : .blue).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    @ViewBuilder
    private func findings(_ report: FileProvenanceReport) -> some View {
        if report.findings.isEmpty {
            Label(
                localized("No supported embedded metadata structures were found in the scanned data."),
                systemImage: "info.circle"
            )
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Text(localized("Metadata findings"))
                    .font(.headline)
                ForEach(report.findings) { finding in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(AppLocalization.text(finding.kind.rawValue, language: language))
                                .font(.headline)
                            Spacer()
                            Label(
                                AppLocalization.evidenceConfidenceLabel(
                                    finding.evidenceConfidence,
                                    language: language
                                ),
                                systemImage: finding.evidenceConfidence == .exact
                                    ? "checkmark.seal"
                                    : "questionmark.circle"
                            )
                                .font(.caption)
                                .foregroundStyle(finding.evidenceConfidence == .exact ? .blue : .orange)
                        }
                        Text(AppLocalization.text(finding.detail, language: language))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(finding.evidence)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 28)
                    .padding(12)
                    .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(alignment: .bottomTrailing) {
                        FindingCopyButton(title: localized("Copy Finding")) {
                            onCopy(FindingReportFormatter.fileProvenanceFinding(
                                finding,
                                language: language
                            ))
                        }
                        .padding(7)
                    }
                }
            }
        }
    }

    private var limitationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(localized("Inspection boundaries"), systemImage: "info.circle.fill")
                .font(.headline)
            Text(localized("SignalSieve identifies container structures and metadata markers. It does not yet validate C2PA signatures or infer authorship."))
            Text(localized("Safe metadata cleaning supports PNG, JPEG, PDF, DOCX, and ODT. PDF pages, forms, links, image data, and document bodies are preserved; signed or encrypted documents are refused."))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(14)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = localized("Inspect")
        panel.message = localized("Choose a file for local, read-only provenance inspection.")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            report = try FileProvenanceAnalyzer.analyze(url: url)
            selectedURL = url
            clipboardImage = nil
            cleaningResult = nil
            clipboardCleaningResult = nil
            clipboardSourceChangeCount = nil
            cleanImageIsOnClipboard = false
            savedCleanImageURL = nil
            errorMessage = nil
        } catch {
            report = nil
            selectedURL = nil
            cleaningResult = nil
            clipboardCleaningResult = nil
            clipboardSourceChangeCount = nil
            cleanImageIsOnClipboard = false
            savedCleanImageURL = nil
            errorMessage = localized("The selected file could not be inspected safely.")
        }
    }

    private func pasteClipboardImage() {
        do {
            let pasteboard = NSPasteboard.general
            let changeCount = pasteboard.changeCount
            let payload = try ClipboardImagePasteboardReader.read(from: pasteboard)
            guard pasteboard.changeCount == changeCount else {
                errorMessage = localized("The clipboard changed while the image was being read. Paste it again.")
                return
            }
            clipboardImage = payload
            report = FileProvenanceAnalyzer.analyze(
                payload.data,
                fileName: payload.fileName
            )
            selectedURL = nil
            cleaningResult = nil
            clipboardCleaningResult = nil
            clipboardSourceChangeCount = changeCount
            cleanImageIsOnClipboard = false
            savedCleanImageURL = nil
            errorMessage = nil
        } catch ClipboardImageImportError.imageTooLarge {
            errorMessage = localized("The clipboard image is too large for bounded local inspection.")
        } catch {
            errorMessage = localized("No supported image is currently available on the clipboard.")
        }
    }

    private func createCleanCopy() {
        guard let sourceURL = selectedURL else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = FileMetadataCleaner.suggestedCopyName(for: sourceURL)
        panel.prompt = localized("Create Clean Copy")
        panel.message = localized("The original file will remain untouched. SignalSieve will reanalyze the new copy before reporting success.")
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        let sourceScoped = sourceURL.startAccessingSecurityScopedResource()
        let destinationScoped = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if sourceScoped { sourceURL.stopAccessingSecurityScopedResource() }
            if destinationScoped { destinationURL.stopAccessingSecurityScopedResource() }
        }

        do {
            let result = try FileMetadataCleaner.cleanCopy(of: sourceURL, to: destinationURL)
            cleaningResult = result
            errorMessage = nil
        } catch FileMetadataCleaningError.destinationAlreadyExists {
            errorMessage = localized("Choose a new filename. SignalSieve never overwrites an existing file.")
        } catch FileMetadataCleaningError.noSupportedMetadata {
            errorMessage = localized("No supported metadata could be removed from this file.")
        } catch FileMetadataCleaningError.signedContainer {
            errorMessage = localized("This document package is digitally signed. Cleaning was refused because rebuilding it would invalidate the signature.")
        } catch FileMetadataCleaningError.encryptedContainer {
            errorMessage = localized("This PDF is encrypted or locked. Cleaning was refused because Signal Sieve cannot verify a safe structural rewrite.")
        } catch FileMetadataCleaningError.cleaningBackendUnavailable {
            errorMessage = localized("The verified PDF cleaning component is unavailable in this build.")
        } catch FileMetadataCleaningError.invalidContainer {
            errorMessage = localized("This file has an unusual or damaged container structure. Cleaning was refused so the original remains untouched.")
        } catch {
            errorMessage = localized("A verified clean copy could not be created. The original file was not modified.")
        }
    }

    private func cleaningResultCard(_ result: FileMetadataCleaningResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(localized("Clean copy verified"), systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(result.cleanedCopyURL.lastPathComponent)
                .font(.subheadline.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 16) {
                Label(
                    formatted("%d metadata finding(s) removed", result.removedFindingCount),
                    systemImage: "trash.slash"
                )
                Label(
                    formatted("%d remaining after reanalysis", result.cleanedReport.findings.count),
                    systemImage: "arrow.clockwise"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Label(
                localized("The original bytes were checked again and remained unchanged."),
                systemImage: "equal.circle"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(localized("Show Copy in Finder"), systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([result.cleanedCopyURL])
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.green.opacity(0.28), lineWidth: 1)
        }
    }

    private func createFreshClipboardImage() {
        guard let clipboardImage else { return }
        do {
            clipboardCleaningResult = try ClipboardImageCleaner.makeFreshCopy(
                from: clipboardImage
            )
            cleanImageIsOnClipboard = false
            savedCleanImageURL = nil
            errorMessage = nil
        } catch ClipboardImageImportError.imageTooLarge {
            errorMessage = localized("The clipboard image is too large to rebuild safely.")
        } catch {
            errorMessage = localized("A verified clean image could not be created. The original image was not modified.")
        }
    }

    private func clipboardCleaningResultCard(
        _ result: ClipboardImageCleaningResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(localized("Fresh clean image verified"), systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(localized("Signal Sieve decoded the visible pixels and rebuilt a new PNG without copying source-container metadata."))
                .font(.subheadline)
            HStack(spacing: 16) {
                Label(
                    formatted("%d metadata finding(s) removed", result.removedFindingCount),
                    systemImage: "trash.slash"
                )
                Label(
                    formatted("%d remaining after reanalysis", result.cleanedReport.findings.count),
                    systemImage: "arrow.clockwise"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Label(
                localized("This removes container metadata, not watermarks encoded in the visible pixel values."),
                systemImage: "eye.trianglebadge.exclamationmark"
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(
                    localized(cleanImageIsOnClipboard
                        ? "Clean Image Is on Clipboard"
                        : "Use This Instead"),
                    systemImage: cleanImageIsOnClipboard
                        ? "checkmark.circle.fill"
                        : "doc.on.clipboard.fill"
                ) {
                    useCleanClipboardImage(result)
                }
                .buttonStyle(.borderedProminent)
                .disabled(cleanImageIsOnClipboard)

                Button(localized("Save Clean Image…"), systemImage: "square.and.arrow.down") {
                    saveCleanClipboardImage(result)
                }

                if let savedCleanImageURL {
                    Label(
                        formatted("Saved as %@", savedCleanImageURL.lastPathComponent),
                        systemImage: "checkmark.circle"
                    )
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.green.opacity(0.28), lineWidth: 1)
        }
    }

    private func useCleanClipboardImage(_ result: ClipboardImageCleaningResult) {
        guard let expectedChangeCount = clipboardSourceChangeCount else {
            errorMessage = localized("Paste the source image again before replacing the clipboard.")
            return
        }
        let currentChangeCount = NSPasteboard.general.changeCount
        guard currentChangeCount == expectedChangeCount else {
            clipboardSourceChangeCount = currentChangeCount
            errorMessage = localized("The clipboard changed. Click Use This Instead again to confirm replacing the newer clipboard content.")
            return
        }
        guard onUseClipboardImage(result.cleanedPayload, expectedChangeCount) else {
            errorMessage = localized("The clean image could not be placed on the clipboard.")
            return
        }
        clipboardSourceChangeCount = NSPasteboard.general.changeCount
        cleanImageIsOnClipboard = true
        errorMessage = nil
    }

    private func saveCleanClipboardImage(_ result: ClipboardImageCleaningResult) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = result.cleanedPayload.fileName
        panel.prompt = localized("Save Clean Image")
        panel.message = localized("A new verified PNG will be saved. The original clipboard image remains unchanged.")
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        let scoped = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { destinationURL.stopAccessingSecurityScopedResource() }
        }

        var createdCopy = false
        var verifiedCopy = false
        defer {
            if createdCopy && !verifiedCopy {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }
        do {
            guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
                errorMessage = localized("Choose a new filename. SignalSieve never overwrites an existing file.")
                return
            }
            try result.cleanedPayload.data.write(
                to: destinationURL,
                options: [.atomic, .withoutOverwriting]
            )
            createdCopy = true
            let persistedData = try Data(contentsOf: destinationURL, options: .mappedIfSafe)
            let persistedReport = FileProvenanceAnalyzer.analyze(
                persistedData,
                fileName: destinationURL.lastPathComponent
            )
            guard persistedData == result.cleanedPayload.data,
                  persistedReport.findings.isEmpty,
                  !persistedReport.containsC2PAContainer else {
                throw FileMetadataCleaningError.verificationFailed
            }
            verifiedCopy = true
            savedCleanImageURL = destinationURL
            errorMessage = nil
        } catch {
            errorMessage = localized("The verified clean image could not be saved. No existing file was overwritten.")
        }
    }

    private func byteCount(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    private func formatted(_ englishFormat: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(englishFormat),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }
}
