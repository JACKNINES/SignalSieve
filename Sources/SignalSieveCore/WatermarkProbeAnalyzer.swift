// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum WatermarkProbeAssessment: String, Sendable, Equatable {
    case insufficientText = "Not enough text"
    case noElevatedRegularity = "No elevated surface regularity"
    case someRegularity = "Some surface regularity"
    case elevatedRegularity = "Elevated surface regularity"
}

public enum WatermarkProbeSignalKind: String, CaseIterable, Sendable, Equatable {
    case repeatedNGrams = "Repeated word sequences"
    case lowLexicalDiversity = "Low lexical diversity"
    case regularSentenceCadence = "Regular sentence cadence"
    case repeatedSentenceOpenings = "Repeated sentence openings"

    public var researchURL: URL? {
        let topic: String
        switch self {
        case .repeatedNGrams:
            topic = "LLM statistical watermark repeated n-gram analysis"
        case .lowLexicalDiversity:
            topic = "lexical diversity AI generated text detection limitations"
        case .regularSentenceCadence:
            topic = "sentence length regularity AI text detection false positives"
        case .repeatedSentenceOpenings:
            topic = "repeated sentence openings stylometry limitations"
        }

        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: topic)]
        return components?.url
    }
}

public struct WatermarkProbeSignal: Identifiable, Sendable, Equatable {
    public let kind: WatermarkProbeSignalKind
    /// A bounded heuristic contribution, not a probability.
    public let strength: Double
    /// A ratio or coefficient represented on a 0...1 scale.
    public let observedValue: Double
    public let isAvailable: Bool

    public var id: String { kind.rawValue }
    public var isElevated: Bool { isAvailable && strength >= 0.4 }

    public init(
        kind: WatermarkProbeSignalKind,
        strength: Double,
        observedValue: Double,
        isAvailable: Bool = true
    ) {
        self.kind = kind
        self.strength = min(max(strength, 0), 1)
        self.observedValue = max(observedValue, 0)
        self.isAvailable = isAvailable
    }
}

public struct WatermarkProbeReport: Sendable, Equatable {
    public let tokenCount: Int
    public let sentenceCount: Int
    public let minimumTokenCount: Int
    public let recommendedTokenCount: Int
    public let hiddenUnicodeFindingCount: Int
    public let assessment: WatermarkProbeAssessment
    /// An aggregate heuristic score, not a probability or confidence value.
    public let heuristicScore: Double
    public let signals: [WatermarkProbeSignal]

    public var hasEnoughText: Bool { tokenCount >= minimumTokenCount }
    public var elevatedSignalCount: Int { signals.filter(\.isElevated).count }

    public init(
        tokenCount: Int,
        sentenceCount: Int,
        minimumTokenCount: Int,
        recommendedTokenCount: Int,
        hiddenUnicodeFindingCount: Int,
        assessment: WatermarkProbeAssessment,
        heuristicScore: Double,
        signals: [WatermarkProbeSignal]
    ) {
        self.tokenCount = tokenCount
        self.sentenceCount = sentenceCount
        self.minimumTokenCount = minimumTokenCount
        self.recommendedTokenCount = recommendedTokenCount
        self.hiddenUnicodeFindingCount = hiddenUnicodeFindingCount
        self.assessment = assessment
        self.heuristicScore = min(max(heuristicScore, 0), 1)
        self.signals = signals
    }
}

/// Performs a keyless, local screen for visible statistical regularity.
///
/// This deliberately does not claim to detect SynthID or any provider's
/// proprietary watermark. A proprietary mark may be indistinguishable from
/// ordinary language to a keyless observer; confirmation requires a compatible
/// detector and validated provider-specific parameters.
public enum WatermarkProbeAnalyzer {
    public static let minimumTokenCount = 80
    public static let recommendedTokenCount = 180

    private static let wordExpression = try? NSRegularExpression(
        pattern: #"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*"#
    )

    public static func analyze(_ text: String) -> WatermarkProbeReport {
        let allTokens = tokens(text)
        let sentenceTokens = sentences(in: text)
        let hiddenCount = HiddenTextAnalyzer.inspect(text).totalActionableFindingCount

        let repeatedRatio = repeatedNGramRatio(allTokens, length: 3)
        let lexicalDiversity = movingWindowLexicalDiversity(allTokens, windowSize: 50)
        let cadence = sentenceCadence(sentenceTokens)
        let openingReuse = repeatedOpeningRatio(sentenceTokens)

        let signals = [
            WatermarkProbeSignal(
                kind: .repeatedNGrams,
                strength: risingStrength(repeatedRatio, from: 0.04, to: 0.18),
                observedValue: repeatedRatio,
                isAvailable: allTokens.count >= 20
            ),
            WatermarkProbeSignal(
                kind: .lowLexicalDiversity,
                strength: fallingStrength(lexicalDiversity, from: 0.72, to: 0.50),
                observedValue: lexicalDiversity,
                isAvailable: allTokens.count >= 40
            ),
            WatermarkProbeSignal(
                kind: .regularSentenceCadence,
                strength: fallingStrength(cadence, from: 0.28, to: 0.10),
                observedValue: cadence,
                isAvailable: sentenceTokens.count >= 5
            ),
            WatermarkProbeSignal(
                kind: .repeatedSentenceOpenings,
                strength: risingStrength(openingReuse, from: 0.18, to: 0.55),
                observedValue: openingReuse,
                isAvailable: sentenceTokens.count >= 5
            )
        ]

        let weightedSignals: [(WatermarkProbeSignal, Double)] = [
            (signals[0], 0.32),
            (signals[1], 0.28),
            (signals[2], 0.20),
            (signals[3], 0.20)
        ]
        let availableWeight = weightedSignals.reduce(0.0) { partial, item in
            partial + (item.0.isAvailable ? item.1 : 0)
        }
        let rawScore = weightedSignals.reduce(0.0) { partial, item in
            partial + (item.0.isAvailable ? item.0.strength * item.1 : 0)
        }
        let score = availableWeight > 0 ? rawScore / availableWeight : 0
        let elevatedCount = signals.filter(\.isElevated).count

        let assessment: WatermarkProbeAssessment
        if allTokens.count < minimumTokenCount {
            assessment = .insufficientText
        } else if elevatedCount >= 3 && score >= 0.58 {
            assessment = .elevatedRegularity
        } else if elevatedCount >= 2 && score >= 0.38 {
            assessment = .someRegularity
        } else {
            assessment = .noElevatedRegularity
        }

        return WatermarkProbeReport(
            tokenCount: allTokens.count,
            sentenceCount: sentenceTokens.count,
            minimumTokenCount: minimumTokenCount,
            recommendedTokenCount: recommendedTokenCount,
            hiddenUnicodeFindingCount: hiddenCount,
            assessment: assessment,
            heuristicScore: score,
            signals: signals
        )
    }

    private static func repeatedNGramRatio(_ words: [String], length: Int) -> Double {
        guard words.count >= length else { return 0 }
        var counts: [String: Int] = [:]
        for index in 0...(words.count - length) {
            let value = words[index..<(index + length)].joined(separator: " ")
            counts[value, default: 0] += 1
        }
        let total = words.count - length + 1
        let repeatedPositions = counts.values.reduce(0) { $0 + max($1 - 1, 0) }
        return Double(repeatedPositions) / Double(total)
    }

    private static func movingWindowLexicalDiversity(
        _ words: [String],
        windowSize: Int
    ) -> Double {
        guard !words.isEmpty else { return 0 }
        guard words.count > windowSize else {
            return Double(Set(words).count) / Double(words.count)
        }

        let strideSize = max(windowSize / 2, 1)
        var values: [Double] = []
        var start = 0
        while start + windowSize <= words.count {
            let window = words[start..<(start + windowSize)]
            values.append(Double(Set(window).count) / Double(windowSize))
            start += strideSize
        }
        if start < words.count {
            let tail = words[(words.count - windowSize)..<words.count]
            values.append(Double(Set(tail).count) / Double(windowSize))
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func sentenceCadence(_ sentenceTokens: [[String]]) -> Double {
        guard sentenceTokens.count >= 2 else { return 1 }
        let lengths = sentenceTokens.map { Double($0.count) }
        let mean = lengths.reduce(0, +) / Double(lengths.count)
        guard mean > 0 else { return 1 }
        let variance = lengths.reduce(0.0) { partial, length in
            let difference = length - mean
            return partial + (difference * difference)
        } / Double(lengths.count)
        return sqrt(variance) / mean
    }

    private static func repeatedOpeningRatio(_ sentenceTokens: [[String]]) -> Double {
        let openings = sentenceTokens.compactMap { words -> String? in
            guard words.count >= 4 else { return nil }
            return words.prefix(2).joined(separator: " ")
        }
        guard !openings.isEmpty else { return 0 }
        let uniqueCount = Set(openings).count
        return Double(openings.count - uniqueCount) / Double(openings.count)
    }

    private static func sentences(in text: String) -> [[String]] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map(tokens)
            .filter { $0.count >= 4 }
    }

    private static func tokens(_ text: String) -> [String] {
        guard let wordExpression else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return wordExpression.matches(in: text, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange]).lowercased()
        }
    }

    private static func risingStrength(_ value: Double, from lower: Double, to upper: Double) -> Double {
        guard upper > lower else { return 0 }
        return min(max((value - lower) / (upper - lower), 0), 1)
    }

    private static func fallingStrength(_ value: Double, from upper: Double, to lower: Double) -> Double {
        guard upper > lower else { return 0 }
        return min(max((upper - value) / (upper - lower), 0), 1)
    }
}
