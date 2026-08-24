// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum CleaningMode: String, Sendable {
    case safe
    case strict
}

public struct CleaningResult: Sendable, Equatable {
    public let text: String
    public let removedCount: Int
    public let replacedCount: Int

    public init(text: String, removedCount: Int, replacedCount: Int) {
        self.text = text
        self.removedCount = removedCount
        self.replacedCount = replacedCount
    }
}

public enum TextCleaner {
    public static func clean(_ text: String, mode: CleaningMode) -> CleaningResult {
        let covertReport = CovertTextChannelAnalyzer.analyze(text)
        let hasTrailingWhitespaceChannel = covertReport.findings.contains {
            $0.kind == .trailingWhitespace
        }
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var scalars = String.UnicodeScalarView()
        var removed = 0
        var replaced = 0
        let sourceScalars = Array(normalizedNewlines.unicodeScalars)

        for (index, scalar) in sourceScalars.enumerated() {
            guard let assessment = HiddenTextAnalyzer.assess(sourceScalars, at: index) else {
                scalars.append(scalar)
                continue
            }

            if mode == .safe, assessment.shouldPreserveInSafeCleaning {
                scalars.append(scalar)
                continue
            }

            switch assessment.kind {
            case .unusualWhitespace:
                scalars.append(" ")
                replaced += 1

            case .variationSelector, .invisibleFiller, .layoutControl:
                removed += 1

            case .zeroWidth:
                removed += 1

            case .privateUse, .unassigned:
                if mode == .strict {
                    removed += 1
                } else {
                    scalars.append(scalar)
                }

            case .bidirectional, .tag, .control, .reservedIgnorable, .noncharacter:
                removed += 1
            }
        }

        let interim = String(scalars)
        let normalized = mode == .strict
            ? interim.precomposedStringWithCompatibilityMapping
            : interim.precomposedStringWithCanonicalMapping
        let trailingResult = hasTrailingWhitespaceChannel
            ? neutralizeTrailingWhitespace(in: normalized)
            : (normalized, 0)

        return CleaningResult(
            text: trailingResult.0,
            removedCount: removed + trailingResult.1,
            replacedCount: replaced
        )
    }

    private static func neutralizeTrailingWhitespace(in text: String) -> (String, Int) {
        var removed = 0
        let lines = text.components(separatedBy: "\n").map { sourceLine in
            var line = sourceLine
            while let last = line.last, last == " " || last == "\t" {
                line.removeLast()
                removed += 1
            }
            return line
        }
        return (lines.joined(separator: "\n"), removed)
    }
}
