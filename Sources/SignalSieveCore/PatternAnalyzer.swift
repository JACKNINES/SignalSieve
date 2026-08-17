// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum PatternFindingKind: String, Sendable, Equatable {
    case repeatedPhrase = "Repeated phrase"
    case repeatedOpening = "Repeated sentence opening"
    case repeatedListStructure = "Repeated list structure"
    case repeatedPunctuation = "Repeated punctuation pattern"
}

public struct PatternFinding: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: PatternFindingKind
    public let pattern: String
    public let detail: String
    public let matchingSampleCount: Int
    public let confidence: Double
    public var evidenceConfidence: EvidenceConfidence { .heuristic }

    public init(
        kind: PatternFindingKind,
        pattern: String,
        detail: String,
        matchingSampleCount: Int,
        confidence: Double
    ) {
        self.id = "\(kind.rawValue):\(pattern)"
        self.kind = kind
        self.pattern = pattern
        self.detail = detail
        self.matchingSampleCount = matchingSampleCount
        self.confidence = min(max(confidence, 0), 1)
    }
}

public struct PatternReport: Sendable, Equatable {
    public let sampleCount: Int
    public let findings: [PatternFinding]

    public var hasSuspiciousRepetition: Bool { !findings.isEmpty }

    public init(sampleCount: Int, findings: [PatternFinding]) {
        self.sampleCount = sampleCount
        self.findings = findings
    }
}

public enum PatternAnalyzer {
    private static let wordExpression = try? NSRegularExpression(
        pattern: #"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*"#
    )

    private static let overlyCommonPhrases: Set<String> = [
        "as a result",
        "at the same",
        "in order to",
        "one of the",
        "the fact that",
        "there is a",
        "this is a"
    ]

    /// Compares recent texts without trying to attribute them to a person or
    /// model. The report describes correlation, never proof of authorship.
    public static func analyze(_ texts: [String]) -> PatternReport {
        let usableTexts = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard usableTexts.count >= 2 else {
            return PatternReport(sampleCount: usableTexts.count, findings: [])
        }

        let tokenized = usableTexts.map(tokens)
        var findings = repeatedPhraseFindings(tokenized)
        findings.append(contentsOf: repeatedOpeningFindings(in: usableTexts))
        findings.append(contentsOf: repeatedStructureFindings(in: usableTexts))

        findings.sort {
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            return $0.matchingSampleCount > $1.matchingSampleCount
        }

        return PatternReport(
            sampleCount: usableTexts.count,
            findings: Array(findings.prefix(12))
        )
    }

    private static func repeatedPhraseFindings(_ samples: [[String]]) -> [PatternFinding] {
        var sampleIndexesByPhrase: [String: Set<Int>] = [:]

        for (sampleIndex, words) in samples.enumerated() {
            guard words.count >= 3 else { continue }
            var phrasesInSample: Set<String> = []

            for length in 3...min(6, words.count) {
                for start in 0...(words.count - length) {
                    let phrase = words[start..<(start + length)].joined(separator: " ")
                    if phrase.count >= 13 && !overlyCommonPhrases.contains(phrase) {
                        phrasesInSample.insert(phrase)
                    }
                }
            }

            for phrase in phrasesInSample {
                sampleIndexesByPhrase[phrase, default: []].insert(sampleIndex)
            }
        }

        let candidates = sampleIndexesByPhrase
            .filter { $0.value.count >= 2 }
            .map { (phrase: $0.key, indexes: $0.value) }
            .sorted {
                let leftWords = $0.phrase.split(separator: " ").count
                let rightWords = $1.phrase.split(separator: " ").count
                if leftWords != rightWords { return leftWords > rightWords }
                if $0.indexes.count != $1.indexes.count { return $0.indexes.count > $1.indexes.count }
                return $0.phrase < $1.phrase
            }

        var selected: [(phrase: String, indexes: Set<Int>)] = []
        for candidate in candidates {
            let isContained = selected.contains { existing in
                existing.indexes == candidate.indexes && existing.phrase.contains(candidate.phrase)
            }
            if !isContained {
                selected.append(candidate)
            }
            if selected.count == 8 { break }
        }

        return selected.map { candidate in
            let wordCount = candidate.phrase.split(separator: " ").count
            let coverage = Double(candidate.indexes.count) / Double(samples.count)
            let confidence = min(0.96, 0.48 + (Double(wordCount) * 0.065) + (coverage * 0.22))
            return PatternFinding(
                kind: .repeatedPhrase,
                pattern: candidate.phrase,
                detail: "The same \(wordCount)-word sequence appears in \(candidate.indexes.count) recent texts.",
                matchingSampleCount: candidate.indexes.count,
                confidence: confidence
            )
        }
    }

    private static func repeatedOpeningFindings(in texts: [String]) -> [PatternFinding] {
        var samplesByOpening: [String: Set<Int>] = [:]

        for (sampleIndex, text) in texts.enumerated() {
            let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            var openingsInSample: Set<String> = []
            for sentence in sentences {
                let sentenceTokens = tokens(sentence)
                guard sentenceTokens.count >= 4 else { continue }
                openingsInSample.insert(sentenceTokens.prefix(3).joined(separator: " "))
            }
            for opening in openingsInSample where !overlyCommonPhrases.contains(opening) {
                samplesByOpening[opening, default: []].insert(sampleIndex)
            }
        }

        return samplesByOpening
            .filter { $0.value.count >= 2 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(3)
            .map { opening, indexes in
                PatternFinding(
                    kind: .repeatedOpening,
                    pattern: opening,
                    detail: "Multiple sentences begin with this sequence across \(indexes.count) texts.",
                    matchingSampleCount: indexes.count,
                    confidence: min(0.88, 0.58 + (Double(indexes.count) * 0.08))
                )
            }
    }

    private static func repeatedStructureFindings(in texts: [String]) -> [PatternFinding] {
        var findings: [PatternFinding] = []
        let bulletCounts = texts.map { text in
            text.components(separatedBy: .newlines).filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil
            }.count
        }
        let samplesWithLists = bulletCounts.filter { $0 >= 3 }.count
        if samplesWithLists >= 2 {
            findings.append(
                PatternFinding(
                    kind: .repeatedListStructure,
                    pattern: "Three or more list items",
                    detail: "\(samplesWithLists) recent texts use the same multi-item list structure.",
                    matchingSampleCount: samplesWithLists,
                    confidence: min(0.84, 0.56 + (Double(samplesWithLists) * 0.08))
                )
            )
        }

        let emDashSamples = texts.filter { $0.contains("—") }.count
        if emDashSamples >= 3 {
            findings.append(
                PatternFinding(
                    kind: .repeatedPunctuation,
                    pattern: "Em dash (—)",
                    detail: "This punctuation choice appears in \(emDashSamples) recent texts.",
                    matchingSampleCount: emDashSamples,
                    confidence: min(0.72, 0.44 + (Double(emDashSamples) * 0.06))
                )
            )
        }
        return findings
    }

    private static func tokens(_ text: String) -> [String] {
        guard let wordExpression else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return wordExpression.matches(in: text, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange]).lowercased()
        }
    }
}
