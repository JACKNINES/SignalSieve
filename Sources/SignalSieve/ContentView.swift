// SPDX-License-Identifier: MPL-2.0
import AppKit
import SwiftUI
import SignalSieveCore

struct ContentView: View {
    @ObservedObject var model: SignalSieveViewModel
    @State private var showsPrivateRules = false
    @State private var showsVaccine = false
    @State private var showsSignatureHunt = false
    @State private var showsClipboardHistory = false
    @State private var showsReveal = false
    @State private var showsWatermarkProbe = false
    @State private var showsRewriteIntegrity = false
    @State private var showsPixelWatermarkModule = false
    @State private var toolbarSection: ToolbarSection = .review
    @State private var expandedPanel: EditorPanel?

    /// Which editor panel, if any, is currently taking the full window width.
    private enum EditorPanel: String, Identifiable {
        case input
        case result

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()

            editors
                .frame(minHeight: 330)

            Divider()
            findingsPanel
            if model.binaryAnalysis.isDetected {
                Divider()
                binaryGuardPanel
            }
            if model.codeAnalysis.isLikelyCode {
                Divider()
                codeGuardPanel
            }
            Divider()
            statusBar
        }
        .onReceive(model.$input) { _ in model.inspect() }
        .sheet(isPresented: $model.showsPatternReport) {
            PatternReportView(
                report: model.patternReport,
                sampleCount: model.patternSampleCount,
                language: model.language,
                onClear: model.clearPatternMemory,
                onCopy: model.copyFindingText
            )
        }
        .sheet(isPresented: $showsPrivateRules) {
            PrivateRulesView(
                rules: model.privateRules,
                language: model.language,
                onAdd: model.addPrivateRule,
                onRemove: model.removePrivateRule
            )
        }
        .sheet(isPresented: $showsClipboardHistory) {
            ClipboardHistoryView(
                entries: model.clipboardHistory,
                language: model.language,
                onOpen: model.openClipboardHistoryEntry,
                onDelete: model.removeClipboardHistoryEntry,
                onClear: model.clearClipboardHistory
            )
        }
        .sheet(isPresented: $showsReveal) {
            RevealView(
                fragments: model.revealedFragments,
                language: model.language,
                onCopy: model.copyFindingText
            )
        }
        .sheet(isPresented: $showsWatermarkProbe) {
            WatermarkProbeView(
                report: model.watermarkProbeReport,
                language: model.language,
                onCopy: model.copyFindingText
            )
        }
        .sheet(isPresented: $showsRewriteIntegrity) {
            RewriteIntegrityView(
                original: model.input,
                candidate: $model.output,
                language: model.language,
                onCopy: model.copyFindingText
            )
        }
        .sheet(isPresented: $showsPixelWatermarkModule) {
            PixelWatermarkModuleView(language: model.language)
        }
        .sheet(
            isPresented: $model.showsFileProvenance,
            onDismiss: model.clearPendingClipboardImage
        ) {
            FileProvenanceView(
                language: model.language,
                initialClipboardImage: model.pendingClipboardImage,
                onCopy: model.copyFindingText,
                onUseClipboardImage: model.useClipboardImage
            )
        }
        .sheet(isPresented: $showsVaccine) {
            VaccineView(language: model.language, onCopy: model.copyFindingText)
        }
        .sheet(isPresented: $showsSignatureHunt) {
            SignatureHuntView(language: model.language, onCopy: model.copyFindingText)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.blue.opacity(0.14))
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Signal Sieve")
                    .font(.title2.weight(.semibold))
                Text(model.localized("Local text privacy and pattern analysis"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ThemePicker(selection: $model.theme, localized: model.localized)

            Menu {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        model.language = language
                    } label: {
                        if model.language == language {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            } label: {
                Label(model.language.displayName, systemImage: "globe")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.10), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(model.localized("Language"))

            statusPill(
                model.activeGuardLabel,
                systemImage: model.isActiveProtectionEnabled ? "eye.circle.fill" : "eye.slash.circle",
                color: model.isActiveProtectionEnabled ? .blue : .secondary
            )

            statusPill(model.localized("Offline"), systemImage: "lock.shield.fill", color: .green)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            LinearGradient(
                colors: [.blue.opacity(0.055), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    /// One contextual row instead of three permanently stacked ones. The
    /// segmented control decides which tools are on screen, which frees the
    /// vertical space the three row headers used to take.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ToolbarSectionPicker(selection: $toolbarSection, localized: model.localized)
                    .accessibilityLabel(model.localized("Toolbar section"))

                Text(model.localized(toolbarSection.hint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            // Scrolls rather than squeezing, so a long button title is never
            // truncated at narrow window widths.
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        switch toolbarSection {
                        case .review: reviewControls
                        case .analyze: analyzeControls
                        case .clean: cleanControls
                        }
                    }
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .frame(height: 26)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var reviewControls: some View {
        Button(model.localized("Paste"), systemImage: "doc.on.clipboard", action: model.paste)
            .sieveToolbarButton()
        Button(model.localized("Inspect"), systemImage: "magnifyingglass", action: model.inspect)
            .sieveToolbarButton(.primary)
        Button(model.localized("Reveal"), systemImage: "eye.fill") {
            showsReveal = true
        }
        .sieveToolbarButton()
        .disabled(model.revealedFragments.isEmpty)
        .help(model.localized("Reveal known invisible encodings without executing their contents."))

        SieveToolbarDivider()

        Menu {
            Button(model.localized("Remember Current Text"), action: model.rememberCurrentText)
            Button(model.localized("View Pattern Report"), action: model.showPatternReport)
            Divider()
            Button(model.localized("Clear Session Memory"), role: .destructive, action: model.clearPatternMemory)
        } label: {
            SieveMenuLabel(title: model.localized("Memory"), systemImage: "brain.head.profile")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()

        Button {
            showsClipboardHistory = true
        } label: {
            HStack(spacing: 5) {
                Label(model.localized("History"), systemImage: "clock.arrow.circlepath")
                if model.clipboardHistoryCount > 0 {
                    Text("\(model.clipboardHistoryCount)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
            }
        }
        .sieveToolbarButton()
        .help(model.localized("View copies recorded during this session"))

        SieveToolbarDivider()

        Menu {
            Toggle(model.localized("Monitor New Clipboard Text"), isOn: $model.isActiveProtectionEnabled)
            Divider()
            Text(model.formatted(
                "%d of 6 warning types enabled",
                model.enabledWarningCount
            ))
            Toggle(model.localized("Warn About Hidden Unicode"), isOn: $model.warnsAboutHiddenUnicode)
            Toggle(model.localized("Warn About Tracked Links"), isOn: $model.warnsAboutTrackedLinks)
            Toggle(model.localized("Warn About Repeated Patterns"), isOn: $model.warnsAboutPatterns)
            Toggle(model.localized("Warn About Source-Code Risks"), isOn: $model.warnsAboutCodeRisks)
            Toggle(model.localized("Warn About Binary or Encoded Data"), isOn: $model.warnsAboutBinaryContent)
            Toggle(model.localized("Warn About File or Image Metadata"), isOn: $model.warnsAboutFileMetadata)
            Button(model.localized("Enable All Warning Types"), action: model.enableAllWarningTypes)
                .disabled(model.enabledWarningCount == 6)
            Divider()
            Toggle(model.localized("Automatically Clean Copied Links"), isOn: $model.automaticallyCleansLinks)
            Text(model.localized("Monitoring runs locally while SignalSieve is open."))
        } label: {
            SieveMenuLabel(title: model.localized("Active Guard"), systemImage: "eye.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()

        Button(model.localized("Rules"), systemImage: "slider.horizontal.3") {
            showsPrivateRules = true
        }
        .sieveToolbarButton()
    }

    @ViewBuilder
    private var analyzeControls: some View {
        Button(model.localized("Vaccine"), systemImage: "syringe.fill") {
            showsVaccine = true
        }
        .sieveToolbarButton()
        Button(model.localized("Signature Hunt"), systemImage: "scope") {
            showsSignatureHunt = true
        }
        .sieveToolbarButton()
        Button(model.localized("File Inspector"), systemImage: "doc.text.magnifyingglass") {
            model.openFileProvenanceInspector()
        }
        .sieveToolbarButton()
        Button(model.localized("Pixel Lab"), systemImage: "photo.badge.magnifyingglass") {
            showsPixelWatermarkModule = true
        }
        .sieveToolbarButton()

        SieveToolbarDivider()

        // Tinted: these two act on whatever is in the Input panel right now.
        Button(model.localized("Surface Regularity"), systemImage: "waveform.badge.magnifyingglass") {
            model.runWatermarkProbe()
            showsWatermarkProbe = true
        }
        .sieveToolbarButton(.accented)
        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(model.localized("Screens visible statistical regularity locally without claiming provider attribution."))

        Button(model.localized("Rewrite Integrity"), systemImage: "arrow.left.arrow.right.square") {
            model.runRewriteIntegrity()
            showsRewriteIntegrity = true
        }
        .sieveToolbarButton(.accented)
        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(model.localized("Compares Input and Result or creates an optional local rewrite without claiming semantic equivalence."))
    }

    @ViewBuilder
    private var cleanControls: some View {
        Button(model.localized("Safe Clean"), systemImage: "wand.and.stars") { model.clean(mode: .safe) }
            .sieveToolbarButton(.accented)
        Button(model.localized("Strict Clean"), systemImage: "wand.and.sparkles") { model.clean(mode: .strict) }
            .sieveToolbarButton()
        Button(model.localized("Clean Links"), systemImage: "link.badge.plus", action: model.cleanLinks)
            .sieveToolbarButton()
        Button(
            model.localized("Code Clean (Review)"),
            systemImage: "chevron.left.forwardslash.chevron.right",
            action: model.cleanCodeForReview
        )
        .sieveToolbarButton()
        .disabled(!model.codeAnalysis.isLikelyCode || model.codeAnalysis.sanitizableFindingCount == 0)
        .help(model.localized("Creates reviewable output without guessing replacements for look-alike identifiers."))

        SieveToolbarDivider()

        Button(model.localized("Visual Transfer"), systemImage: "viewfinder", action: model.visualTransfer)
            .sieveToolbarButton()
            .disabled(model.isProcessing || model.input.isEmpty || model.codeAnalysis.isLikelyCode)
            .help(model.codeAnalysis.isLikelyCode
                ? model.localized("Visual Transfer is disabled for source code because OCR can alter syntax.")
                : model.localized("Renders text to an image and reads it back with local OCR."))

        Spacer(minLength: 8)

        Button(model.localized("Use Result"), systemImage: "arrow.left", action: model.moveOutputToInput)
            .sieveToolbarButton()
            .disabled(model.output.isEmpty)
        Button(model.localized("Copy Result"), systemImage: "doc.on.doc", action: model.copyOutput)
            .sieveToolbarButton(.primary)
            .disabled(model.output.isEmpty)
    }

    private func statusPill(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private var editors: some View {
        switch expandedPanel {
        case .input:
            inputPanel
        case .result:
            resultPanel
        case nil:
            HSplitView {
                inputPanel
                resultPanel
            }
        }
    }

    private var inputPanel: some View {
        editorPanel(
            panel: .input,
            title: model.localized("Input"),
            subtitle: model.localized("Paste or type text to inspect"),
            systemImage: "text.cursor",
            tint: .blue,
            expandHelp: model.localized("Expand Input to full width"),
            text: $model.input
        )
    }

    private var resultPanel: some View {
        editorPanel(
            panel: .result,
            title: model.localized("Result"),
            subtitle: model.localized("Review before copying"),
            systemImage: "checkmark.square",
            tint: .green,
            expandHelp: model.localized("Expand Result to full width"),
            text: $model.output
        )
    }

    private func editorPanel(
        panel: EditorPanel,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        expandHelp: String,
        text: Binding<String>
    ) -> some View {
        let isExpanded = expandedPanel == panel
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    expandedPanel = isExpanded ? nil : panel
                } label: {
                    Image(systemName: isExpanded
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(isExpanded ? model.localized("Restore both panels") : expandHelp)
                .accessibilityLabel(isExpanded ? model.localized("Restore both panels") : expandHelp)
            }

            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
                }
        }
        .padding(14)
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var findingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.localized("Findings")).font(.headline)
                Text("\(model.inspection.findings.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.14), in: Capsule())
                Spacer()
                if !model.inspection.findings.isEmpty {
                    Button(model.localized("Copy Findings"), systemImage: "doc.on.doc") {
                        model.copyFindingText(FindingReportFormatter.hiddenReport(
                            model.inspection,
                            language: model.language
                        ))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                if model.inspection.changesUnderNFC || model.inspection.changesUnderNFKC {
                    Text(model.localized("Unicode normalization changes this text"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                riskLegend
            }

            if model.inspection.findings.isEmpty {
                Label(model.localized("No known hidden Unicode risk found."), systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(.green.opacity(0.16), lineWidth: 0.75)
                    }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.inspection.findings) { finding in
                            ZStack(alignment: .bottomTrailing) {
                                Button {
                                    if let url = finding.researchURL {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(finding.codePoint).font(.caption.monospaced().weight(.semibold))
                                            Spacer()
                                            Image(systemName: "arrow.up.right.square")
                                        }
                                        Label(
                                            AppLocalization.riskLabel(finding.riskLevel, language: model.language),
                                            systemImage: "circle.fill"
                                        )
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(finding.riskLevel.color)
                                        Label(
                                            AppLocalization.evidenceConfidenceLabel(
                                                finding.evidenceConfidence,
                                                language: model.language
                                            ),
                                            systemImage: "checkmark.seal"
                                        )
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.blue)
                                        Text(AppLocalization.hiddenKind(finding.kind, language: model.language))
                                            .font(.subheadline.weight(.medium))
                                        Text(AppLocalization.hiddenContext(finding.context, language: model.language))
                                            .font(.caption)
                                            .foregroundStyle(finding.riskLevel == .clear ? .green : .secondary)
                                        Text(model.formatted("Scalar %d · %@", finding.scalarPosition, finding.displayName))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.trailing, 34)
                                    }
                                    .frame(width: 275, alignment: .leading)
                                    .padding(10)
                                    .background(
                                        finding.riskLevel.color.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(finding.riskLevel.color.opacity(0.65), lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help(model.formatted(
                                    "Search for an explanation of %@. Your original text is not included.",
                                    finding.codePoint
                                ))
                                .accessibilityLabel(
                                    model.formatted(
                                        "Research %@, %@, %@",
                                        finding.codePoint,
                                        AppLocalization.hiddenKind(finding.kind, language: model.language),
                                        AppLocalization.riskLabel(finding.riskLevel, language: model.language)
                                    )
                                )

                                FindingCopyButton(title: model.localized("Copy Finding")) {
                                    model.copyFindingText(FindingReportFormatter.hiddenFinding(
                                        finding,
                                        language: model.language
                                    ))
                                }
                                .padding(7)
                            }
                            .contextMenu {
                                Button(model.localized("Copy Finding"), systemImage: "doc.on.doc") {
                                    model.copyFindingText(FindingReportFormatter.hiddenFinding(
                                        finding,
                                        language: model.language
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 100)
    }

    private var riskLegend: some View {
        HStack(spacing: 10) {
            legendItem(label: model.localized("Clear"), color: .green)
            legendItem(level: .suspicious)
            legendItem(level: .medium)
            legendItem(level: .high)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.localized(
            "Risk legend: green clear, yellow suspicious, orange medium risk, red high risk"
        ))
    }

    private var codeGuardPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(model.localized("Code Guard"), systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.headline)
                Text(codeLanguageStatus)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.12), in: Capsule())
                    .help(AppLocalization.text(
                        model.codeAnalysis.languageConfidence.rawValue,
                        language: model.language
                    ))
                Text("\(model.codeAnalysis.findings.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.14), in: Capsule())
                Spacer()
                if !model.codeAnalysis.findings.isEmpty {
                    Button(model.localized("Copy Findings"), systemImage: "doc.on.doc") {
                        model.copyFindingText(FindingReportFormatter.codeReport(
                            model.codeAnalysis,
                            language: model.language
                        ))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                Text(model.localized("Code is never modified automatically"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.codeAnalysis.findings.isEmpty {
                Label(model.localized("No known source-code Unicode risks found."), systemImage: "checkmark.shield.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.codeAnalysis.findings) { finding in
                            ZStack(alignment: .bottomTrailing) {
                                Button {
                                    if let url = finding.researchURL {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(finding.codePoint)
                                                .font(.caption.monospaced().weight(.semibold))
                                            Spacer()
                                            Image(systemName: "arrow.up.right.square")
                                        }
                                        Label(
                                            AppLocalization.riskLabel(finding.kind.riskLevel, language: model.language),
                                            systemImage: "circle.fill"
                                        )
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(finding.kind.riskLevel.color)
                                        Label(
                                            AppLocalization.evidenceConfidenceLabel(
                                                finding.evidenceConfidence,
                                                language: model.language
                                            ),
                                            systemImage: "checkmark.seal"
                                        )
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.blue)
                                        Text(AppLocalization.codeKind(finding.kind, language: model.language))
                                            .font(.subheadline.weight(.medium))
                                        Text(model.formatted("Line %d · Column %d", finding.line, finding.column))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(AppLocalization.codeDetail(finding.kind, language: model.language))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .padding(.trailing, 34)
                                    }
                                    .frame(width: 280, alignment: .leading)
                                    .padding(10)
                                    .background(
                                        finding.kind.riskLevel.color.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(finding.kind.riskLevel.color.opacity(0.65), lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help(model.formatted(
                                    "Search for an explanation of %@. Your original code is not included.",
                                    finding.codePoint
                                ))

                                FindingCopyButton(title: model.localized("Copy Finding")) {
                                    model.copyFindingText(FindingReportFormatter.codeFinding(
                                        finding,
                                        language: model.language
                                    ))
                                }
                                .padding(7)
                            }
                            .contextMenu {
                                Button(model.localized("Copy Finding"), systemImage: "doc.on.doc") {
                                    model.copyFindingText(FindingReportFormatter.codeFinding(
                                        finding,
                                        language: model.language
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 90)
    }

    private var binaryGuardPanel: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.localized("Binary Guard"))
                        .font(.headline)
                    Text(AppLocalization.text(model.binaryAnalysis.displayName, language: model.language))
                        .font(.subheadline.weight(.medium))
                    Text(model.localized("Encoded or binary-looking content is reported, not decoded or executed."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.formatted("Approximately %d byte(s)", model.binaryAnalysis.byteCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 38)
            }

            FindingCopyButton(title: model.localized("Copy Finding")) {
                model.copyFindingText(FindingReportFormatter.binaryFinding(
                    model.binaryAnalysis,
                    language: model.language
                ))
            }
            .padding(7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.yellow.opacity(0.05))
    }

    private var codeLanguageStatus: String {
        guard model.codeAnalysis.languageDetection.primary != nil else {
            return model.localized("Source code detected")
        }
        return model.formatted("%@ code detected", model.codeAnalysis.detectedLanguage)
    }

    private func legendItem(level: HiddenElementRiskLevel) -> some View {
        legendItem(label: AppLocalization.riskLabel(level, language: model.language), color: level.color)
    }

    private func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isProcessing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "info.circle")
            }
            Text(model.status).lineLimit(1)
            Spacer()
            Text(model.formatted(
                "%d scalars · %d UTF-16 units",
                model.inspection.scalarCount,
                model.inspection.utf16Count
            ))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private extension HiddenElementRiskLevel {
    var color: Color {
        switch self {
        case .clear: .green
        case .suspicious: .yellow
        case .medium: .orange
        case .high: .red
        }
    }
}
