// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum ClipboardAutomationProtocol: String, CaseIterable, Codable, Sendable {
    /// Default behavior: do not rewrite copies and show every enabled warning.
    case reviewAll = "review-all"
    /// Safe Clean eligible text copies.
    case safeClean = "safe-clean"
    /// Strict Clean eligible text copies.
    case strictClean = "strict-clean"

    public static func persistedOrReviewAll(_ rawValue: String?) -> Self {
        // Versions before the alert-visibility setting stored this legacy
        // value inside the cleaning protocol. It now means no auto-cleaning.
        if rawValue == "high-risk-only" { return .reviewAll }
        return rawValue.flatMap(Self.init(rawValue:)) ?? .reviewAll
    }

    public var cleaningMode: CleaningMode? {
        switch self {
        case .reviewAll: nil
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
}

public enum ClipboardAutomaticCleaningOutcome: Sendable, Equatable {
    case noDetectedAlerts
    case cleanedAllDetectedAlerts
    case cleanedSomeDetectedAlerts
    case alertsRemain
    case skipped
}

/// Evidence retained in session memory after automatic Safe or Strict Clean.
/// Counts come from deterministic reanalysis of the original and final text;
/// they are not an assertion that the source itself is trustworthy.
public struct ClipboardAutomaticCleaningAudit: Sendable, Equatable {
    public let mode: CleaningMode
    public let didWriteCleanedText: Bool
    public let removedElementCount: Int
    public let replacedElementCount: Int
    public let originalAlertCount: Int
    public let remainingAlertCount: Int
    public let originalPriority: ClipboardAlertPriority
    public let remainingPriority: ClipboardAlertPriority
    public let skipReason: ClipboardAutomationSkipReason?

    public init(
        mode: CleaningMode,
        didWriteCleanedText: Bool,
        removedElementCount: Int,
        replacedElementCount: Int,
        originalAlertCount: Int,
        remainingAlertCount: Int,
        originalPriority: ClipboardAlertPriority,
        remainingPriority: ClipboardAlertPriority,
        skipReason: ClipboardAutomationSkipReason? = nil
    ) {
        self.mode = mode
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
        originalPriority == .high && remainingPriority == .high
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
    public static func transform(
        _ text: String,
        using selection: ClipboardAutomationProtocol,
        isLikelyCode: Bool,
        hasNonTextRepresentation: Bool,
        isPrivacySensitive: Bool
    ) -> ClipboardAutomationResult {
        guard let mode = selection.cleaningMode else {
            return ClipboardAutomationResult(text: text)
        }
        guard !isPrivacySensitive else {
            return ClipboardAutomationResult(
                text: text,
                skipReason: .privacySensitiveClipboard
            )
        }
        guard !hasNonTextRepresentation else {
            return ClipboardAutomationResult(
                text: text,
                skipReason: .nonTextRepresentation
            )
        }
        guard !isLikelyCode else {
            return ClipboardAutomationResult(text: text, skipReason: .sourceCode)
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
