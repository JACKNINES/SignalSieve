// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import SwiftUI

struct RewriteIntegrityView: View {
    let original: String
    @Binding var candidate: String
    let language: AppLanguage
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var modelName = "qwen3.5:4b"
    @State private var installedModels: [String] = []
    @State private var isLoadingModels = false
    @State private var rewriteStyle: LocalRewriteStyle = .paraphrase
    @State private var isRewriting = false
    @State private var rewriteStatus: String?
    @State private var lastRewrite: LocalRewriteResult?

    private var report: RewriteIntegrityReport {
        RewriteIntegrityAnalyzer.analyze(original: original, candidate: candidate)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    localRewriteCard
                    assessmentCard
                    if report.originalTokenCount > 0 || report.candidateTokenCount > 0 {
                        metricCard
                    }
                    semanticCard
                    findings
                    limitationCard
                }
                .padding(18)
            }
            Divider()
            HStack {
                Text(localized("Local comparison · optional rewrite uses loopback Ollama only"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(localized("Copy Findings"), systemImage: "doc.on.doc") {
                    onCopy(FindingReportFormatter.rewriteIntegrityReport(
                        report,
                        language: language
                    ))
                }
                Button(localized("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 680, minHeight: 590)
        .task {
            refreshInstalledModels()
        }
    }

    private var localRewriteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(localized("Optional Local Rewrite"), systemImage: "desktopcomputer")
                    .font(.headline)
                Spacer()
                Text(localized("Best effort · never a watermark guarantee"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            Text(localized("Uses an already-installed Ollama model on 127.0.0.1. Missing models are never downloaded automatically by Signal Sieve."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(
                localized(LocalRewriteEngine.statisticalBiasWarning),
                systemImage: "waveform.path.ecg"
            )
                .font(.caption)
                .foregroundStyle(.orange)

            HStack(spacing: 10) {
                if installedModels.isEmpty {
                    TextField(localized("Installed model name"), text: $modelName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180)
                } else {
                    Picker(localized("Installed model"), selection: $modelName) {
                        ForEach(installedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .frame(minWidth: 180)
                }
                Button {
                    refreshInstalledModels()
                } label: {
                    if isLoadingModels {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help(localized("Refresh Installed Models"))
                .disabled(isLoadingModels || LocalRewriteEngine.executableURL() == nil)
                Picker(localized("Rewrite style"), selection: $rewriteStyle) {
                    ForEach(LocalRewriteStyle.allCases) { style in
                        Text(AppLocalization.text(style.rawValue, language: language))
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Button(localized("Rewrite Locally"), systemImage: "wand.and.stars") {
                    runLocalRewrite()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isRewriting
                        || original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || LocalRewriteEngine.executableURL() == nil
                )
            }

            if isRewriting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(localized("Rewriting with the local model…"))
                }
                .font(.caption)
            } else if LocalRewriteEngine.executableURL() == nil {
                Label(
                    localized("Ollama was not found in a supported local installation path."),
                    systemImage: "exclamationmark.triangle"
                )
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if installedModels.isEmpty && !isLoadingModels {
                Label(
                    localized("Ollama is available, but no local models were found. Signal Sieve will not download one automatically."),
                    systemImage: "externaldrive.badge.questionmark"
                )
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let rewriteStatus {
                Text(rewriteStatus)
                    .font(.caption)
                    .foregroundStyle(lastRewrite == nil ? .red : .green)
            }
            if let lastRewrite {
                HStack(spacing: 16) {
                    Label(
                        formatted(
                            "%d%% lexical divergence",
                            Int((lastRewrite.integrityReport.lexicalDivergence * 100).rounded())
                        ),
                        systemImage: "character.book.closed"
                    )
                    Label(
                        localized(lastRewrite.integrityReport.hasProtectedValueChanges
                            ? "Protected values changed — review required"
                            : "No exact protected-value changes detected"),
                        systemImage: lastRewrite.integrityReport.hasProtectedValueChanges
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle"
                    )
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(lastRewrite.integrityReport.hasProtectedValueChanges ? .red : .blue)
            }
        }
        .padding(14)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.blue.opacity(0.25), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.square")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("Rewrite Integrity"))
                    .font(.title2.weight(.semibold))
                Text(localized("Compares Input and Result without rewriting either one"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var assessmentCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: assessmentIcon)
                .font(.title2)
                .foregroundStyle(assessmentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.text(report.assessment.rawValue, language: language))
                    .font(.headline)
                Text(assessmentDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(assessmentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(assessmentColor.opacity(0.45), lineWidth: 1)
        }
    }

    private var metricCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(localized("Transformation metrics"))
                .font(.headline)
            metric(
                label: "Lexical divergence",
                value: report.lexicalDivergence,
                detail: formatted("%d%% of unique words differ", Int((report.lexicalDivergence * 100).rounded()))
            )
            metric(
                label: "Length ratio",
                value: min(report.lengthRatio, 2) / 2,
                detail: formatted(
                    "%d original words · %d candidate words",
                    report.originalTokenCount,
                    report.candidateTokenCount
                )
            )
        }
        .padding(14)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(label: String, value: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(localized(label)).font(.subheadline.weight(.medium))
                Spacer()
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: value).tint(.blue)
        }
    }

    private var semanticCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.diamond")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("Semantic equivalence"))
                    .font(.headline)
                Text(AppLocalization.evidenceConfidenceLabel(
                    report.semanticEquivalenceConfidence,
                    language: language
                ))
                    .font(.subheadline.weight(.medium))
                Text(localized("Lexical change cannot establish that facts, intent, tone, or watermark status were preserved."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var findings: some View {
        if report.findings.isEmpty {
            Label(
                localized("No exact changes to numbers, URLs, or quoted text were detected."),
                systemImage: "info.circle"
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(localized("Protected-value changes"))
                    .font(.headline)
                ForEach(report.findings) { finding in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: finding.change == .removed
                            ? "minus.circle.fill"
                            : "plus.circle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(localized(finding.kind.rawValue)) · \(localized(finding.change.rawValue))")
                                .font(.subheadline.weight(.semibold))
                            Text(finding.value)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Text(AppLocalization.evidenceConfidenceLabel(
                                finding.evidenceConfidence,
                                language: language
                            ))
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        FindingCopyButton(title: localized("Copy Finding")) {
                            onCopy(FindingReportFormatter.rewriteIntegrityFinding(
                                finding,
                                language: language
                            ))
                        }
                    }
                    .padding(11)
                    .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }

    private var limitationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(localized("Review boundary"), systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(localized("A clean protected-value comparison is not approval. Read the candidate and verify facts before using it."))
            Text(localized("Source code is deliberately blocked because rewriting identifiers, literals, or comments can change behavior or security."))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(14)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var assessmentColor: Color {
        switch report.assessment {
        case .protectedValuesChanged, .codeNotSupported: .red
        case .inputTooLarge: .orange
        case .reviewRequired: .blue
        case .noCandidate: .yellow
        case .identical: .secondary
        }
    }

    private var assessmentIcon: String {
        switch report.assessment {
        case .protectedValuesChanged, .codeNotSupported: "exclamationmark.triangle.fill"
        case .inputTooLarge: "text.badge.xmark"
        case .reviewRequired: "person.crop.circle.badge.questionmark"
        case .noCandidate: "doc.badge.plus"
        case .identical: "equal.circle"
        }
    }

    private var assessmentDetail: String {
        switch report.assessment {
        case .noCandidate:
            localized("Generate or paste a candidate into Result before comparing it.")
        case .identical:
            localized("Input and Result are exactly the same; no transformation was evaluated.")
        case .reviewRequired:
            localized("No protected-value differences were found, but meaning still requires human review.")
        case .protectedValuesChanged:
            localized("Numbers, URLs, or quoted text changed. Resolve every exact difference before using the candidate.")
        case .codeNotSupported:
            localized("Use Code Guard and tests for source code. Rewrite Integrity will not approve code transformations.")
        case .inputTooLarge:
            localized("The comparison was stopped at the local safety limit instead of analyzing a partial rewrite.")
        }
    }

    private func runLocalRewrite() {
        let source = original
        let selectedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedStyle = rewriteStyle
        isRewriting = true
        rewriteStatus = nil
        lastRewrite = nil

        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    return Result<LocalRewriteResult, LocalRewriteError>.success(
                        try LocalRewriteEngine.rewrite(
                            source,
                            model: selectedModel,
                            style: selectedStyle
                        )
                    )
                } catch let error as LocalRewriteError {
                    return .failure(error)
                } catch {
                    return .failure(.processFailed)
                }
            }.value

            isRewriting = false
            switch outcome {
            case .success(let result):
                candidate = result.text
                lastRewrite = result
                rewriteStatus = localized("The local rewrite was placed in Result. Read and verify it before copying.")
            case .failure(let error):
                lastRewrite = nil
                rewriteStatus = localized(errorMessage(for: error))
            }
        }
    }

    private func refreshInstalledModels() {
        guard !isLoadingModels, LocalRewriteEngine.executableURL() != nil else { return }
        isLoadingModels = true
        Task {
            let models = await Task.detached(priority: .utility) {
                (try? LocalRewriteEngine.installedModels()) ?? []
            }.value
            installedModels = models
            if let first = models.first, !models.contains(modelName) {
                modelName = first
            }
            isLoadingModels = false
        }
    }

    private func errorMessage(for error: LocalRewriteError) -> String {
        switch error {
        case .ollamaNotInstalled:
            "Ollama was not found in a supported local installation path."
        case .serverUnavailable:
            "Ollama is installed, but its local service is not available on 127.0.0.1."
        case .invalidModelName:
            "The model name contains unsupported characters."
        case .modelNotInstalled:
            "That model is not installed locally. Signal Sieve did not download it."
        case .emptyInput:
            "Paste prose into Input before requesting a rewrite."
        case .inputTooLarge:
            "The text exceeds the local rewrite safety limit."
        case .sourceCodeNotSupported:
            "Local rewriting is blocked for source code."
        case .timedOut:
            "The local model timed out without changing Result."
        case .outputTooLarge:
            "The local model exceeded the bounded output limit."
        case .couldNotStart, .processFailed, .invalidOutput:
            "The local rewrite failed without changing Result."
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
