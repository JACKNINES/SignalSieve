// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct TextAnalysisLimitation: Sendable, Equatable {
    public let observedUTF8Bytes: Int
    public let maximumUTF8Bytes: Int

    public init(observedUTF8Bytes: Int, maximumUTF8Bytes: Int) {
        self.observedUTF8Bytes = max(0, observedUTF8Bytes)
        self.maximumUTF8Bytes = max(1, maximumUTF8Bytes)
    }
}

/// Shared fail-closed resource limits for interactive text analysis. These
/// limits are enforced in SignalSieveCore so UI and future callers cannot
/// accidentally bypass them.
public enum TextAnalysisBudget {
    /// Large enough for ordinary documents, but bounded before analyzers build
    /// scalar, character, token, or regular-expression working sets.
    public static let maximumInteractiveUTF8Bytes = 1_048_576

    /// Pattern Memory is intended to compare prose excerpts, not retain entire
    /// documents. Individual samples and the whole session have separate caps.
    public static let maximumPatternSampleUTF8Bytes = 64 * 1_024
    public static let maximumPatternMemoryUTF8Bytes = 256 * 1_024

    /// The adaptive baseline needs only a compact writing sample. Bounding it
    /// also limits temporary arrays created by feature extraction.
    public static let maximumAdaptiveSampleUTF8Bytes = 64 * 1_024

    /// Aggregate-only model JSON should remain tiny. A larger file is treated
    /// as corrupt or tampered state before it is decoded.
    public static let maximumAdaptiveModelFileBytes = 64 * 1_024

    public static func limitation(
        for text: String,
        maximumUTF8Bytes: Int = maximumInteractiveUTF8Bytes
    ) -> TextAnalysisLimitation? {
        let byteCount = text.utf8.count
        guard byteCount > maximumUTF8Bytes else { return nil }
        return TextAnalysisLimitation(
            observedUTF8Bytes: byteCount,
            maximumUTF8Bytes: maximumUTF8Bytes
        )
    }
}
