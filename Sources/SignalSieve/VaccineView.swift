// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

struct VaccineView: View {
    let language: AppLanguage
    let onCopy: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rootURL: URL?
    @State private var report: VaccineScanReport?
    @State private var result: VaccineResult?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var confirmsVaccination = false
    @State private var showsSmartAssAchievement = false

    var body: some View {
        SheetScaffold(
            title: localized("Vaccine"),
            subtitle: localized("Scan a project locally before changing any file"),
            systemImage: "syringe.fill",
            doneTitle: localized("Done"),
            onDone: { dismiss() },
            footerNote: localized("Encoded data, file metadata, and review-only findings are reported but never rewritten."),
            content: { scanContent },
            footer: {
                Button(localized("Vaccinate Safe Findings…"), systemImage: "shield.checkered") {
                    attemptVaccination()
                }
                .sieveSheetButton(.primary)
                .disabled(isVaccinationBlocked)
            }
        )
        .frame(minWidth: 860, minHeight: 680)
        .confirmationDialog(
            localized("Vaccinate the selected project?"),
            isPresented: $confirmsVaccination,
            titleVisibility: .visible
        ) {
            Button(localized("Create Backup and Vaccinate")) { vaccinate() }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("Only safely removable Unicode controls and safe punctuation/whitespace replacements will be applied. A complete backup of every changed file is created first."))
        }
        .overlay(alignment: .top) {
            if showsSmartAssAchievement {
                SmartAssAchievementView()
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }

    /// The footer action stays visible at all times, so it has to describe its
    /// own preconditions rather than relying on being absent.
    private var isVaccinationBlocked: Bool {
        guard let report, !isWorking else { return true }
        return report.sanitizableFileCount == 0 && !report.isSignalSieveTarget
    }

    private var scanContent: some View {
        VStack(alignment: .leading, spacing: 14) {
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

                if let report, !report.findings.isEmpty {
                    Button(localized("Copy Findings"), systemImage: "doc.on.doc") {
                        onCopy(FindingReportFormatter.vaccineReport(report, language: language))
                    }
                    .sieveSheetButton()
                }

                Button(localized("Scan"), systemImage: "magnifyingglass") { scan() }
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
                if report.isSignalSieveTarget {
                    selfVaccinationWarning
                }
                findings(report)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text(localized("Choose a project folder"))
                        .font(.headline)
                    Text(localized("Vaccine will identify Unicode risks, encoded data, file provenance, metadata, and binary files without uploading anything."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let result {
                resultBanner(result)
            }
        }
    }

    private var safetyBanner: some View {
        Label {
            Text(localized("Symlinks and binary files are never modified. Generated dependency folders are skipped. Files changed after the scan are left untouched."))
                .font(.caption)
        } icon: {
            Image(systemName: "lock.shield.fill").foregroundStyle(.green)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var selfVaccinationWarning: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("Do not vaccinate SignalSieve with itself."))
                    .font(.subheadline.weight(.semibold))
                Text(localized("Its security fixtures intentionally contain attack samples. Analysis is allowed, but Vaccine will block every modification."))
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.red)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.red.opacity(0.45), lineWidth: 1)
        }
    }

    private func summary(_ report: VaccineScanReport) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            SheetStatTile(value: "\(report.scannedFileCount)", label: localized("Text files scanned"))
            SheetStatTile(value: "\(report.provenanceScannedFileCount)", label: localized("Metadata files scanned"))
            SheetStatTile(value: "\(report.affectedFileCount)", label: localized("Files with findings"))
            SheetStatTile(value: "\(report.sanitizableFileCount)", label: localized("Safe to vaccinate"))
            SheetStatTile(value: "\(report.totalMetadataFindingCount)", label: localized("Metadata findings"))
        }
    }

    private func findings(_ report: VaccineScanReport) -> some View {
        Group {
            if report.findings.isEmpty {
                Label(localized("No Vaccine findings in scanned text or metadata files."), systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(report.findings) { finding in
                    HStack(spacing: 10) {
                        Image(systemName: finding.sanitizableFindingCount > 0
                            ? "exclamationmark.shield.fill"
                            : "eye.fill")
                            .foregroundStyle(finding.sanitizableFindingCount > 0 ? .orange : .yellow)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(finding.relativePath).font(.system(.body, design: .monospaced))
                            HStack(spacing: 10) {
                                if let language = finding.detectedLanguage {
                                    Text(language)
                                }
                                if finding.unicodeFindingCount > 0 {
                                    Text(formatted("%d Unicode finding(s)", finding.unicodeFindingCount))
                                }
                                if let kind = finding.encodedDataKind {
                                    Text(AppLocalization.text(kind.rawValue, language: language))
                                }
                                if finding.reviewOnlyFindingCount > 0 {
                                    Text(formatted("%d review-only", finding.reviewOnlyFindingCount))
                                }
                                if let provenance = finding.provenanceReport {
                                    Text(AppLocalization.text(provenance.format.rawValue, language: language))
                                    Text(formatted("%d metadata finding(s)", provenance.findings.count))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let provenance = finding.provenanceReport,
                               finding.revealedFragments.isEmpty,
                               finding.codeFindings.isEmpty {
                                ForEach(Array(provenance.findings.prefix(3))) { metadataFinding in
                                    Text(
                                        "\(AppLocalization.text(metadataFinding.kind.rawValue, language: language)) · \(AppLocalization.text(metadataFinding.evidence, language: language))"
                                    )
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.purple)
                                }
                            } else if finding.revealedFragments.isEmpty {
                                ForEach(Array(finding.codeFindings.prefix(3))) { codeFinding in
                                    Text(formatted(
                                        "%@ · line %d, column %d · %@",
                                        codeFinding.codePoint,
                                        codeFinding.line,
                                        codeFinding.column,
                                        AppLocalization.codeKind(codeFinding.kind, language: language)
                                    ))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(codeFinding.kind.riskLevel == .high ? .red : .orange)
                                }
                            } else {
                                ForEach(Array(finding.revealedFragments.prefix(3))) { fragment in
                                    revealedFragment(fragment)
                                }
                            }
                        }
                        Spacer()
                        if finding.sanitizableFindingCount > 0 {
                            Text(formatted("%d safe change(s)", finding.sanitizableFindingCount))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.bottom, 30)
                    .overlay(alignment: .bottomTrailing) {
                        FindingCopyButton(title: localized("Copy Finding")) {
                            onCopy(FindingReportFormatter.vaccineFile(finding, language: language))
                        }
                        .padding(.vertical, 3)
                    }
                    .contextMenu {
                        Button(localized("Copy Finding"), systemImage: "doc.on.doc") {
                            onCopy(FindingReportFormatter.vaccineFile(finding, language: language))
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func revealedFragment(_ fragment: RevealedInvisibleFragment) -> some View {
        let color: Color = fragment.presentation == .decodedPayload ? .purple : .orange
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(formatted(
                    "Hidden element %d · %@ · line %d, column %d",
                    fragment.findingNumber,
                    fragment.codePoint,
                    fragment.line,
                    fragment.column
                ))
                Spacer()
                Text(AppLocalization.text(fragment.presentation.rawValue, language: language))
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            .font(.caption2.monospaced())
            Text("“\(fragment.text)”")
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if fragment.hiddenScalarCount > 1 {
                Text(formatted(
                    "%d invisible scalar(s) represented",
                    fragment.hiddenScalarCount
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(7)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.30), lineWidth: 1)
        }
    }

    private func resultBanner(_ result: VaccineResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                formatted("Vaccinated %d file(s). Removed %d and replaced %d element(s).", result.sanitizedFileCount, result.removedCount, result.replacedCount),
                systemImage: "checkmark.shield.fill"
            )
            .foregroundStyle(.green)
            Text(formatted("Backup: %@", result.backupURL.path))
                .font(.caption.monospaced())
                .textSelection(.enabled)
            if !result.filesChangedSinceScan.isEmpty {
                Text(formatted("%d file(s) changed after scanning and were not modified.", result.filesChangedSinceScan.count))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                let scanned = try await Task.detached(priority: .userInitiated) {
                    try VaccineEngine.scan(rootURL: rootURL)
                }.value
                report = scanned
            } catch {
                errorMessage = localized(error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func vaccinate() {
        guard let report else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let backupBase = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first!
                    .appendingPathComponent("SignalSieve", isDirectory: true)
                    .appendingPathComponent("Vaccine Backups", isDirectory: true)
                result = try await Task.detached(priority: .userInitiated) {
                    try VaccineEngine.vaccinate(report, backupBaseURL: backupBase)
                }.value
                self.report = try await Task.detached(priority: .userInitiated) {
                    try VaccineEngine.scan(rootURL: report.rootURL)
                }.value
            } catch {
                errorMessage = localized(error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func attemptVaccination() {
        guard let report else { return }
        guard report.isSignalSieveTarget else {
            confirmsVaccination = true
            return
        }

        errorMessage = localized("SignalSieve cannot vaccinate itself. No files were modified.")
        NSSound(named: NSSound.Name("Glass"))?.play()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
            showsSmartAssAchievement = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                showsSmartAssAchievement = false
            }
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

private struct SmartAssAchievementView: View {
    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.70, green: 0.91, blue: 0.12),
                                     Color(red: 0.18, green: 0.55, blue: 0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "xbox.logo")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            .shadow(color: .green.opacity(0.55), radius: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text("ACHIEVEMENT UNLOCKED")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(Color(red: 0.67, green: 0.88, blue: 0.17))
                Text("SmartAss")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Try to auto vaccinate SignalSieve")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(width: 390, alignment: .leading)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Achievement unlocked. SmartAss. Try to auto vaccinate SignalSieve")
    }
}
