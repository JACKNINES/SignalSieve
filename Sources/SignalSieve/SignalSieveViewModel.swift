// SPDX-License-Identifier: MPL-2.0
import AppKit
import Combine
import Foundation
import SignalSieveCore

@MainActor
final class SignalSieveViewModel: ObservableObject {
    @Published var input = ""
    @Published var output = ""
    @Published var showsPatternReport = false
    @Published var showsFileProvenance = false
    @Published private(set) var pendingClipboardImage: ClipboardImagePayload?
    @Published private(set) var inspection = HiddenTextAnalyzer.inspect("")
    @Published private(set) var codeAnalysis = CodeGuardAnalyzer.analyze("")
    @Published private(set) var binaryAnalysis = BinaryContentDetector.analyze("")
    @Published private(set) var watermarkProbeReport = WatermarkProbeAnalyzer.analyze("")
    @Published private(set) var rewriteIntegrityReport = RewriteIntegrityAnalyzer.analyze(
        original: "",
        candidate: ""
    )
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
    @Published var automaticallyCleansLinks: Bool {
        didSet { defaults.set(automaticallyCleansLinks, forKey: PreferenceKey.automaticLinkCleaning) }
    }

    private let privateRulesURL: URL
    private let defaults: UserDefaults
    private let noticePanel = ClipboardNoticePanelController()
    private var clipboardMonitor: AnyCancellable?
    private var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    private var openMainWindow: (() -> Void)?

    var patternSampleCount: Int { patternTexts.count }
    var clipboardHistoryCount: Int { clipboardHistory.count }
    var privateRuleCount: Int { privateRules.count }
    var enabledWarningCount: Int {
        [warnsAboutHiddenUnicode, warnsAboutTrackedLinks, warnsAboutPatterns, warnsAboutCodeRisks, warnsAboutBinaryContent, warnsAboutFileMetadata]
            .filter { $0 }
            .count
    }

    var activeGuardLabel: String {
        guard isActiveProtectionEnabled else { return localized("Active Guard Off") }
        guard enabledWarningCount < 6 else { return localized("Active Guard On") }
        return formatted("Active Guard · %d/6 warnings", enabledWarningCount)
    }

    init(privateRulesURL: URL? = nil, defaults: UserDefaults = .standard) {
        Self.migrateLegacyExecutablePreferencesIfNeeded(to: defaults)
        let resolvedURL = privateRulesURL ?? Self.defaultPrivateRulesURL()
        self.privateRulesURL = resolvedURL
        self.defaults = defaults
        self.language = AppLanguage.persistedOrEnglish(
            defaults.string(forKey: PreferenceKey.language)
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
        self.automaticallyCleansLinks = Self.storedBool(
            PreferenceKey.automaticLinkCleaning,
            defaults: defaults,
            fallback: false
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
        inspect()
        remember(text: input)
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        writeClipboard(output)
        status = localized("Result copied to the clipboard.")
    }

    func inspect() {
        inspection = HiddenTextAnalyzer.inspect(input)
        codeAnalysis = CodeGuardAnalyzer.analyze(input)
        binaryAnalysis = BinaryContentDetector.analyze(input)
        revealedFragments = InvisibleFragmentRevealer.reveal(in: input)
        if input.isEmpty {
            status = localized("Paste text to get started.")
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
        } else if inspection.findings.isEmpty {
            status = localized("No known hidden Unicode elements were found.")
        } else if inspection.isClean {
            status = formatted(
                "Found %d functional Unicode element(s); no known hidden payload risk.",
                inspection.findings.count
            )
        } else {
            status = formatted("Found %d elements to review.", inspection.actionableFindings.count)
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
        output = result.text

        switch (result.linksFound, result.linksChanged) {
        case (0, _):
            status = localized("No HTTP or HTTPS links were found.")
        case (_, 0):
            status = formatted(
                "Found %d links, but none contained known tracking parameters.",
                result.linksFound
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
        status = localized("All Active Guard warning types are enabled.")
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

    private func stopClipboardMonitoring() {
        clipboardMonitor?.cancel()
        clipboardMonitor = nil
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
        let shouldStoreInHistory = Self.shouldStoreInClipboardHistory(pasteboard)
        let typeInventory = ClipboardTypeAnalyzer.analyze(
            typeIdentifiers: (pasteboard.types ?? []).map(\.rawValue)
        )
        let fileMetadataAlert = warnsAboutFileMetadata
            && typeInventory.requiresFileProvenanceReview
        let copiedText = pasteboard.string(forType: .string) ?? ""
        guard !copiedText.isEmpty || fileMetadataAlert else { return }

        if copiedText.isEmpty {
            present(ClipboardNotice(
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
                clipboardContentKinds: typeInventory.kinds,
                pasteboardChangeCount: pasteboard.changeCount
            ))
            return
        }

        let copiedCodeAnalysis = CodeGuardAnalyzer.analyze(copiedText)
        let initialLinkCleaning = URLTrackerCleaner.cleanLinks(in: copiedText, customRules: privateRules)
        var effectiveText = copiedText
        var automaticallyCleaned = false

        if automaticallyCleansLinks,
           !copiedCodeAnalysis.isLikelyCode,
           initialLinkCleaning.linksChanged > 0 {
            automaticallyCleaned = replaceClipboard(
                expectedText: copiedText,
                replacement: initialLinkCleaning.text
            )
            if automaticallyCleaned {
                effectiveText = initialLinkCleaning.text
                status = formatted(
                    "Active Guard automatically cleaned %d copied link(s).",
                    initialLinkCleaning.linksChanged
                )
            }
        } else if automaticallyCleansLinks,
                  copiedCodeAnalysis.isLikelyCode,
                  initialLinkCleaning.linksChanged > 0 {
            status = localized("Code detected. Automatic link cleaning was skipped so source code was not modified.")
        }

        let analysis = ClipboardProtectionAnalyzer.analyze(
            effectiveText,
            recentPatternTexts: patternTexts,
            customRules: privateRules
        )
        patternTexts = analysis.updatedPatternTexts
        patternReport = PatternAnalyzer.analyze(patternTexts)

        if shouldStoreInHistory {
            let entry = ClipboardHistory.makeEntry(
                text: copiedText,
                capturedAt: capturedAt,
                sourceApplicationName: sourceApplication?.localizedName,
                sourceBundleIdentifier: sourceApplication?.bundleIdentifier,
                hiddenUnicodeCount: analysis.inspection.actionableFindings.count,
                codeRiskCount: analysis.codeAnalysis.findings.count,
                trackedLinkCount: initialLinkCleaning.linksChanged,
                binaryKind: analysis.binaryAnalysis.kind,
                wasAutomaticallyCleaned: automaticallyCleaned
            )
            clipboardHistory = ClipboardHistory.appending(entry, to: clipboardHistory)
        }

        let codeRiskCount = warnsAboutCodeRisks ? analysis.codeAnalysis.findings.count : 0
        let binaryDetection = warnsAboutBinaryContent
            ? analysis.binaryAnalysis
            : BinaryContentAnalysis(kind: nil)
        let rawHiddenCount = warnsAboutHiddenUnicode ? analysis.inspection.actionableFindings.count : 0
        let hiddenCount = codeRiskCount > 0 ? 0 : rawHiddenCount
        let trackedLinkCount = warnsAboutTrackedLinks && !automaticallyCleaned
            ? initialLinkCleaning.linksChanged
            : 0
        let alertPatternReport = warnsAboutPatterns && analysis.containsRecentPattern
            ? analysis.recentPatternReport
            : PatternReport(sampleCount: 0, findings: [])

        guard hiddenCount > 0
                || codeRiskCount > 0
                || binaryDetection.isDetected
                || trackedLinkCount > 0
                || alertPatternReport.hasSuspiciousRepetition
                || fileMetadataAlert else {
            return
        }

        let notice = ClipboardNotice(
            clipboardText: effectiveText,
            hiddenUnicodeCount: hiddenCount,
            hiddenUnicodeRiskLevel: hiddenCount > 0
                ? analysis.inspection.highestRiskLevel
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
            clipboardContentKinds: fileMetadataAlert ? typeInventory.kinds : [],
            pasteboardChangeCount: pasteboard.changeCount
        )
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
            onSetSuppressed: { [weak self] kind, isSuppressed in
                self?.setWarning(kind, isSuppressed: isSuppressed)
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
        let result = URLTrackerCleaner.cleanLinks(in: notice.clipboardText, customRules: privateRules)
        guard result.linksChanged > 0 else {
            status = localized("The copied text no longer contains known tracking parameters.")
            noticePanel.dismissCurrent()
            return
        }
        if replaceClipboard(expectedText: notice.clipboardText, replacement: result.text) {
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

    private func setWarning(_ kind: ClipboardWarningKind, isSuppressed: Bool) {
        switch kind {
        case .hiddenUnicode: warnsAboutHiddenUnicode = !isSuppressed
        case .unsafeCode: warnsAboutCodeRisks = !isSuppressed
        case .binaryContent: warnsAboutBinaryContent = !isSuppressed
        case .fileMetadata: warnsAboutFileMetadata = !isSuppressed
        case .trackedLink: warnsAboutTrackedLinks = !isSuppressed
        case .repeatedPattern: warnsAboutPatterns = !isSuppressed
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
        guard pasteboard.string(forType: .string) == expectedText else { return false }
        writeClipboard(replacement)
        return true
    }

    private func writeClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastPasteboardChangeCount = pasteboard.changeCount
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
            PreferenceKey.automaticLinkCleaning,
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
        static let trackedLinkWarnings = "activeProtection.warn.trackedLinks"
        static let patternWarnings = "activeProtection.warn.patterns"
        static let automaticLinkCleaning = "activeProtection.autoCleanLinks"
        static let language = "appearance.language"
        static let legacyPreferencesMigrated = "migration.legacyExecutablePreferences.v1"
    }
}
