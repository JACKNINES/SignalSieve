// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum ClipboardAutomationProtocol: String, CaseIterable, Codable, Sendable {
    /// Default behavior: do not rewrite copies and show every enabled warning.
    case reviewAll = "review-all"
    /// Safe Clean eligible text copies.
    case safeClean = "safe-clean"
    /// Strict Clean eligible text copies.
    case strictClean = "strict-clean"
    /// Rebuild eligible text through a local bitmap and OCR boundary.
    case visualTransfer = "visual-transfer"

    public static func persistedOrReviewAll(_ rawValue: String?) -> Self {
        // Versions before the alert-visibility setting stored this legacy
        // value inside the cleaning protocol. It now means no auto-cleaning.
        if rawValue == "high-risk-only" { return .reviewAll }
        return rawValue.flatMap(Self.init(rawValue:)) ?? .reviewAll
    }

    public var cleaningMode: CleaningMode? {
        switch self {
        case .reviewAll, .visualTransfer: nil
        case .safeClean: .safe
        case .strictClean: .strict
        }
    }
}

public enum ClipboardAlertVisibility: String, CaseIterable, Codable, Sendable {
    case showAll = "show-all"
    case hideGreenAndYellow = "hide-green-and-yellow"
    case redOnly = "red-only"

    public static func persistedOrShowAll(
        _ rawValue: String?,
        legacyHidesGreenAndYellow: Bool = false
    ) -> Self {
        if let rawValue, let visibility = Self(rawValue: rawValue) {
            return visibility
        }
        return legacyHidesGreenAndYellow ? .hideGreenAndYellow : .showAll
    }
}

public enum ClipboardAlertVisibilityPolicy {
    /// Red alerts are mandatory under every preference. The intermediate
    /// option keeps orange alerts; the strongest option presents red only.
    public static func shouldPresent(
        _ priority: ClipboardAlertPriority,
        visibility: ClipboardAlertVisibility
    ) -> Bool {
        switch visibility {
        case .showAll:
            true
        case .hideGreenAndYellow:
            priority != .standard
        case .redOnly:
            priority == .high
        }
    }

    /// Category preferences may silence ordinary findings, but never a red
    /// finding. This prevents older per-category switches from becoming an
    /// indirect way to disable mandatory alerts.
    public static func shouldIncludeCategory(
        isEnabled: Bool,
        highestRisk: HiddenElementRiskLevel?
    ) -> Bool {
        isEnabled || highestRisk == .high
    }

    public static func shouldIncludeScamCategory(
        isEnabled: Bool,
        threatLevel: ScamThreatLevel?
    ) -> Bool {
        isEnabled || threatLevel == .high
    }
}

public enum ClipboardAutomationSkipReason: String, Sendable, Equatable {
    case sourceCode
    case nonTextRepresentation
    case privacySensitiveClipboard
    case inputTooLarge
    case visualTransferIntegrityCheckFailed
    case visualTransferFailed

    public var receiptLabel: String {
        switch self {
        case .sourceCode:
            "source code"
        case .nonTextRepresentation:
            "file or image representation"
        case .privacySensitiveClipboard:
            "privacy-sensitive clipboard type"
        case .inputTooLarge:
            "input too large"
        case .visualTransferIntegrityCheckFailed:
            "OCR integrity check failed"
        case .visualTransferFailed:
            "local OCR failed"
        }
    }
}

public enum ClipboardAutomaticCleaningOutcome: Sendable, Equatable {
    case noDetectedAlerts
    case cleanedAllDetectedAlerts
    case cleanedSomeDetectedAlerts
    case alertsRemain
    case skipped
}

public enum ClipboardCleanReceiptVerdict: Sendable, Equatable {
    case noSupportedRiskRemains
    case cleanedSourceNeedsReview
    case riskRemainsDoNotShare
}

/// Content-free evidence for the automatic cleaning decision. It records only
/// bounded counts, severities, the selected protocol, and a short reason so it
/// can be shown or stored in session memory without retaining more copied text.
public struct ClipboardCleanReceipt: Sendable, Equatable {
    public static let maximumReasonCharacters = 96

    public let selectedProtocol: ClipboardAutomationProtocol
    public let verdict: ClipboardCleanReceiptVerdict
    public let originalAlertCount: Int
    public let originalPriority: ClipboardAlertPriority
    public let removedElementCount: Int
    public let replacedElementCount: Int
    public let remainingAlertCount: Int
    public let remainingPriority: ClipboardAlertPriority
    public let wasAutomaticCleaningSkipped: Bool
    public let reason: String

    public init(
        selectedProtocol: ClipboardAutomationProtocol,
        verdict: ClipboardCleanReceiptVerdict,
        originalAlertCount: Int,
        originalPriority: ClipboardAlertPriority,
        removedElementCount: Int,
        replacedElementCount: Int,
        remainingAlertCount: Int,
        remainingPriority: ClipboardAlertPriority,
        wasAutomaticCleaningSkipped: Bool,
        reason: String
    ) {
        self.selectedProtocol = selectedProtocol
        self.verdict = verdict
        self.originalAlertCount = max(0, originalAlertCount)
        self.originalPriority = originalPriority
        self.removedElementCount = max(0, removedElementCount)
        self.replacedElementCount = max(0, replacedElementCount)
        self.remainingAlertCount = max(0, remainingAlertCount)
        self.remainingPriority = remainingPriority
        self.wasAutomaticCleaningSkipped = wasAutomaticCleaningSkipped
        self.reason = Self.boundedReason(reason)
    }

    private static func boundedReason(_ reason: String) -> String {
        let flattened = reason
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > maximumReasonCharacters else { return flattened }
        return String(flattened.prefix(maximumReasonCharacters - 1)) + "…"
    }
}

/// Evidence retained in session memory after an automatic cleaning protocol.
/// Counts come from local reanalysis of the original and final text; they are
/// not an assertion that the source itself is trustworthy or generally safe.
public struct ClipboardAutomaticCleaningAudit: Sendable, Equatable {
    public let selectedProtocol: ClipboardAutomationProtocol
    public let didWriteCleanedText: Bool
    public let removedElementCount: Int
    public let replacedElementCount: Int
    public let originalAlertCount: Int
    public let remainingAlertCount: Int
    public let originalPriority: ClipboardAlertPriority
    public let remainingPriority: ClipboardAlertPriority
    public let skipReason: ClipboardAutomationSkipReason?

    public var mode: CleaningMode? { selectedProtocol.cleaningMode }

    public init(
        mode: CleaningMode,
        selectedProtocol: ClipboardAutomationProtocol? = nil,
        didWriteCleanedText: Bool,
        removedElementCount: Int,
        replacedElementCount: Int,
        originalAlertCount: Int,
        remainingAlertCount: Int,
        originalPriority: ClipboardAlertPriority,
        remainingPriority: ClipboardAlertPriority,
        skipReason: ClipboardAutomationSkipReason? = nil
    ) {
        self.selectedProtocol = selectedProtocol
            ?? (mode == .strict ? .strictClean : .safeClean)
        self.didWriteCleanedText = didWriteCleanedText
        self.removedElementCount = max(0, removedElementCount)
        self.replacedElementCount = max(0, replacedElementCount)
        self.originalAlertCount = max(0, originalAlertCount)
        self.remainingAlertCount = max(0, remainingAlertCount)
        self.originalPriority = originalPriority
        self.remainingPriority = remainingPriority
        self.skipReason = skipReason
    }

    public init(
        selectedProtocol: ClipboardAutomationProtocol,
        didWriteCleanedText: Bool,
        removedElementCount: Int,
        replacedElementCount: Int,
        originalAlertCount: Int,
        remainingAlertCount: Int,
        originalPriority: ClipboardAlertPriority,
        remainingPriority: ClipboardAlertPriority,
        skipReason: ClipboardAutomationSkipReason? = nil
    ) {
        self.selectedProtocol = selectedProtocol
        self.didWriteCleanedText = didWriteCleanedText
        self.removedElementCount = max(0, removedElementCount)
        self.replacedElementCount = max(0, replacedElementCount)
        self.originalAlertCount = max(0, originalAlertCount)
        self.remainingAlertCount = max(0, remainingAlertCount)
        self.originalPriority = originalPriority
        self.remainingPriority = remainingPriority
        self.skipReason = skipReason
    }

    public var outcome: ClipboardAutomaticCleaningOutcome {
        if skipReason != nil { return .skipped }
        guard originalAlertCount > 0 else { return .noDetectedAlerts }
        if didWriteCleanedText, remainingAlertCount == 0 {
            return .cleanedAllDetectedAlerts
        }
        if didWriteCleanedText, remainingAlertCount < originalAlertCount {
            return .cleanedSomeDetectedAlerts
        }
        return .alertsRemain
    }

    public var redRiskWasRemoved: Bool {
        didWriteCleanedText
            && originalPriority == .high
            && remainingPriority != .high
    }

    public var redRiskRemains: Bool {
        remainingPriority == .high
    }

    public var receipt: ClipboardCleanReceipt {
        ClipboardCleanReceipt(
            selectedProtocol: selectedProtocol,
            verdict: receiptVerdict,
            originalAlertCount: originalAlertCount,
            originalPriority: originalPriority,
            removedElementCount: removedElementCount,
            replacedElementCount: replacedElementCount,
            remainingAlertCount: remainingAlertCount,
            remainingPriority: remainingPriority,
            wasAutomaticCleaningSkipped: skipReason != nil,
            reason: receiptReason
        )
    }

    private var receiptVerdict: ClipboardCleanReceiptVerdict {
        if remainingPriority == .high {
            return .riskRemainsDoNotShare
        }
        if skipReason != nil || remainingAlertCount > 0 || originalPriority == .high {
            return .cleanedSourceNeedsReview
        }
        return .noSupportedRiskRemains
    }

    private var receiptReason: String {
        if let skipReason {
            return "Automatic cleaning skipped: \(skipReason.receiptLabel)."
        }
        if remainingPriority == .high {
            return "High-risk finding remained after reanalysis."
        }
        if originalPriority == .high {
            return "High-risk finding was removed; review the source."
        }
        if remainingAlertCount > 0 {
            return "Lower-risk findings remain after reanalysis."
        }
        if originalAlertCount == 0 {
            return "No supported cleaning risks were detected."
        }
        return "No supported cleaning risks remain after reanalysis."
    }
}

public struct ClipboardAutomationResult: Sendable, Equatable {
    public let text: String
    public let removedCount: Int
    public let replacedCount: Int
    public let inputChanged: Bool
    public let skipReason: ClipboardAutomationSkipReason?

    public init(
        text: String,
        removedCount: Int = 0,
        replacedCount: Int = 0,
        inputChanged: Bool = false,
        skipReason: ClipboardAutomationSkipReason? = nil
    ) {
        self.text = text
        self.removedCount = removedCount
        self.replacedCount = replacedCount
        self.inputChanged = inputChanged
        self.skipReason = skipReason
    }

    public var didChange: Bool { inputChanged }
}

/// Pure policy used by Active Guard before it writes anything to NSPasteboard.
public enum ClipboardAutomationPolicy {
    public static let maximumAutomaticVisualTransferCharacterCount = 4_000

    public static func skipReason(
        for selection: ClipboardAutomationProtocol,
        text: String,
        isLikelyCode: Bool,
        hasNonTextRepresentation: Bool,
        isPrivacySensitive: Bool
    ) -> ClipboardAutomationSkipReason? {
        guard selection != .reviewAll else { return nil }
        if TextAnalysisBudget.limitation(for: text) != nil { return .inputTooLarge }
        if isPrivacySensitive { return .privacySensitiveClipboard }
        if hasNonTextRepresentation { return .nonTextRepresentation }
        if isLikelyCode { return .sourceCode }
        if selection == .visualTransfer,
           text.count > maximumAutomaticVisualTransferCharacterCount {
            return .inputTooLarge
        }
        return nil
    }

    /// Strict Clean promises a plain-text result. HTML/RTF must therefore be
    /// flattened even when its visible string needs no Unicode changes.
    public static func shouldFlattenRichText(
        using selection: ClipboardAutomationProtocol,
        hasRichTextRepresentation: Bool,
        skipReason: ClipboardAutomationSkipReason?
    ) -> Bool {
        selection == .strictClean
            && hasRichTextRepresentation
            && skipReason == nil
    }

    public static func shouldQuarantineAutomaticReplacement(
        candidatePriority: ClipboardAlertPriority,
        skipReason: ClipboardAutomationSkipReason?
    ) -> Bool {
        skipReason == nil && candidatePriority == .high
    }

    /// Automatic OCR is lossy. Reject candidates that alter values for which
    /// a transcription error has disproportionate impact.
    public static func acceptsAutomaticVisualTransfer(
        original: String,
        candidate: String
    ) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let report = RewriteIntegrityAnalyzer.analyze(
            original: original,
            candidate: candidate
        )
        return !report.hasProtectedValueChanges
            && report.assessment != .codeNotSupported
            && report.assessment != .inputTooLarge
    }

    public static func transform(
        _ text: String,
        using selection: ClipboardAutomationProtocol,
        isLikelyCode: Bool,
        hasNonTextRepresentation: Bool,
        isPrivacySensitive: Bool
    ) -> ClipboardAutomationResult {
        guard selection != .reviewAll else {
            return ClipboardAutomationResult(text: text)
        }
        if let skipReason = skipReason(
            for: selection,
            text: text,
            isLikelyCode: isLikelyCode,
            hasNonTextRepresentation: hasNonTextRepresentation,
            isPrivacySensitive: isPrivacySensitive
        ) {
            return ClipboardAutomationResult(text: text, skipReason: skipReason)
        }
        guard let mode = selection.cleaningMode else {
            // Visual Transfer is performed asynchronously by the app after
            // this shared eligibility policy has accepted the copy.
            return ClipboardAutomationResult(text: text)
        }

        let cleaned = TextCleaner.clean(text, mode: mode)
        return ClipboardAutomationResult(
            text: cleaned.text,
            removedCount: cleaned.removedCount,
            replacedCount: cleaned.replacedCount,
            inputChanged: cleaned.text != text
        )
    }
}
