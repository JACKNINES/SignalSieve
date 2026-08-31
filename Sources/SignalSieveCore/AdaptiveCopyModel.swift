// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct AdaptiveFeatureDeviation: Identifiable, Sendable, Equatable {
    public let id: String
    public let feature: String
    public let standardDeviations: Double
    public let direction: String

    public init(feature: String, standardDeviations: Double, direction: String) {
        self.id = feature
        self.feature = feature
        self.standardDeviations = standardDeviations
        self.direction = direction
    }
}

public struct AdaptiveCopyAnalysis: Sendable, Equatable {
    public let sampleCountBeforeLearning: Int
    public let anomalyScore: Double
    public let deviations: [AdaptiveFeatureDeviation]
    public let wasEligibleForLearning: Bool

    public init(
        sampleCountBeforeLearning: Int,
        anomalyScore: Double,
        deviations: [AdaptiveFeatureDeviation],
        wasEligibleForLearning: Bool
    ) {
        self.sampleCountBeforeLearning = sampleCountBeforeLearning
        self.anomalyScore = min(max(anomalyScore, 0), 1)
        self.deviations = deviations
        self.wasEligibleForLearning = wasEligibleForLearning
    }

    public var isWarmedUp: Bool {
        sampleCountBeforeLearning >= AdaptiveCopyModel.minimumTrainingSamples
    }

    public var isAnomalous: Bool {
        isWarmedUp && isLearningOutlier
    }

    public var isLearningOutlier: Bool {
        deviations.count >= 2 && anomalyScore >= 0.62
    }
}

public struct AdaptiveCopyModel: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let minimumTrainingSamples = 12
    public static let minimumOutlierScreeningSamples = 4
    public static let minimumCharacters = 24

    public private(set) var schemaVersion: Int
    public private(set) var sampleCount: Int
    private var statistics: [String: RunningStatistic]

    public init() {
        self.schemaVersion = Self.currentSchemaVersion
        self.sampleCount = 0
        self.statistics = [:]
    }

    /// Evaluates before learning, then updates only aggregate numeric state.
    /// Clipboard text, tokens, hashes, URLs, and application names are never
    /// stored in the model.
    public mutating func evaluateAndLearn(
        _ text: String,
        allowLearning: Bool = true
    ) -> AdaptiveCopyAnalysis {
        let features = Self.features(for: text)
        guard text.count >= Self.minimumCharacters, !features.isEmpty else {
            return AdaptiveCopyAnalysis(
                sampleCountBeforeLearning: sampleCount,
                anomalyScore: 0,
                deviations: [],
                wasEligibleForLearning: false
            )
        }

        let priorCount = sampleCount
        let analysis = evaluateFeatures(features, priorCount: priorCount)
        let shouldLearn = allowLearning && !analysis.isLearningOutlier
        let result = AdaptiveCopyAnalysis(
            sampleCountBeforeLearning: analysis.sampleCountBeforeLearning,
            anomalyScore: analysis.anomalyScore,
            deviations: analysis.deviations,
            wasEligibleForLearning: shouldLearn
        )
        guard shouldLearn else { return result }
        for (key, value) in features {
            var statistic = statistics[key] ?? RunningStatistic()
            statistic.add(winsorized(value, using: statistic))
            statistics[key] = statistic
        }
        sampleCount += 1
        return result
    }

    /// Scores a text against the current aggregate baseline without changing
    /// the model. This is used by the manual inspector.
    public func assess(_ text: String) -> AdaptiveCopyAnalysis {
        let features = Self.features(for: text)
        guard text.count >= Self.minimumCharacters, !features.isEmpty else {
            return AdaptiveCopyAnalysis(
                sampleCountBeforeLearning: sampleCount,
                anomalyScore: 0,
                deviations: [],
                wasEligibleForLearning: false
            )
        }
        return evaluateFeatures(features, priorCount: sampleCount)
    }

    public static func features(for text: String) -> [String: Double] {
        guard TextAnalysisBudget.limitation(
            for: text,
            maximumUTF8Bytes: TextAnalysisBudget.maximumAdaptiveSampleUTF8Bytes
        ) == nil else { return [:] }
        let characters = Array(text)
        guard !characters.isEmpty else { return [:] }
        let words = text.split { !$0.isLetter && !$0.isNumber }
        let sentences = text.split { ".!?\n".contains($0) }.filter { !$0.isEmpty }
        let count = Double(characters.count)
        let wordCount = max(1, words.count)
        let uniqueWords = Set(words.map { $0.lowercased() })
        let sentenceLengths = sentences.map { sentence in
            Double(sentence.split { !$0.isLetter && !$0.isNumber }.count)
        }.filter { $0 > 0 }

        return [
            "length": log1p(count),
            "average word length": Double(words.reduce(0) { $0 + $1.count }) / Double(wordCount),
            "lexical diversity": Double(uniqueWords.count) / Double(wordCount),
            "sentence cadence": coefficientOfVariation(sentenceLengths),
            "uppercase ratio": ratio(in: characters) { $0.isUppercase },
            "digit ratio": ratio(in: characters) { $0.isNumber },
            "punctuation ratio": ratio(in: characters) { $0.isPunctuation },
            "line-break ratio": ratio(in: characters) { $0 == "\n" },
            "non-ASCII ratio": ratio(in: characters) { character in
                character.unicodeScalars.contains { !$0.isASCII }
            },
            "URL density": Double(urlCount(in: text)) / Double(wordCount)
        ]
    }

    private func evaluateFeatures(
        _ features: [String: Double],
        priorCount: Int
    ) -> AdaptiveCopyAnalysis {
        guard priorCount >= Self.minimumOutlierScreeningSamples else {
            return AdaptiveCopyAnalysis(
                sampleCountBeforeLearning: priorCount,
                anomalyScore: 0,
                deviations: [],
                wasEligibleForLearning: true
            )
        }

        var deviations: [AdaptiveFeatureDeviation] = []
        for (key, value) in features {
            guard let statistic = statistics[key],
                  statistic.count >= Self.minimumOutlierScreeningSamples else {
                continue
            }
            let scale = max(statistic.standardDeviation, Self.minimumScale(for: key))
            let z = (value - statistic.mean) / scale
            guard abs(z) >= 3.0 else { continue }
            deviations.append(AdaptiveFeatureDeviation(
                feature: key,
                standardDeviations: abs(z),
                direction: z > 0 ? "higher" : "lower"
            ))
        }
        deviations.sort { $0.standardDeviations > $1.standardDeviations }
        let strongest = deviations.prefix(3).map { min($0.standardDeviations, 6) }
        let score = strongest.isEmpty
            ? 0
            : min(1, strongest.reduce(0, +) / (Double(strongest.count) * 5.0))
        return AdaptiveCopyAnalysis(
            sampleCountBeforeLearning: priorCount,
            anomalyScore: score,
            deviations: Array(deviations.prefix(5)),
            wasEligibleForLearning: true
        )
    }

    private func winsorized(_ value: Double, using statistic: RunningStatistic) -> Double {
        guard statistic.count >= Self.minimumOutlierScreeningSamples else { return value }
        let scale = max(statistic.standardDeviation, 0.000_1)
        return min(max(value, statistic.mean - (4 * scale)), statistic.mean + (4 * scale))
    }

    private static func minimumScale(for key: String) -> Double {
        switch key {
        case "length": 0.12
        case "average word length": 0.22
        case "lexical diversity", "sentence cadence": 0.045
        default: 0.012
        }
    }

    private static func ratio(
        in characters: [Character],
        where predicate: (Character) -> Bool
    ) -> Double {
        Double(characters.filter(predicate).count) / Double(max(1, characters.count))
    }

    private static func coefficientOfVariation(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance) / mean
    }

    private static func urlCount(in text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter {
            $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://")
        }.count
    }

    fileprivate var hasValidPersistentState: Bool {
        guard schemaVersion == Self.currentSchemaVersion,
              sampleCount >= 0,
              sampleCount <= 1_000_000,
              statistics.count <= Self.expectedFeatureKeys.count,
              Set(statistics.keys).isSubset(of: Self.expectedFeatureKeys) else {
            return false
        }
        if sampleCount == 0 { return statistics.isEmpty }
        return statistics.count == Self.expectedFeatureKeys.count
            && statistics.values.allSatisfy {
                $0.count == sampleCount && $0.hasValidPersistentState
            }
    }

    private static let expectedFeatureKeys: Set<String> = [
        "length",
        "average word length",
        "lexical diversity",
        "sentence cadence",
        "uppercase ratio",
        "digit ratio",
        "punctuation ratio",
        "line-break ratio",
        "non-ASCII ratio",
        "URL density"
    ]
}

private struct RunningStatistic: Codable, Sendable, Equatable {
    private(set) var count = 0
    private(set) var mean = 0.0
    private(set) var squaredDifferenceSum = 0.0

    var standardDeviation: Double {
        guard count >= 2 else { return 0 }
        return sqrt(squaredDifferenceSum / Double(count - 1))
    }

    mutating func add(_ value: Double) {
        count += 1
        let delta = value - mean
        mean += delta / Double(count)
        let nextDelta = value - mean
        squaredDifferenceSum += delta * nextDelta
    }

    var hasValidPersistentState: Bool {
        count >= 0
            && mean.isFinite
            && squaredDifferenceSum.isFinite
            && squaredDifferenceSum >= 0
    }
}

public enum AdaptiveCopyModelStoreError: Error, LocalizedError, Equatable {
    case invalidFileType
    case fileTooLarge(maximumBytes: Int)
    case invalidModel

    public var errorDescription: String? {
        switch self {
        case .invalidFileType:
            "The Personal Baseline file is not a regular file."
        case .fileTooLarge(let maximumBytes):
            "The Personal Baseline file exceeds the \(maximumBytes)-byte safety limit."
        case .invalidModel:
            "The Personal Baseline file contains invalid aggregate state."
        }
    }
}

/// Deterministic findings and statistical outliers are never admitted into
/// the baseline. This prevents a suspicious copy from teaching the detector
/// that the suspicious structure is normal.
public enum AdaptiveCopyLearningPolicy {
    public static func allowsLearning(from analysis: ClipboardProtectionAnalysis) -> Bool {
        analysis.limitation == nil
            && !analysis.containsHiddenUnicode
            && !analysis.containsCodeRisk
            && !analysis.containsBinaryContent
            && !analysis.containsTrackedLinks
            && !analysis.containsOpaqueIdentifiers
            && !analysis.containsPotentialScam
            && !analysis.containsRecentPattern
    }
}

public enum AdaptiveCopyModelStore {
    public static func load(from url: URL) throws -> AdaptiveCopyModel {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AdaptiveCopyModel()
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw AdaptiveCopyModelStoreError.invalidFileType
        }
        guard (values.fileSize ?? 0) <= TextAnalysisBudget.maximumAdaptiveModelFileBytes else {
            throw AdaptiveCopyModelStoreError.fileTooLarge(
                maximumBytes: TextAnalysisBudget.maximumAdaptiveModelFileBytes
            )
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(
            upToCount: TextAnalysisBudget.maximumAdaptiveModelFileBytes + 1
        ) ?? Data()
        guard data.count <= TextAnalysisBudget.maximumAdaptiveModelFileBytes else {
            throw AdaptiveCopyModelStoreError.fileTooLarge(
                maximumBytes: TextAnalysisBudget.maximumAdaptiveModelFileBytes
            )
        }
        let model = try JSONDecoder().decode(AdaptiveCopyModel.self, from: data)
        guard model.schemaVersion == AdaptiveCopyModel.currentSchemaVersion else {
            return AdaptiveCopyModel()
        }
        guard model.hasValidPersistentState else {
            throw AdaptiveCopyModelStoreError.invalidModel
        }
        return model
    }

    public static func save(_ model: AdaptiveCopyModel, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard model.hasValidPersistentState else {
            throw AdaptiveCopyModelStoreError.invalidModel
        }
        let data = try encoder.encode(model)
        guard data.count <= TextAnalysisBudget.maximumAdaptiveModelFileBytes else {
            throw AdaptiveCopyModelStoreError.fileTooLarge(
                maximumBytes: TextAnalysisBudget.maximumAdaptiveModelFileBytes
            )
        }
        try data.write(to: url, options: [.atomic])
    }
}
