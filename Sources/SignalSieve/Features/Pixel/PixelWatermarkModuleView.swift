// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

struct PixelWatermarkModuleView: View {
    let language: AppLanguage

    private enum BundledPixelModuleKind: CaseIterable {
        case lsb
        case spectral

        var directoryName: String {
            switch self {
            case .lsb: "Baseline"
            case .spectral: "Spectral"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var module: ExternalPixelWatermarkModule?
    @State private var bundledModuleKind: BundledPixelModuleKind?
    @State private var imageURL: URL?
    @State private var score: PixelWatermarkScore?
    @State private var regeneration: PixelWatermarkRegenerationResult?
    @State private var strength = 0.25
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(
            title: localized("Pixel Watermark Lab"),
            subtitle: localized("Built-in LSB and spectral screening, plus advanced external modules"),
            systemImage: "photo.badge.magnifyingglass",
            doneTitle: localized("Done"),
            onDone: { dismiss() },
            footerNote: localized(bundledModuleKind != nil
                ? "Built-in forensic module · local and offline"
                : "External module · explicit execution only"),
            content: { labContent },
            footer: {
                if !availableBundledModules.isEmpty {
                    Menu {
                        if bundledModuleURL(for: .spectral) != nil {
                            Button(localized("Use Spectral Carrier Lab")) {
                                loadBundledModule(.spectral, showError: true)
                            }
                        }
                        if bundledModuleURL(for: .lsb) != nil {
                            Button(localized("Use LSB Baseline")) {
                                loadBundledModule(.lsb, showError: true)
                            }
                        }
                    } label: {
                        SieveMenuLabel(title: localized("Built-in Modules"), systemImage: "checkmark.shield")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                Button(localized("Choose Module Folder…"), systemImage: "shippingbox", action: chooseModule)
                    .sieveSheetButton(.primary)
            }
        )
        .frame(minWidth: 780, minHeight: 700)
        .onAppear {
            if module == nil { loadBundledModule(.spectral, showError: false) }
        }
    }

    private var labContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                trustBoundary
                moduleCard
                imageCard
                if let score { scoreCard(score) }
                if let regeneration { regenerationCard(regeneration) }
            }
        }
    }

    private var trustBoundary: some View {
        Group {
            if let bundledModuleKind {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        localized(bundledModuleKind == .spectral
                            ? "Built-in experimental spectral carrier lab"
                            : "Built-in experimental LSB baseline"),
                        systemImage: "checkmark.shield.fill"
                    )
                        .font(.headline)
                        .foregroundStyle(.blue)
                    if bundledModuleKind == .spectral {
                        Text(localized("Runs offline without a model. It screens weak periodic luminance carriers across a frequency bank and can suppress the strongest projection in a verified copy."))
                    } else {
                        Text(localized("Runs offline without a model. It screens classic least-significant-bit carrier regularity and can neutralize those bits in a verified copy."))
                    }
                    Text(localized("It has no provider keys and does not authenticate SynthID, C2PA, or every learned watermark. An elevated score is a forensic lead, not proof of authorship or AI generation."))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.blue.opacity(0.30), lineWidth: 1)
                }
            } else {
                externalTrustBoundary
            }
        }
    }

    private var externalTrustBoundary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(localized("Third-party execution boundary"), systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(localized("Signal Sieve validates the module path and output, stages a read-only input copy, requests offline mode, and never invokes a shell."))
            Text(localized("A third-party executable can ignore offline flags. Review its source, license, model downloads, and privacy behavior before running it."))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(14)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.orange.opacity(0.35), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var moduleCard: some View {
        if let module {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(module.manifest.name, systemImage: "shippingbox.fill")
                        .font(.headline)
                    Text("v\(module.manifest.version)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(module.manifest.license)
                        .font(.caption.weight(.medium))
                }
                HStack(spacing: 8) {
                    ForEach(module.manifest.capabilities, id: \.rawValue) { capability in
                        Text(localized(capability == .score ? "Score" : "Regenerate"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.purple.opacity(0.12), in: Capsule())
                    }
                }
                if let families = module.manifest.detectorFamilies, !families.isEmpty {
                    Text(localized("Detector families") + ": " + families.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let mode = module.manifest.verificationMode {
                    Text(localized("Verification scope") + ": " + mode.rawValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(mode == .providerCompatible ? .orange : .secondary)
                }
                if let digest = module.manifest.modelDigest {
                    Text(localized("Model digest") + ": " + digest)
                        .font(.caption2.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Text(module.rootURL.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Label(
                localized("Choose a folder containing signalsieve-pixel-module.json."),
                systemImage: "shippingbox"
            )
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localized("Image under review"))
                    .font(.headline)
                Spacer()
                Button(localized("Choose Image…"), systemImage: "photo", action: chooseImage)
            }
            if let imageURL {
                Text(imageURL.path)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text(localized("No image selected"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Button(localized("Score Image"), systemImage: "gauge.with.dots.needle.50percent") {
                    runScore()
                }
                .disabled(isWorking || imageURL == nil || module?.supports(.score) != true)

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: $strength, in: 0.05...0.70, step: 0.05)
                        .frame(width: 180)
                    Text(formatted("Regeneration strength: %d%%", Int((strength * 100).rounded())))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button(localized("Regenerate Copy…"), systemImage: "photo.badge.arrow.down") {
                    regenerateCopy()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || imageURL == nil || module?.supports(.regenerate) != true)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func scoreCard(_ score: PixelWatermarkScore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(localized(bundledModuleKind != nil ? "Forensic score" : "External score"), systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Text(formatted("%d%%", Int((score.score * 100).rounded())))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(score.isElevated == true ? .orange : .blue)
            }
            Text(score.detector)
                .font(.subheadline.weight(.medium))
            if let label = score.label {
                Text(localized(label))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(score.isElevated == true ? .orange : .secondary)
            }
            if let threshold = score.threshold {
                Text(formatted("Module threshold: %d%%", Int((threshold * 100).rounded())))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(localized(scoreExplanation))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func regenerationCard(_ result: PixelWatermarkRegenerationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localized("Regenerated copy verified"), systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(result.outputURL.lastPathComponent)
                .font(.subheadline.weight(.semibold))
            Text(formatted("%d × %d pixels · original unchanged", result.width, result.height))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let before = result.beforeScore, let after = result.afterScore {
                Text(formatted(
                    bundledModuleKind != nil
                        ? "Forensic score: %d%% before · %d%% after"
                        : "External score: %d%% before · %d%% after",
                    Int((before.score * 100).rounded()),
                    Int((after.score * 100).rounded())
                ))
                    .font(.caption.weight(.medium))
            }
            if !result.outputProvenanceReport.findings.isEmpty {
                Label(
                    formatted(
                        "%d metadata finding(s) remain in the generated copy",
                        result.outputProvenanceReport.findings.count
                    ),
                    systemImage: "info.circle"
                )
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button(localized("Show Copy in Finder"), systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
            }
        }
        .padding(14)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func chooseModule() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = localized("Choose Module")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            module = try ExternalPixelWatermarkEngine.loadModule(at: url)
            bundledModuleKind = nil
            score = nil
            regeneration = nil
            errorMessage = nil
        } catch {
            module = nil
            errorMessage = localized("The selected folder is not a valid Signal Sieve pixel module.")
        }
    }

    private var availableBundledModules: [BundledPixelModuleKind] {
        BundledPixelModuleKind.allCases.filter { bundledModuleURL(for: $0) != nil }
    }

    private func bundledModuleURL(for kind: BundledPixelModuleKind) -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources
            .appendingPathComponent("PixelModules", isDirectory: true)
            .appendingPathComponent(kind.directoryName, isDirectory: true)
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent(ExternalPixelWatermarkEngine.manifestFileName).path
        ) ? url : nil
    }

    private func loadBundledModule(
        _ kind: BundledPixelModuleKind,
        showError: Bool
    ) {
        guard let url = bundledModuleURL(for: kind) else {
            if showError {
                errorMessage = localized("The selected built-in pixel module is unavailable in this build.")
            }
            return
        }
        do {
            module = try ExternalPixelWatermarkEngine.loadModule(at: url)
            bundledModuleKind = kind
            score = nil
            regeneration = nil
            errorMessage = nil
        } catch {
            module = nil
            bundledModuleKind = nil
            if showError {
                errorMessage = localized("The selected built-in pixel module failed integrity validation.")
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = localized("Choose Image")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        imageURL = url
        score = nil
        regeneration = nil
        errorMessage = nil
    }

    private func runScore() {
        guard let imageURL, let module else { return }
        isWorking = true
        errorMessage = nil
        let imageScoped = imageURL.startAccessingSecurityScopedResource()
        let moduleScoped = module.rootURL.startAccessingSecurityScopedResource()
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    return Result<PixelWatermarkScore, ExternalPixelWatermarkError>.success(
                        try ExternalPixelWatermarkEngine.score(
                            imageURL: imageURL,
                            using: module
                        )
                    )
                } catch let error as ExternalPixelWatermarkError {
                    return .failure(error)
                } catch {
                    return .failure(.moduleFailed)
                }
            }.value
            if imageScoped { imageURL.stopAccessingSecurityScopedResource() }
            if moduleScoped { module.rootURL.stopAccessingSecurityScopedResource() }
            isWorking = false
            switch outcome {
            case .success(let value):
                score = value
            case .failure(let error):
                errorMessage = localized(message(for: error))
            }
        }
    }

    private func regenerateCopy() {
        guard let imageURL, let module else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let stem = imageURL.deletingPathExtension().lastPathComponent
        let fileExtension = imageURL.pathExtension.isEmpty ? "png" : imageURL.pathExtension
        panel.nameFieldStringValue = "\(stem)-pixel-clean.\(fileExtension)"
        panel.prompt = localized("Create Regenerated Copy")
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isWorking = true
        errorMessage = nil
        let selectedStrength = strength
        let imageScoped = imageURL.startAccessingSecurityScopedResource()
        let moduleScoped = module.rootURL.startAccessingSecurityScopedResource()
        let destinationScoped = destinationURL.startAccessingSecurityScopedResource()
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    return Result<PixelWatermarkRegenerationResult, ExternalPixelWatermarkError>.success(
                        try ExternalPixelWatermarkEngine.regenerateCopy(
                            imageURL: imageURL,
                            destinationURL: destinationURL,
                            strength: selectedStrength,
                            using: module
                        )
                    )
                } catch let error as ExternalPixelWatermarkError {
                    return .failure(error)
                } catch {
                    return .failure(.moduleFailed)
                }
            }.value
            if imageScoped { imageURL.stopAccessingSecurityScopedResource() }
            if moduleScoped { module.rootURL.stopAccessingSecurityScopedResource() }
            if destinationScoped { destinationURL.stopAccessingSecurityScopedResource() }
            isWorking = false
            switch outcome {
            case .success(let value):
                regeneration = value
                score = value.afterScore ?? score
            case .failure(let error):
                errorMessage = localized(message(for: error))
            }
        }
    }

    private func message(for error: ExternalPixelWatermarkError) -> String {
        switch error {
        case .destinationAlreadyExists:
            "Choose a new filename. SignalSieve never overwrites an existing file."
        case .capabilityUnavailable:
            "The selected module does not declare that capability."
        case .invalidImage, .inputTooLarge:
            "The selected image could not be staged safely."
        case .invalidStrength:
            "Regeneration strength must be a finite value from 0.05 through 0.70."
        case .dimensionsChanged:
            "The module changed the image dimensions, so the output was rejected."
        case .noPixelChange:
            "The module returned identical image bytes, so no regenerated copy was created."
        case .timedOut:
            "The external pixel module timed out."
        case .invalidModuleResponse, .invalidOutput, .outputTooLarge:
            "The module returned an invalid or oversized result."
        case .sourceChangedDuringOperation:
            "The source image changed during processing; the generated copy was rejected."
        case .invalidModule, .unsupportedSchema, .unsafeExecutablePath,
             .destinationMatchesSource, .couldNotStart, .moduleFailed, .couldNotCreateCopy:
            "The external pixel operation failed without modifying the original."
        }
    }

    private var scoreExplanation: String {
        switch bundledModuleKind {
        case .lsb:
            "This model-free score covers classic LSB carrier regularity only. Signal Sieve cannot treat it as an official provider verdict."
        case .spectral:
            "This model-free score covers periodic luminance carriers in a bounded frequency bank. It is not an official provider verdict or proof that a watermark exists."
        case nil:
            "This result comes from the selected external module. Signal Sieve cannot treat it as an official provider verdict."
        }
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
