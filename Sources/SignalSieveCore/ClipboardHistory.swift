// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct ClipboardHistoryEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let capturedAt: Date
    public let sourceApplicationName: String?
    public let sourceBundleIdentifier: String?
    public let text: String
    public let originalCharacterCount: Int
    public let isTruncated: Bool
    public let hiddenUnicodeCount: Int
    public let codeRiskCount: Int
    public let trackedLinkCount: Int
    public let binaryKind: BinaryContentKind?
    public let wasAutomaticallyCleaned: Bool

    public init(
        id: UUID = UUID(),
        capturedAt: Date,
        sourceApplicationName: String?,
        sourceBundleIdentifier: String?,
        text: String,
        originalCharacterCount: Int,
        isTruncated: Bool,
        hiddenUnicodeCount: Int,
        codeRiskCount: Int,
        trackedLinkCount: Int,
        binaryKind: BinaryContentKind?,
        wasAutomaticallyCleaned: Bool
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.text = text
        self.originalCharacterCount = originalCharacterCount
        self.isTruncated = isTruncated
        self.hiddenUnicodeCount = hiddenUnicodeCount
        self.codeRiskCount = codeRiskCount
        self.trackedLinkCount = trackedLinkCount
        self.binaryKind = binaryKind
        self.wasAutomaticallyCleaned = wasAutomaticallyCleaned
    }

    public var visiblePreview: String {
        ClipboardHistory.visiblePreview(text)
    }

    public var hasKnownRisk: Bool {
        hiddenUnicodeCount > 0
            || codeRiskCount > 0
            || trackedLinkCount > 0
            || binaryKind != nil
    }
}

public enum ClipboardHistory {
    public static let maximumEntries = 50
    public static let maximumStoredCharacters = 20_000
    public static let maximumPreviewCharacters = 360

    public static func makeEntry(
        text: String,
        capturedAt: Date = Date(),
        sourceApplicationName: String?,
        sourceBundleIdentifier: String?,
        hiddenUnicodeCount: Int,
        codeRiskCount: Int,
        trackedLinkCount: Int,
        binaryKind: BinaryContentKind?,
        wasAutomaticallyCleaned: Bool
    ) -> ClipboardHistoryEntry {
        let characterCount = text.count
        let stored = String(text.prefix(maximumStoredCharacters))
        return ClipboardHistoryEntry(
            capturedAt: capturedAt,
            sourceApplicationName: sourceApplicationName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            text: stored,
            originalCharacterCount: characterCount,
            isTruncated: characterCount > maximumStoredCharacters,
            hiddenUnicodeCount: hiddenUnicodeCount,
            codeRiskCount: codeRiskCount,
            trackedLinkCount: trackedLinkCount,
            binaryKind: binaryKind,
            wasAutomaticallyCleaned: wasAutomaticallyCleaned
        )
    }

    /// Inserts newest first and keeps memory usage bounded for long sessions.
    public static func appending(
        _ entry: ClipboardHistoryEntry,
        to existing: [ClipboardHistoryEntry]
    ) -> [ClipboardHistoryEntry] {
        Array(([entry] + existing).prefix(maximumEntries))
    }

    public static func visiblePreview(_ text: String) -> String {
        let bounded = String(text.prefix(maximumPreviewCharacters))
        let scalars = Array(bounded.unicodeScalars)
        let visible = scalars.enumerated().map { index, scalar in
            guard let assessment = HiddenTextAnalyzer.assess(scalars, at: index),
                  assessment.riskLevel != .clear else {
                return String(scalar)
            }
            return String(format: "⟦U+%04X⟧", scalar.value)
        }.joined()
        return text.count > maximumPreviewCharacters ? visible + "…" : visible
    }
}
