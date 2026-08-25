// SPDX-License-Identifier: MPL-2.0
import AppKit
import Combine
import Foundation
import SignalSieveCore

private struct ClipboardCoreAnalysis: Sendable {
    let copiedCodeAnalysis: CodeGuardAnalysis
    let initialLinkCleaning: URLCleaningResult
    let effectiveText: String
    let linkWasPreparedForAutomaticCleaning: Bool
    let automationResult: ClipboardAutomationResult
    let shouldFlattenRichText: Bool
    let originalAnalysis: ClipboardProtectionAnalysis
    let finalAnalysis: ClipboardProtectionAnalysis
    let finalLinkCleaning: URLCleaningResult
}

/// Serializes CPU-heavy clipboard work away from AppKit's main actor. Pending
/// cancelled requests are discarded before they allocate analysis state, so a
/// burst of copy events cannot create an unbounded detached-task storm.
private actor ClipboardAnalysisWorker {
    func analyze(
        text: String,
        recentPatternTexts: [String],
        customRules: [CustomURLRule],
        automaticallyCleansLinks: Bool,
        automationProtocol: ClipboardAutomationProtocol,
        typeInventory: ClipboardTypeInventory,
        isPrivacySensitive: Bool
    ) -> ClipboardCoreAnalysis? {
        guard !Task.isCancelled else { return nil }
        let copiedCodeAnalysis = CodeGuardAnalyzer.analyze(text)
        let initialLinkCleaning = URLTrackerCleaner.cleanLinks(in: text, customRules: customRules)
        let hasNonTextRepresentation = typeInventory.kinds.contains(.image)
            || typeInventory.kinds.contains(.fileURL)
        let mayRewritePlainText = !copiedCodeAnalysis.isLikelyCode
            && !hasNonTextRepresentation
            && !isPrivacySensitive

        var effectiveText = text
        var linkWasPreparedForAutomaticCleaning = false
        if automaticallyCleansLinks,
           mayRewritePlainText,
           initialLinkCleaning.linksChanged > 0 {
            effectiveText = initialLinkCleaning.text
            linkWasPreparedForAutomaticCleaning = true
        }
        let automationResult = ClipboardAutomationPolicy.transform(
            effectiveText,
            using: automationProtocol,
            isLikelyCode: copiedCodeAnalysis.isLikelyCode,
            hasNonTextRepresentation: hasNonTextRepresentation,
            isPrivacySensitive: isPrivacySensitive
        )
        effectiveText = automationResult.text
        let shouldFlattenRichText = ClipboardAutomationPolicy.shouldFlattenRichText(
            using: automationProtocol,
            hasRichTextRepresentation: typeInventory.containsRichTextRepresentation,
            skipReason: automationResult.skipReason
        )
        let originalAnalysis = ClipboardProtectionAnalyzer.analyze(
            text,
            recentPatternTexts: recentPatternTexts,
            customRules: customRules
        )
        let finalAnalysis = effectiveText == text
            ? originalAnalysis
            : ClipboardProtectionAnalyzer.analyze(
                effectiveText,
                recentPatternTexts: [],
                customRules: customRules
            )
        let finalLinkCleaning = effectiveText == text
            ? initialLinkCleaning
            : URLTrackerCleaner.cleanLinks(in: effectiveText, customRules: customRules)
        guard !Task.isCancelled else { return nil }
        return ClipboardCoreAnalysis(
            copiedCodeAnalysis: copiedCodeAnalysis,
            initialLinkCleaning: initialLinkCleaning,
            effectiveText: effectiveText,
            linkWasPreparedForAutomaticCleaning: linkWasPreparedForAutomaticCleaning,
            automationResult: automationResult,
            shouldFlattenRichText: shouldFlattenRichText,
            originalAnalysis: originalAnalysis,
            finalAnalysis: finalAnalysis,
            finalLinkCleaning: finalLinkCleaning
        )
    }
}

@MainActor
final class SignalSieveViewModel: ObservableObject {
    @Published var input = ""
    @Published var output = ""
    @Published var showsPatternReport = false
    @Published var showsFileProvenance = false
    @Published private(set) var pendingClipboardImage: ClipboardImagePayload?
    @Published private(set) var inspection = HiddenTextAnalyzer.inspect("")
    @Published private(set) var covertChannelReport = CovertTextChannelAnalyzer.analyze("")
    @Published private(set) var codeAnalysis = CodeGuardAnalyzer.analyze("")
    @Published private(set) var binaryAnalysis = BinaryContentDetector.analyze("")
    @Published private(set) var identifierAnalysis = OpaqueIdentifierAnalyzer.analyze("")
    @Published private(set) var scamAnalysis = ScamAttemptDetector.analyze("")
    @Published private(set) var adaptiveAnalysis = AdaptiveCopyAnalysis(
        sampleCountBeforeLearning: 0,
        anomalyScore: 0,
        deviations: [],
        wasEligibleForLearning: false
    )
    @Published private(set) var watermarkProbeReport = WatermarkProbeAnalyzer.analyze("")
    @Published private(set) var rewriteIntegrityReport = RewriteIntegrityAnalyzer.analyze(
        original: "",
        candidate: ""
    )
    @Published private(set) var linkCleaningReport = URLTrackerCleaner.cleanLinks(in: "")
    @Published private(set) var revealedFragments: [RevealedInvisibleFragment] = []
    @Published private(set) var status = "Paste text to get started."
    @Published private(set) var isProcessing = false
    @Published private(set) var patternTexts: [String] = []
    @Published private(set) var patternReport = PatternReport(sampleCount: 0, findings: [])
    @Published private(set) var clipboardHistory: [ClipboardHistoryEntry] = []
    @Published private(set) var privateRules: [CustomURLRule]
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: PreferenceKey.language)
            status = formatted("Language changed to %@.", language.displayName)
        }
    }

    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: PreferenceKey.theme) }
    }

    @Published var isActiveProtectionEnabled: Bool {
        didSet {
            defaults.set(isActiveProtectionEnabled, forKey: PreferenceKey.activeProtection)
            isActiveProtectionEnabled ? startClipboardMonitoring() : stopClipboardMonitoring()
        }
    }
    @Published var warnsAboutHiddenUnicode: Bool {
        didSet { defaults.set(warnsAboutHiddenUnicode, forKey: PreferenceKey.hiddenUnicodeWarnings) }
    }
    @Published var warnsAboutTrackedLinks: Bool {
        didSet { defaults.set(warnsAboutTrackedLinks, forKey: PreferenceKey.trackedLinkWarnings) }
    }
    @Published var warnsAboutPatterns: Bool {
        didSet { defaults.set(warnsAboutPatterns, forKey: PreferenceKey.patternWarnings) }
    }
    @Published var warnsAboutCodeRisks: Bool {
        didSet { defaults.set(warnsAboutCodeRisks, forKey: PreferenceKey.codeWarnings) }
    }
    @Published var warnsAboutBinaryContent: Bool {
        didSet { defaults.set(warnsAboutBinaryContent, forKey: PreferenceKey.binaryWarnings) }
    }
    @Published var warnsAboutFileMetadata: Bool {
        didSet { defaults.set(warnsAboutFileMetadata, forKey: PreferenceKey.fileMetadataWarnings) }
    }
    @Published var warnsAboutOpaqueIdentifiers: Bool {
        didSet { defaults.set(warnsAboutOpaqueIdentifiers, forKey: PreferenceKey.identifierWarnings) }
    }
    @Published var warnsAboutScamAttempts: Bool {
        didSet { defaults.set(warnsAboutScamAttempts, forKey: PreferenceKey.scamWarnings) }
    }
    @Published var isAdaptiveModelEnabled: Bool {
        didSet { defaults.set(isAdaptiveModelEnabled, forKey: PreferenceKey.adaptiveModelEnabled) }
    }
    @Published var clipboardAlertVisibility: ClipboardAlertVisibility {
        didSet {
            defaults.set(
                clipboardAlertVisibility.rawValue,
                forKey: PreferenceKey.clipboardAlertVisibility
            )
        }
    }
    @Published var clipboardAutomationProtocol: ClipboardAutomationProtocol {
        didSet {
            defaults.set(
                clipboardAutomationProtocol.rawValue,
                forKey: PreferenceKey.clipboardAutomationProtocol
            )
            if automaticallyPreparesInputResult {
                prepareAutomaticInputResult()
            }
        }
    }
    @Published var automaticallyCleansLinks: Bool {
        didSet { defaults.set(automaticallyCleansLinks, forKey: PreferenceKey.automaticLinkCleaning) }
    }
    @Published var automaticallyPreparesInputResult: Bool {
        didSet {
            defaults.set(
                automaticallyPreparesInputResult,
                forKey: PreferenceKey.automaticInputResult
            )
            if automaticallyPreparesInputResult {
                prepareAutomaticInputResult()
            } else {
                automaticInputResultTask?.cancel()
                automaticInputResultTask = nil
            }
        }
    }

    private let privateRulesURL: URL
    private let adaptiveModelURL: URL
    private let defaults: UserDefaults
    private let noticePanel = ClipboardNoticePanelController()
    private var clipboardMonitor: AnyCancellable?
    private let clipboardAnalysisWorker = ClipboardAnalysisWorker()
    private var clipboardAnalysisTask: Task<Void, Never>?
    private var automaticVisualTransferTask: Task<Void, Never>?
    private var automaticInputResultTask: Task<Void, Never>?
    private var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    private var openMainWindow: (() -> Void)?
    private var adaptiveCopyModel: AdaptiveCopyModel

    var patternSampleCount: Int { patternTexts.count }
    var clipboardHistoryCount: Int { clipboardHistory.count }
    var privateRuleCount: Int { privateRules.count }
    var enabledWarningCount: Int {
        [warnsAboutHiddenUnicode, warnsAboutTrackedLinks, warnsAboutPatterns, warnsAboutCodeRisks, warnsAboutBinaryContent, warnsAboutFileMetadata, warnsAboutOpaqueIdentifiers, warnsAboutScamAttempts, isAdaptiveModelEnabled]
            .filter { $0 }
            .count
    }

    var adaptiveModelSampleCount: Int { adaptiveCopyModel.sampleCount }
    // Expose writable key paths for SwiftUI instead of constructing custom
    // actor-isolated Binding closures in ContentView. Besides being simpler,
    // this avoids a Swift 6.1.2 IRGen crash in its Bool-setter thunk.
    var hidesGreenAndYellowAlerts: Bool {
        get { clipboardAlertVisibility == .hideGreenAndYellow }
        set { setHidesGreenAndYellowAlerts(newValue) }
    }
    var hidesGreenThroughOrangeAlerts: Bool {
        get { clipboardAlertVisibility == .redOnly }
        set { setHidesGreenThroughOrangeAlerts(newValue) }
    }
    var usesAutomaticSafeClean: Bool {
        get { clipboardAutomationProtocol == .safeClean }
        set { setClipboardProtocolOption(.safeClean, isSelected: newValue) }
    }
    var usesAutomaticStrictClean: Bool {
        get { clipboardAutomationProtocol == .strictClean }
        set { setClipboardProtocolOption(.strictClean, isSelected: newValue) }
    }
    var usesAutomaticVisualTransfer: Bool {
        get { clipboardAutomationProtocol == .visualTransfer }
        set { setClipboardProtocolOption(.visualTransfer, isSelected: newValue) }
    }

    var activeGuardLabel: String {
        guard isActiveProtectionEnabled else { return localized("Active Guard Off") }
        guard enabledWarningCount < 9 else { return localized("Active Guard On") }
        return formatted("Active Guard · %d/9 warnings", enabledWarningCount)
    }

    init(
        privateRulesURL: URL? = nil,
        adaptiveModelURL: URL? = nil,
        defaults: UserDefaults = .standard
    ) {
        Self.migrateLegacyExecutablePreferencesIfNeeded(to: defaults)
        let resolvedURL = privateRulesURL ?? Self.defaultPrivateRulesURL()
        self.privateRulesURL = resolvedURL
        let resolvedAdaptiveURL = adaptiveModelURL ?? Self.defaultAdaptiveModelURL()
        self.adaptiveModelURL = resolvedAdaptiveURL
        self.adaptiveCopyModel = (try? AdaptiveCopyModelStore.load(from: resolvedAdaptiveURL))
            ?? AdaptiveCopyModel()
        self.defaults = defaults
        self.language = AppLanguage.persistedOrEnglish(
            defaults.string(forKey: PreferenceKey.language)
        )
        self.theme = AppTheme.persistedOrSystem(
            defaults.string(forKey: PreferenceKey.theme)
        )
        self.isActiveProtectionEnabled = Self.storedBool(
            PreferenceKey.activeProtection,
            defaults: defaults,
            fallback: true
        )
        self.warnsAboutHiddenUnicode = Self.storedBool(
            PreferenceKey.hiddenUnicodeWarnings,
            defaults: defaults,
            fallback: true
        )
        self.warnsAboutTrackedLinks = Self.storedBool(
            PreferenceKey.trackedLinkWarnings,
            defaults: defaults,
            fallback: true
        )
        self.warnsAboutPatterns = Self.storedBool(
            PreferenceKey.patternWarnings,
            defaults: defaults,
            fallback: true
        )
        self.warnsAboutCodeRisks = Self.storedBool(
            PreferenceKey.codeWarnings,
            defaults: defaults,
            fallback: true
        )
        self.warnsAboutBinaryContent = Self.storedBool(
            PreferenceKey.binaryWarnings,
            defaults: defaults,
            fallback: true
        )
        self.warnsAboutFileMetadata = Self.storedBool(
            PreferenceKey.fileMetadataWarnings,
            defaults: defaults,
            fallback: true
        )
        self.warnsAboutOpaqueIdentifiers = Self.storedBool(
            PreferenceKey.identifierWarnings,
            defaults: defaults,
            fallback: true
        )
        self.warnsAboutScamAttempts = Self.storedBool(
            PreferenceKey.scamWarnings,
            defaults: defaults,
            fallback: true
        )
        self.isAdaptiveModelEnabled = Self.storedBool(
            PreferenceKey.adaptiveModelEnabled,
            defaults: defaults,
            fallback: true
        )
        let storedClipboardProtocol = defaults.string(
            forKey: PreferenceKey.clipboardAutomationProtocol
        )
        let legacyHidesGreenAndYellow = Self.storedBool(
            PreferenceKey.hidesGreenAndYellowAlerts,
            defaults: defaults,
            fallback: storedClipboardProtocol == "high-risk-only"
                || storedClipboardProtocol == ClipboardAutomationProtocol.safeClean.rawValue
                || storedClipboardProtocol == ClipboardAutomationProtocol.strictClean.rawValue
        )
        self.clipboardAlertVisibility = .persistedOrShowAll(
            defaults.string(forKey: PreferenceKey.clipboardAlertVisibility),
            legacyHidesGreenAndYellow: legacyHidesGreenAndYellow
        )
        self.clipboardAutomationProtocol = .persistedOrReviewAll(storedClipboardProtocol)
        self.automaticallyCleansLinks = Self.storedBool(
            PreferenceKey.automaticLinkCleaning,
            defaults: defaults,
            fallback: false
        )
        self.automaticallyPreparesInputResult = Self.storedBool(
            PreferenceKey.automaticInputResult,
            defaults: defaults,
            fallback: true
        )

        do {
            if privateRulesURL == nil {
                try URLRulePersistence.migrateIfNeeded(
                    from: Self.legacyPrivateRulesURL(),
                    to: resolvedURL
                )
            }
            self.privateRules = try URLRulePersistence.load(from: resolvedURL)
        } catch {
            self.privateRules = []
            self.status = formatted(
                "Private rules could not be loaded: %@",
                error.localizedDescription
            )
        }

        if isActiveProtectionEnabled {
            startClipboardMonitoring()
        } else {
            status = localized("Paste text to get started.")
        }
    }

    func paste() {
        input = NSPasteboard.general.string(forType: .string) ?? ""
        prepareAutomaticInputResult()
        inspect()
        remember(text: input)
    }

    func inputDidChange() {
        prepareAutomaticInputResult()
    }

    private func prepareAutomaticInputResult() {
        automaticInputResultTask?.cancel()
        automaticInputResultTask = nil

        if let prepared = InputResultAutomationPolicy.prepareDeterministicResult(
            from: input,
            isEnabled: automaticallyPreparesInputResult,
            using: clipboardAutomationProtocol
        ) {
            output = prepared
            return
        }

        guard InputResultAutomationPolicy.shouldUseVisualTransfer(
            isEnabled: automaticallyPreparesInputResult,
            using: clipboardAutomationProtocol
        ) else { return }

        let source = input
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            output = ""
            return
        }
        guard source.count <= ClipboardAutomationPolicy.maximumAutomaticVisualTransferCharacterCount else {
            output = ""
            status = formatted(
                "Automatic Visual Transfer skipped text longer than %d characters.",
                ClipboardAutomationPolicy.maximumAutomaticVisualTransferCharacterCount
            )
            return
        }

        // Never leave a Result produced for an older Input visible while OCR
        // is preparing the replacement. Debouncing avoids starting Vision for
        // every intermediate keystroke.
        output = ""
        automaticInputResultTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let result = try await Task.detached(priority: .userInitiated) {
                    try VisualTransfer.roundTrip(source)
                }.value
                guard !Task.isCancelled, let self else { return }
                guard self.automaticallyPreparesInputResult,
                      self.clipboardAutomationProtocol == .visualTransfer,
                      self.input == source else { return }
                guard ClipboardAutomationPolicy.acceptsAutomaticVisualTransfer(
                    original: source,
                    candidate: result.text
                ) else {
                    self.status = self.localized("Automatic Visual Transfer did not prepare Result because OCR changed a URL, number, quotation, or produced an unsafe result.")
                    return
                }
                self.output = result.text
                self.status = self.formatted(
                    "Automatic Visual Transfer prepared Result with local OCR: %d characters recognized. Review it before use.",
                    result.recognizedCharacterCount
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                guard self.automaticallyPreparesInputResult,
                      self.clipboardAutomationProtocol == .visualTransfer,
                      self.input == source else { return }
                self.status = self.formatted(
                    "Automatic Visual Transfer could not prepare Result: %@",
                    error.localizedDescription
                )
            }
        }
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        writeClipboard(output)
        status = localized("Result copied to the clipboard.")
    }

    func inspect() {
        inspection = HiddenTextAnalyzer.inspect(input)
        covertChannelReport = CovertTextChannelAnalyzer.analyze(input)
        codeAnalysis = CodeGuardAnalyzer.analyze(input)
        binaryAnalysis = BinaryContentDetector.analyze(input)
        identifierAnalysis = OpaqueIdentifierAnalyzer.analyze(input)
        scamAnalysis = ScamAttemptDetector.analyze(input)
        linkCleaningReport = URLTrackerCleaner.cleanLinks(in: input, customRules: privateRules)
        adaptiveAnalysis = isAdaptiveModelEnabled
            ? adaptiveCopyModel.assess(input)
            : AdaptiveCopyAnalysis(
                sampleCountBeforeLearning: adaptiveCopyModel.sampleCount,
                anomalyScore: 0,
                deviations: [],
                wasEligibleForLearning: false
            )
        revealedFragments = InvisibleFragmentRevealer.reveal(in: input)
        if input.isEmpty {
            status = localized("Paste text to get started.")
        } else if scamAnalysis.isPotentialScam {
            status = formatted(
                "Possible scam attempt · %d explainable signal(s) found.",
                scamAnalysis.signals.count
            )
        } else if codeAnalysis.hasRisks {
            status = codeAnalysis.languageDetection.primary == nil
                ? formatted(
                    "Source code detected. Code Guard found %d risk(s) to review.",
                    codeAnalysis.findings.count
                )
                : formatted(
                    "%@ code detected. Code Guard found %d risk(s) to review.",
                    codeAnalysis.detectedLanguage,
                    codeAnalysis.findings.count
                )
        } else if binaryAnalysis.isDetected {
            status = formatted(
                "%@ detected. Binary Guard will not decode or execute it.",
                AppLocalization.text(binaryAnalysis.displayName, language: language)
            )
        } else if codeAnalysis.isLikelyCode {
            status = codeAnalysis.languageDetection.primary == nil
                ? localized("Source code detected. No known source-code Unicode risks found.")
                : formatted(
                    "%@ code detected. No known source-code Unicode risks found.",
                    codeAnalysis.detectedLanguage
                )
        } else if covertChannelReport.hasSuspiciousChannel {
            status = formatted(
                "Found %d patterned covert channel(s) to review.",
                covertChannelReport.findings.count
            )
        } else if inspection.findings.isEmpty {
            status = localized("No known hidden Unicode elements were found.")
        } else if inspection.isClean {
            status = formatted(
                "Found %d functional Unicode element(s); no known hidden payload risk.",
                inspection.totalFindingCount
            )
        } else {
            status = formatted("Found %d elements to review.", inspection.totalActionableFindingCount)
        }
    }

    func clean(mode: CleaningMode) {
        let result = TextCleaner.clean(input, mode: mode)
        output = result.text
        let label = localized(mode == .safe ? "Safe cleaning" : "Strict cleaning")
        status = formatted("%@: removed %d and replaced %d.", label, result.removedCount, result.replacedCount)
    }

    func cleanLinks() {
        let result = URLTrackerCleaner.cleanLinks(in: input, customRules: privateRules)
        linkCleaningReport = result
        output = result.text

        switch (result.linksFound, result.linksChanged, result.unresolvedRedirectCount) {
        case (0, _, _):
            status = localized("No HTTP or HTTPS links were found.")
        case (_, 0, let unresolved) where unresolved > 0:
            status = formatted(
                "Detected %d opaque redirect(s); Signal Sieve did not contact them or claim a destination.",
                unresolved
            )
        case (_, 0, _):
            status = formatted(
                "Found %d links, but none contained known tracking parameters.",
                result.linksFound
            )
        case (_, _, let unresolved) where unresolved > 0:
            status = formatted(
                "Cleaned %d links, removed %d tracking parameters, and left %d opaque redirect(s) unresolved offline.",
                result.linksChanged,
                result.removedParameterCount,
                unresolved
            )
        default:
            status = formatted(
                "Cleaned %d links and removed %d tracking parameters.",
                result.linksChanged,
                result.removedParameterCount
            )
        }
    }

    func cleanCodeForReview() {
        guard codeAnalysis.isLikelyCode else {
            status = localized("No source code was detected in the current input.")
            return
        }
        let result = CodeGuardAnalyzer.sanitize(input)
        output = result.text
        status = formatted(
            "Code Guard prepared review output: removed %d and replaced %d. Confusable identifiers were not changed.",
            result.removedCount,
            result.replacedCount
        )
    }

    func addPrivateRule(domain: String, parameter: String) -> String? {
        do {
            let rule = try CustomURLRule(domain: domain, parameter: parameter)
            guard !privateRules.contains(rule) else {
                return localized("That private rule already exists.")
            }

            let previousRules = privateRules
            privateRules.append(rule)
            privateRules.sort(by: Self.sortRules)

            do {
                try persistPrivateRules()
                status = formatted("Added private rule for %@: %@.", rule.domain, rule.parameter)
                return nil
            } catch {
                privateRules = previousRules
                return formatted("The rule could not be saved: %@", error.localizedDescription)
            }
        } catch {
            return localizedRuleError(error)
        }
    }

    func removePrivateRule(_ rule: CustomURLRule) {
        let previousRules = privateRules
        privateRules.removeAll { $0 == rule }

        do {
            try persistPrivateRules()
            status = formatted("Removed private rule for %@: %@.", rule.domain, rule.parameter)
        } catch {
            privateRules = previousRules
            status = formatted("The private rule could not be removed: %@", error.localizedDescription)
        }
    }

    func rememberCurrentText() {
        remember(text: input)
    }

    func showPatternReport() {
        showsPatternReport = true
    }

    func runWatermarkProbe() {
        watermarkProbeReport = WatermarkProbeAnalyzer.analyze(input)
        status = formatted(
            "Surface Regularity analyzed %d words locally.",
            watermarkProbeReport.tokenCount
        )
    }

    func runRewriteIntegrity() {
        rewriteIntegrityReport = RewriteIntegrityAnalyzer.analyze(
            original: input,
            candidate: output
        )
        status = localized("Rewrite Integrity compared Input and Result locally.")
    }

    func registerMainWindowOpener(_ opener: @escaping () -> Void) {
        openMainWindow = opener
    }

    func openFileProvenanceInspector() {
        pendingClipboardImage = nil
        showsFileProvenance = true
    }

    func clearPendingClipboardImage() {
        pendingClipboardImage = nil
    }

    func enableAllWarningTypes() {
        warnsAboutHiddenUnicode = true
        warnsAboutTrackedLinks = true
        warnsAboutPatterns = true
        warnsAboutCodeRisks = true
        warnsAboutBinaryContent = true
        warnsAboutFileMetadata = true
        warnsAboutOpaqueIdentifiers = true
        warnsAboutScamAttempts = true
        isAdaptiveModelEnabled = true
        status = localized("All Active Guard warning types are enabled.")
    }

    func clearAdaptiveModel() {
        adaptiveCopyModel = AdaptiveCopyModel()
        adaptiveAnalysis = AdaptiveCopyAnalysis(
            sampleCountBeforeLearning: 0,
            anomalyScore: 0,
            deviations: [],
            wasEligibleForLearning: false
        )
        try? AdaptiveCopyModelStore.save(adaptiveCopyModel, to: adaptiveModelURL)
        status = localized("Learned copy patterns were forgotten. No copied text had been stored.")
    }

    func clearPatternMemory() {
        patternTexts.removeAll()
        patternReport = PatternReport(sampleCount: 0, findings: [])
        status = localized("Session Pattern Memory cleared.")
    }

    func openClipboardHistoryEntry(_ entry: ClipboardHistoryEntry) {
        input = entry.text
        inspect()
        status = entry.isTruncated
            ? localized("Opened the stored portion of this copy. The original was truncated for memory safety.")
            : localized("Opened a copy from session history.")
    }

    func removeClipboardHistoryEntry(_ entry: ClipboardHistoryEntry) {
        clipboardHistory.removeAll { $0.id == entry.id }
        status = localized("Removed one entry from session copy history.")
    }

    func clearClipboardHistory() {
        clipboardHistory.removeAll()
        status = localized("Session copy history cleared.")
    }

    func visualTransfer() {
        let source = input
        isProcessing = true
        status = localized("Rendering as an image and reading it with local OCR…")

        Task {
            defer { isProcessing = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try VisualTransfer.roundTrip(source)
                }.value
                output = result.text
                status = formatted(
                    "Visual transfer complete: %d characters recognized. Review the result.",
                    result.recognizedCharacterCount
                )
            } catch {
                status = formatted("Visual transfer failed: %@", error.localizedDescription)
            }
        }
    }

    func moveOutputToInput() {
        input = output
        inspect()
        status = localized("The result is now the input text.")
    }

    private func remember(text: String) {
        let sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let update = ClipboardProtectionAnalyzer.appendingPatternSample(text, to: patternTexts)
        guard update.added else {
            if !sample.isEmpty && sample.count < ClipboardProtectionAnalyzer.minimumPatternSampleLength {
                status = localized("Text is too short for useful pattern comparison.")
            } else if !sample.isEmpty {
                status = localized("This text is already the latest Pattern Memory sample.")
            }
            return
        }
        patternTexts = update.texts
        patternReport = PatternAnalyzer.analyze(patternTexts)

        if patternTexts.count < 3 {
            status = formatted(
                "Added to session Pattern Memory (%d/3 samples for a stronger comparison).",
                patternTexts.count
            )
        } else if patternReport.hasSuspiciousRepetition {
            status = formatted(
                "Pattern Memory found %d repeated patterns across recent texts.",
                patternReport.findings.count
            )
        } else {
            status = formatted(
                "Pattern Memory compared %d recent texts; no strong repetition found.",
                patternTexts.count
            )
        }
    }

    private func persistPrivateRules() throws {
        try URLRulePersistence.save(privateRules, to: privateRulesURL)
    }

    private func startClipboardMonitoring() {
        guard clipboardMonitor == nil else { return }
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        clipboardMonitor = Timer.publish(every: 0.55, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollClipboard()
            }
        status = localized("Active Guard is monitoring new clipboard content locally.")
    }

    func ensureClipboardMonitoringIsRunning() {
        guard isActiveProtectionEnabled else { return }
        startClipboardMonitoring()
    }

    private func stopClipboardMonitoring() {
        clipboardMonitor?.cancel()
        clipboardMonitor = nil
        clipboardAnalysisTask?.cancel()
        clipboardAnalysisTask = nil
        automaticVisualTransferTask?.cancel()
        automaticVisualTransferTask = nil
        noticePanel.close()
        status = localized("Active Guard is off.")
    }

    private func pollClipboard() {
        guard isActiveProtectionEnabled else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pasteboard.changeCount
        let capturedAt = Date()
        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let sourceApplicationName = sourceApplication?.localizedName
        let sourceBundleIdentifier = sourceApplication?.bundleIdentifier
        let shouldStoreInHistory = Self.shouldStoreInClipboardHistory(pasteboard)
        let typeInventory = ClipboardTypeAnalyzer.analyze(
            typeIdentifiers: (pasteboard.types ?? []).map(\.rawValue)
        )
        let fileMetadataAlert = warnsAboutFileMetadata
            && typeInventory.requiresFileProvenanceReview
        let copiedText = pasteboard.string(forType: .string) ?? ""
        guard !copiedText.isEmpty || fileMetadataAlert else { return }

        if copiedText.isEmpty {
            let notice = ClipboardNotice(
                clipboardText: "",
                hiddenUnicodeCount: 0,
                hiddenUnicodeRiskLevel: nil,
                codeRiskCount: 0,
                codeRiskLevel: nil,
                codeLanguage: "",
                hasSpecificCodeLanguage: false,
                binaryKind: nil,
                binaryByteCount: 0,
                trackedLinkCount: 0,
                removedParameterCount: 0,
                patternReport: PatternReport(sampleCount: 0, findings: []),
                identifierAnalysis: OpaqueIdentifierAnalysis(findings: []),
                scamAnalysis: ScamAttemptDetector.analyze(""),
                adaptiveAnalysis: AdaptiveCopyAnalysis(
                    sampleCountBeforeLearning: adaptiveCopyModel.sampleCount,
                    anomalyScore: 0,
                    deviations: [],
                    wasEligibleForLearning: false
                ),
                clipboardContentKinds: typeInventory.kinds,
                pasteboardChangeCount: pasteboard.changeCount,
                automaticCleaningAudit: nil
            )
            if ClipboardAlertVisibilityPolicy.shouldPresent(
                notice.priority,
                visibility: clipboardAlertVisibility
            ) {
                present(notice)
            }
            return
        }

        let expectedChangeCount = pasteboard.changeCount
        let recentPatternTexts = patternTexts
        let customRules = privateRules
        let automaticLinkCleaning = automaticallyCleansLinks
        let automationProtocol = clipboardAutomationProtocol
        let isPrivacySensitive = !shouldStoreInHistory

        clipboardAnalysisTask?.cancel()
        clipboardAnalysisTask = Task { [weak self] in
            guard let self else { return }
            guard let prepared = await clipboardAnalysisWorker.analyze(
                text: copiedText,
                recentPatternTexts: recentPatternTexts,
                customRules: customRules,
                automaticallyCleansLinks: automaticLinkCleaning,
                automationProtocol: automationProtocol,
                typeInventory: typeInventory,
                isPrivacySensitive: isPrivacySensitive
            ), !Task.isCancelled else { return }
            guard self.isActiveProtectionEnabled,
                  self.automaticallyCleansLinks == automaticLinkCleaning,
                  self.clipboardAutomationProtocol == automationProtocol else { return }
            self.finishClipboardPoll(
                copiedText: copiedText,
                expectedChangeCount: expectedChangeCount,
                capturedAt: capturedAt,
                sourceApplicationName: sourceApplicationName,
                sourceBundleIdentifier: sourceBundleIdentifier,
                shouldStoreInHistory: shouldStoreInHistory,
                typeInventory: typeInventory,
                fileMetadataAlert: fileMetadataAlert,
                prepared: prepared
            )
        }
    }

    private func finishClipboardPoll(
        copiedText: String,
        expectedChangeCount: Int,
        capturedAt: Date,
        sourceApplicationName: String?,
        sourceBundleIdentifier: String?,
        shouldStoreInHistory: Bool,
        typeInventory: ClipboardTypeInventory,
        fileMetadataAlert: Bool,
        prepared: ClipboardCoreAnalysis
    ) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == expectedChangeCount,
              pasteboard.string(forType: .string) == copiedText else { return }

        let copiedCodeAnalysis = prepared.copiedCodeAnalysis
        let initialLinkCleaning = prepared.initialLinkCleaning
        var effectiveText = prepared.effectiveText
        let hasNonTextRepresentation = typeInventory.kinds.contains(.image)
            || typeInventory.kinds.contains(.fileURL)
        let isPrivacySensitive = !shouldStoreInHistory
        let linkWasPreparedForAutomaticCleaning = prepared.linkWasPreparedForAutomaticCleaning
        let automationResult = prepared.automationResult
        let shouldFlattenRichText = prepared.shouldFlattenRichText

        var automaticallyCleaned = false
        var automaticTextCleaningApplied = false
        if effectiveText != copiedText || shouldFlattenRichText {
            automaticallyCleaned = replaceClipboard(
                expectedText: copiedText,
                replacement: effectiveText
            )
            if !automaticallyCleaned {
                effectiveText = copiedText
            } else if automationResult.didChange {
                automaticTextCleaningApplied = true
                status = formatted(
                    "%@ automatically cleaned this copy: removed %d and replaced %d element(s).",
                    AppLocalization.text(
                        clipboardAutomationProtocol == .strictClean ? "Strict Clean" : "Safe Clean",
                        language: language
                    ),
                    automationResult.removedCount,
                    automationResult.replacedCount
                )
            } else if shouldFlattenRichText {
                automaticTextCleaningApplied = true
                status = localized("Strict Clean converted this copy to plain text and removed its HTML or rich-text formatting.")
            } else if linkWasPreparedForAutomaticCleaning {
                status = formatted(
                    "Active Guard automatically cleaned %d copied link(s).",
                    initialLinkCleaning.linksChanged
                )
            }
        } else if automaticallyCleansLinks,
                  copiedCodeAnalysis.isLikelyCode,
                  initialLinkCleaning.linksChanged > 0 {
            status = localized("Code detected. Automatic link cleaning was skipped so source code was not modified.")
        } else if let skipReason = automationResult.skipReason,
                  clipboardAutomationProtocol.cleaningMode != nil {
            status = localizedClipboardAutomationSkip(skipReason)
        }

        if clipboardAutomationProtocol == .visualTransfer {
            scheduleAutomaticVisualTransfer(
                text: effectiveText,
                expectedChangeCount: NSPasteboard.general.changeCount,
                isLikelyCode: copiedCodeAnalysis.isLikelyCode,
                hasNonTextRepresentation: hasNonTextRepresentation,
                isPrivacySensitive: isPrivacySensitive
            )
        }

        // Detection and alert priority use the original copy. Automatic
        // cleaning must never erase the evidence that decides whether a red
        // warning remains mandatory.
        let analysis = prepared.originalAnalysis
        let finalClipboardAnalysis = effectiveText == copiedText
            ? analysis
            : prepared.finalAnalysis
        let finalLinkCleaning = effectiveText == copiedText
            ? initialLinkCleaning
            : prepared.finalLinkCleaning
        let automaticCleaningAudit = clipboardAutomationProtocol.cleaningMode.map { mode in
            ClipboardAutomaticCleaningAudit(
                mode: mode,
                didWriteCleanedText: automaticTextCleaningApplied,
                removedElementCount: automationResult.removedCount,
                replacedElementCount: automationResult.replacedCount,
                originalAlertCount: Self.automaticTextAlertCount(in: analysis),
                remainingAlertCount: Self.automaticTextAlertCount(in: finalClipboardAnalysis),
                originalPriority: Self.automaticTextPriority(in: analysis),
                remainingPriority: Self.automaticTextPriority(in: finalClipboardAnalysis),
                skipReason: automationResult.skipReason
            )
        }
        patternTexts = analysis.updatedPatternTexts
        patternReport = PatternAnalyzer.analyze(patternTexts)
        identifierAnalysis = analysis.identifierAnalysis
        scamAnalysis = analysis.scamAnalysis

        if isAdaptiveModelEnabled, shouldStoreInHistory {
            adaptiveAnalysis = adaptiveCopyModel.evaluateAndLearn(copiedText)
            do {
                try AdaptiveCopyModelStore.save(adaptiveCopyModel, to: adaptiveModelURL)
            } catch {
                status = localized("Usual copy patterns could not save their numerical measurements.")
            }
        } else {
            adaptiveAnalysis = AdaptiveCopyAnalysis(
                sampleCountBeforeLearning: adaptiveCopyModel.sampleCount,
                anomalyScore: 0,
                deviations: [],
                wasEligibleForLearning: false
            )
        }

        if shouldStoreInHistory {
            let entry = ClipboardHistory.makeEntry(
                text: copiedText,
                capturedAt: capturedAt,
                sourceApplicationName: sourceApplicationName,
                sourceBundleIdentifier: sourceBundleIdentifier,
                hiddenUnicodeCount: analysis.hiddenTextFindingCount,
                codeRiskCount: analysis.codeAnalysis.findings.count,
                trackedLinkCount: initialLinkCleaning.linksFlagged,
                binaryKind: analysis.binaryAnalysis.kind,
                scamSignalCount: analysis.scamAnalysis.isPotentialScam
                    ? analysis.scamAnalysis.signals.count
                    : 0,
                scamThreatLevel: analysis.scamAnalysis.isPotentialScam
                    ? analysis.scamAnalysis.threatLevel
                    : nil,
                wasAutomaticallyCleaned: automaticallyCleaned,
                automaticCleaningAudit: automaticCleaningAudit
            )
            clipboardHistory = ClipboardHistory.appending(entry, to: clipboardHistory)
        }

        let includesCodeWarnings = ClipboardAlertVisibilityPolicy.shouldIncludeCategory(
            isEnabled: warnsAboutCodeRisks,
            highestRisk: analysis.codeAnalysis.highestRiskLevel
        )
        let codeRiskCount = includesCodeWarnings ? analysis.codeAnalysis.findings.count : 0
        let binaryDetection = warnsAboutBinaryContent
            ? analysis.binaryAnalysis
            : BinaryContentAnalysis(kind: nil)
        let includesHiddenWarnings = ClipboardAlertVisibilityPolicy.shouldIncludeCategory(
            isEnabled: warnsAboutHiddenUnicode,
            highestRisk: analysis.hiddenTextRiskLevel
        )
        let rawHiddenCount = includesHiddenWarnings
            ? analysis.hiddenTextFindingCount
            : 0
        let hiddenCount = codeRiskCount > 0 && analysis.hiddenTextRiskLevel != .high
            ? 0
            : rawHiddenCount
        let trackedLinkCount = warnsAboutTrackedLinks
            ? finalLinkCleaning.linksFlagged
            : 0
        let alertPatternReport = warnsAboutPatterns && analysis.containsRecentPattern
            ? analysis.recentPatternReport
            : PatternReport(sampleCount: 0, findings: [])
        let alertIdentifierAnalysis = warnsAboutOpaqueIdentifiers
            ? analysis.identifierAnalysis
            : OpaqueIdentifierAnalysis(findings: [])
        let includesScamWarnings = ClipboardAlertVisibilityPolicy.shouldIncludeScamCategory(
            isEnabled: warnsAboutScamAttempts,
            threatLevel: analysis.scamAnalysis.isPotentialScam
                ? analysis.scamAnalysis.threatLevel
                : nil
        )
        let alertScamAnalysis = includesScamWarnings
            ? analysis.scamAnalysis
            : ScamAttemptDetector.analyze("")
        let alertAdaptiveAnalysis = isAdaptiveModelEnabled
            ? adaptiveAnalysis
            : AdaptiveCopyAnalysis(
                sampleCountBeforeLearning: adaptiveCopyModel.sampleCount,
                anomalyScore: 0,
                deviations: [],
                wasEligibleForLearning: false
            )

        guard hiddenCount > 0
                || codeRiskCount > 0
                || binaryDetection.isDetected
                || trackedLinkCount > 0
                || alertPatternReport.hasSuspiciousRepetition
                || alertIdentifierAnalysis.containsIdentifiers
                || alertScamAnalysis.isPotentialScam
                || alertAdaptiveAnalysis.isAnomalous
                || fileMetadataAlert else {
            return
        }

        let notice = ClipboardNotice(
            clipboardText: copiedText,
            hiddenUnicodeCount: hiddenCount,
            hiddenUnicodeRiskLevel: hiddenCount > 0
                ? analysis.hiddenTextRiskLevel
                : nil,
            codeRiskCount: codeRiskCount,
            codeRiskLevel: codeRiskCount > 0
                ? analysis.codeAnalysis.highestRiskLevel
                : nil,
            codeLanguage: analysis.codeAnalysis.detectedLanguage,
            hasSpecificCodeLanguage: analysis.codeAnalysis.languageDetection.primary != nil,
            binaryKind: binaryDetection.kind,
            binaryByteCount: binaryDetection.byteCount,
            trackedLinkCount: trackedLinkCount,
            removedParameterCount: trackedLinkCount > 0 ? initialLinkCleaning.removedParameterCount : 0,
            patternReport: alertPatternReport,
            identifierAnalysis: alertIdentifierAnalysis,
            scamAnalysis: alertScamAnalysis,
            adaptiveAnalysis: alertAdaptiveAnalysis,
            clipboardContentKinds: fileMetadataAlert ? typeInventory.kinds : [],
            pasteboardChangeCount: pasteboard.changeCount,
            automaticCleaningAudit: automaticCleaningAudit
        )
        guard ClipboardAlertVisibilityPolicy.shouldPresent(
            notice.priority,
            visibility: clipboardAlertVisibility
        ) else { return }
        present(notice)
    }

    private func present(_ notice: ClipboardNotice) {
        noticePanel.show(
            notice,
            language: language,
            onReview: { [weak self] in self?.review(notice) },
            onCleanLinks: { [weak self] in self?.cleanCopiedLinks(from: notice) },
            onEnableAutoClean: { [weak self] in self?.enableAutomaticLinkCleaning(from: notice) },
            onShowPatterns: { [weak self] in self?.revealPatternReport() },
            onOpenFileInspector: { [weak self] in self?.revealFileProvenanceInspector(from: notice) },
            alertVisibility: clipboardAlertVisibility,
            onSetAlertVisibility: { [weak self] visibility in
                self?.setClipboardAlertVisibility(visibility)
            },
            clipboardProtocol: clipboardAutomationProtocol,
            onSetClipboardProtocol: { [weak self] selection in
                self?.setClipboardAutomationProtocol(selection, applyingTo: notice)
            }
        )
    }

    private func review(_ notice: ClipboardNotice) {
        input = notice.clipboardText
        inspect()
        revealMainWindow()
        noticePanel.dismissCurrent()
    }

    private func cleanCopiedLinks(from notice: ClipboardNotice) {
        let pasteboard = NSPasteboard.general
        guard let currentText = pasteboard.string(forType: .string) else {
            status = localized("The clipboard no longer contains text.")
            noticePanel.dismissCurrent()
            return
        }
        let result = URLTrackerCleaner.cleanLinks(in: currentText, customRules: privateRules)
        linkCleaningReport = result
        guard result.linksChanged > 0 else {
            if result.unresolvedRedirectCount > 0 {
                status = formatted(
                    "Detected %d opaque redirect(s); Signal Sieve kept them unchanged and made no network request.",
                    result.unresolvedRedirectCount
                )
            } else {
                status = localized("The copied text no longer contains known tracking parameters.")
            }
            noticePanel.dismissCurrent()
            return
        }
        if replaceClipboard(expectedText: currentText, replacement: result.text) {
            output = result.text
            status = formatted(
                "Cleaned the current clipboard copy and removed %d tracking parameter(s).",
                result.removedParameterCount
            )
        } else {
            status = localized("Clipboard changed before cleaning, so SignalSieve did not overwrite it.")
        }
        noticePanel.dismissCurrent()
    }

    private func enableAutomaticLinkCleaning(from notice: ClipboardNotice) {
        automaticallyCleansLinks = true
        cleanCopiedLinks(from: notice)
        status = localized("Automatic link cleaning is on. Future copied links will be cleaned locally.")
    }

    private func revealPatternReport() {
        showsPatternReport = true
        revealMainWindow()
        noticePanel.dismissCurrent()
    }

    private func revealFileProvenanceInspector(from notice: ClipboardNotice) {
        pendingClipboardImage = nil
        if notice.clipboardContentKinds.contains(.image) {
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount == notice.pasteboardChangeCount {
                do {
                    pendingClipboardImage = try ClipboardImagePasteboardReader.read(from: pasteboard)
                    status = localized("Pasted the copied image into File Inspector.")
                } catch {
                    status = localized("The clipboard image could not be imported safely. You can paste it again or choose a file.")
                }
            } else {
                status = localized("The clipboard changed after the warning. Paste the image again from File Inspector.")
            }
        }
        showsFileProvenance = true
        revealMainWindow()
        noticePanel.dismissCurrent()
    }

    private func revealMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainApplicationWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        openMainWindow?()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.mainApplicationWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private var mainApplicationWindow: NSWindow? {
        NSApp.windows.first { window in
            !(window is NSPanel) && window.canBecomeMain
        }
    }

    func setClipboardProtocolOption(
        _ selection: ClipboardAutomationProtocol,
        isSelected: Bool
    ) {
        setClipboardAutomationProtocol(isSelected ? selection : .reviewAll)
    }

    func setHidesGreenAndYellowAlerts(_ isHidden: Bool) {
        guard isHidden || clipboardAlertVisibility == .hideGreenAndYellow else { return }
        setClipboardAlertVisibility(isHidden ? .hideGreenAndYellow : .showAll)
    }

    func setHidesGreenThroughOrangeAlerts(_ isHidden: Bool) {
        guard isHidden || clipboardAlertVisibility == .redOnly else { return }
        setClipboardAlertVisibility(isHidden ? .redOnly : .showAll)
    }

    private func setClipboardAlertVisibility(_ visibility: ClipboardAlertVisibility) {
        clipboardAlertVisibility = visibility
        switch visibility {
        case .showAll:
            status = localized("Green through orange alerts are visible. Red alerts remain mandatory.")
        case .hideGreenAndYellow:
            status = localized("Green and yellow alerts are hidden. Orange and red alerts remain mandatory.")
        case .redOnly:
            status = localized("Green through orange alerts are hidden. Only mandatory red alerts will appear.")
        }
    }

    private func setClipboardAutomationProtocol(
        _ selection: ClipboardAutomationProtocol,
        applyingTo notice: ClipboardNotice? = nil
    ) {
        clipboardAutomationProtocol = selection

        if selection == .reviewAll {
            automaticVisualTransferTask?.cancel()
            automaticVisualTransferTask = nil
            status = localized("Automatic text cleaning is off. Alert visibility is unchanged.")
            return
        }

        if selection == .visualTransfer {
            guard let notice else {
                status = localized("Automatic Visual Transfer is on for eligible future text copies. OCR stays on this Mac, but its output must still be reviewed.")
                return
            }
            scheduleAutomaticVisualTransfer(from: notice)
            return
        }

        guard let mode = selection.cleaningMode else { return }

        guard let notice else {
            status = localized(selection == .safeClean
                ? "Safe Clean is now automatic for eligible future text copies. Alert visibility is unchanged."
                : "Strict Clean is now automatic for eligible future text copies. Alert visibility is unchanged.")
            return
        }

        applyClipboardProtocol(mode: mode, selection: selection, to: notice)
    }

    private func applyClipboardProtocol(
        mode: CleaningMode,
        selection: ClipboardAutomationProtocol,
        to notice: ClipboardNotice
    ) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == notice.pasteboardChangeCount,
              let currentText = pasteboard.string(forType: .string) else {
            status = localized("Clipboard Protocol was saved, but the current clipboard changed before cleaning.")
            return
        }

        let typeInventory = ClipboardTypeAnalyzer.analyze(
            typeIdentifiers: (pasteboard.types ?? []).map(\.rawValue)
        )
        let result = ClipboardAutomationPolicy.transform(
            currentText,
            using: selection,
            isLikelyCode: CodeGuardAnalyzer.analyze(currentText).isLikelyCode,
            hasNonTextRepresentation: typeInventory.kinds.contains(.image)
                || typeInventory.kinds.contains(.fileURL),
            isPrivacySensitive: !Self.shouldStoreInClipboardHistory(pasteboard)
        )
        let shouldFlattenRichText = ClipboardAutomationPolicy.shouldFlattenRichText(
            using: selection,
            hasRichTextRepresentation: typeInventory.containsRichTextRepresentation,
            skipReason: result.skipReason
        )

        if let skipReason = result.skipReason {
            status = localizedClipboardAutomationSkip(skipReason)
            return
        }
        guard result.didChange || shouldFlattenRichText else {
            status = localized(mode == .safe
                ? "Safe Clean is automatic. The current copy needed no changes."
                : "Strict Clean is automatic. The current copy needed no changes.")
            return
        }
        guard replaceClipboard(expectedText: currentText, replacement: result.text) else {
            status = localized("Clipboard Protocol was saved, but the current clipboard changed before cleaning.")
            return
        }
        status = shouldFlattenRichText && !result.didChange
            ? localized("Strict Clean converted this copy to plain text and removed its HTML or rich-text formatting.")
            : formatted(
                "%@ cleaned the current copy: removed %d and replaced %d element(s).",
                AppLocalization.text(mode == .safe ? "Safe Clean" : "Strict Clean", language: language),
                result.removedCount,
                result.replacedCount
            )
    }

    private func scheduleAutomaticVisualTransfer(from notice: ClipboardNotice) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == notice.pasteboardChangeCount,
              let currentText = pasteboard.string(forType: .string) else {
            status = localized("Clipboard Protocol was saved, but the current clipboard changed before processing.")
            return
        }
        let typeInventory = ClipboardTypeAnalyzer.analyze(
            typeIdentifiers: (pasteboard.types ?? []).map(\.rawValue)
        )
        scheduleAutomaticVisualTransfer(
            text: currentText,
            expectedChangeCount: pasteboard.changeCount,
            isLikelyCode: CodeGuardAnalyzer.analyze(currentText).isLikelyCode,
            hasNonTextRepresentation: typeInventory.requiresFileProvenanceReview,
            isPrivacySensitive: !Self.shouldStoreInClipboardHistory(pasteboard)
        )
    }

    private func scheduleAutomaticVisualTransfer(
        text: String,
        expectedChangeCount: Int,
        isLikelyCode: Bool,
        hasNonTextRepresentation: Bool,
        isPrivacySensitive: Bool
    ) {
        if let skipReason = ClipboardAutomationPolicy.skipReason(
            for: .visualTransfer,
            text: text,
            isLikelyCode: isLikelyCode,
            hasNonTextRepresentation: hasNonTextRepresentation,
            isPrivacySensitive: isPrivacySensitive
        ) {
            status = localizedClipboardAutomationSkip(skipReason)
            return
        }

        automaticVisualTransferTask?.cancel()
        status = localized("Automatic Visual Transfer is rebuilding this copy with local OCR…")
        automaticVisualTransferTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try VisualTransfer.roundTrip(text)
                }.value
                guard !Task.isCancelled, let self else { return }
                guard self.clipboardAutomationProtocol == .visualTransfer else { return }

                let pasteboard = NSPasteboard.general
                guard pasteboard.changeCount == expectedChangeCount,
                      pasteboard.string(forType: .string) == text else {
                    self.status = self.localized("The clipboard changed before Automatic Visual Transfer finished, so SignalSieve did not overwrite it.")
                    return
                }
                guard ClipboardAutomationPolicy.acceptsAutomaticVisualTransfer(
                    original: text,
                    candidate: result.text
                ) else {
                    self.status = self.localized("Automatic Visual Transfer did not overwrite this copy because OCR changed a URL, number, quotation, or produced an unsafe result.")
                    return
                }

                self.writeClipboard(result.text)
                self.output = result.text
                self.status = self.formatted(
                    "Automatic Visual Transfer rebuilt this copy with local OCR: %d characters recognized. Review it before use.",
                    result.recognizedCharacterCount
                )
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.status = self.formatted(
                    "Automatic Visual Transfer failed: %@",
                    error.localizedDescription
                )
            }
        }
    }

    private func localizedClipboardAutomationSkip(
        _ reason: ClipboardAutomationSkipReason
    ) -> String {
        switch reason {
        case .sourceCode:
            localized("Clipboard Protocol was saved. Automatic text cleaning skipped source code.")
        case .nonTextRepresentation:
            localized("Clipboard Protocol was saved. Automatic text cleaning skipped a file or image representation.")
        case .privacySensitiveClipboard:
            localized("Clipboard Protocol was saved. Automatic text cleaning skipped privacy-sensitive clipboard content.")
        case .inputTooLarge:
            formatted(
                "Automatic Visual Transfer skipped text longer than %d characters.",
                ClipboardAutomationPolicy.maximumAutomaticVisualTransferCharacterCount
            )
        }
    }

    private func setWarning(_ kind: ClipboardWarningKind, isSuppressed: Bool) {
        switch kind {
        case .hiddenUnicode: warnsAboutHiddenUnicode = !isSuppressed
        case .unsafeCode: warnsAboutCodeRisks = !isSuppressed
        case .binaryContent: warnsAboutBinaryContent = !isSuppressed
        case .fileMetadata: warnsAboutFileMetadata = !isSuppressed
        case .trackedLink: warnsAboutTrackedLinks = !isSuppressed
        case .repeatedPattern: warnsAboutPatterns = !isSuppressed
        case .opaqueIdentifier: warnsAboutOpaqueIdentifiers = !isSuppressed
        case .scamAttempt: warnsAboutScamAttempts = !isSuppressed
        case .adaptiveAnomaly: isAdaptiveModelEnabled = !isSuppressed
        }
        status = isSuppressed
            ? formatted(
                "%@ warnings are off. You can restore them from Active Guard.",
                AppLocalization.text(kind.label, language: language)
            )
            : formatted(
                "%@ warnings are on.",
                AppLocalization.text(kind.label, language: language)
            )
    }

    @discardableResult
    private func replaceClipboard(expectedText: String, replacement: String) -> Bool {
        let pasteboard = NSPasteboard.general
        guard ClipboardPlainTextWriter.replace(
            on: pasteboard,
            expectedText: expectedText,
            replacement: replacement
        ) else { return false }
        lastPasteboardChangeCount = pasteboard.changeCount
        return true
    }

    private func writeClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        ClipboardPlainTextWriter.write(text, to: pasteboard)
        lastPasteboardChangeCount = pasteboard.changeCount
    }

    private static func automaticTextAlertCount(
        in analysis: ClipboardProtectionAnalysis
    ) -> Int {
        analysis.hiddenTextFindingCount
            + analysis.codeAnalysis.findings.count
            + (analysis.scamAnalysis.isPotentialScam ? analysis.scamAnalysis.signals.count : 0)
    }

    private static func automaticTextPriority(
        in analysis: ClipboardProtectionAnalysis
    ) -> ClipboardAlertPriority {
        ClipboardProtectionAnalyzer.alertPriority(
            hiddenUnicodeRisk: analysis.hiddenTextRiskLevel,
            codeRisk: analysis.codeAnalysis.highestRiskLevel,
            scamThreat: analysis.scamAnalysis.isPotentialScam
                ? analysis.scamAnalysis.threatLevel
                : nil
        )
    }

    private static func shouldStoreInClipboardHistory(_ pasteboard: NSPasteboard) -> Bool {
        let excludedTypes = Set([
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType"
        ])
        return !(pasteboard.types ?? []).contains { excludedTypes.contains($0.rawValue) }
    }

    func copyFindingText(_ text: String) {
        writeClipboard(text)
        status = localized("Copied")
    }

    @discardableResult
    func useClipboardImage(
        _ payload: ClipboardImagePayload,
        replacingChangeCount expectedChangeCount: Int
    ) -> Bool {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == expectedChangeCount else {
            status = localized("The clipboard changed before replacement, so Signal Sieve did not overwrite it.")
            return false
        }
        guard ClipboardImagePasteboardReader.write(payload, to: pasteboard) else {
            status = localized("The clean image could not be placed on the clipboard.")
            return false
        }
        lastPasteboardChangeCount = pasteboard.changeCount
        status = localized("The verified clean image is now on the clipboard.")
        return true
    }

    private static func sortRules(_ left: CustomURLRule, _ right: CustomURLRule) -> Bool {
        left.domain == right.domain
            ? left.parameter < right.parameter
            : left.domain < right.domain
    }

    private static func defaultPrivateRulesURL() -> URL {
        privateRulesURL(applicationName: "SignalSieve")
    }

    private static func defaultAdaptiveModelURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return applicationSupport
            .appendingPathComponent("SignalSieve", isDirectory: true)
            .appendingPathComponent("adaptive-copy-model.json")
    }

    private static func legacyPrivateRulesURL() -> URL {
        privateRulesURL(applicationName: "TextScrub")
    }

    private static func privateRulesURL(applicationName: String) -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return applicationSupport
            .appendingPathComponent(applicationName, isDirectory: true)
            .appendingPathComponent("private-url-rules.json")
    }

    private static func storedBool(
        _ key: String,
        defaults: UserDefaults,
        fallback: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    /// The original command-line build used `SignalSieve` as its preferences
    /// domain. A real app bundle uses its bundle identifier instead, so copy
    /// only known settings once and never copy clipboard content.
    private static func migrateLegacyExecutablePreferencesIfNeeded(to defaults: UserDefaults) {
        guard !defaults.bool(forKey: PreferenceKey.legacyPreferencesMigrated) else { return }
        guard let legacy = UserDefaults(suiteName: "SignalSieve") else {
            defaults.set(true, forKey: PreferenceKey.legacyPreferencesMigrated)
            return
        }

        let keys = [
            PreferenceKey.activeProtection,
            PreferenceKey.hiddenUnicodeWarnings,
            PreferenceKey.codeWarnings,
            PreferenceKey.binaryWarnings,
            PreferenceKey.trackedLinkWarnings,
            PreferenceKey.patternWarnings,
            PreferenceKey.fileMetadataWarnings,
            PreferenceKey.identifierWarnings,
            PreferenceKey.scamWarnings,
            PreferenceKey.adaptiveModelEnabled,
            PreferenceKey.clipboardAlertVisibility,
            PreferenceKey.hidesGreenAndYellowAlerts,
            PreferenceKey.clipboardAutomationProtocol,
            PreferenceKey.automaticLinkCleaning,
            PreferenceKey.automaticInputResult,
            PreferenceKey.language
        ]
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: PreferenceKey.legacyPreferencesMigrated)
    }

    func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    func formatted(_ englishFormat: String, _ arguments: CVarArg...) -> String {
        String(
            format: AppLocalization.text(englishFormat, language: language),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }

    private func localizedRuleError(_ error: Error) -> String {
        guard let validationError = error as? RuleValidationError else {
            return error.localizedDescription
        }
        switch validationError {
        case .invalidDomain:
            return localized("Enter a valid domain such as example.com.")
        case .invalidParameter:
            return localized("Enter a query parameter name without a value.")
        }
    }

    private enum PreferenceKey {
        static let activeProtection = "activeProtection.enabled"
        static let hiddenUnicodeWarnings = "activeProtection.warn.hiddenUnicode"
        static let codeWarnings = "activeProtection.warn.codeRisks"
        static let binaryWarnings = "activeProtection.warn.binaryContent"
        static let fileMetadataWarnings = "activeProtection.warn.fileMetadata"
        static let identifierWarnings = "activeProtection.warn.opaqueIdentifiers"
        static let scamWarnings = "activeProtection.warn.scamAttempts"
        static let adaptiveModelEnabled = "activeProtection.adaptiveModel.enabled"
        static let clipboardAlertVisibility = "activeProtection.alertVisibility"
        static let hidesGreenAndYellowAlerts = "activeProtection.hideGreenAndYellowAlerts"
        static let clipboardAutomationProtocol = "activeProtection.clipboardAutomationProtocol"
        static let trackedLinkWarnings = "activeProtection.warn.trackedLinks"
        static let patternWarnings = "activeProtection.warn.patterns"
        static let automaticLinkCleaning = "activeProtection.autoCleanLinks"
        static let automaticInputResult = "workspace.automaticSafeResult"
        static let language = "appearance.language"
        static let theme = "appearance.theme"
        static let legacyPreferencesMigrated = "migration.legacyExecutablePreferences.v1"
    }
}
