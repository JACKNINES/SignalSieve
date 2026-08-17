// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum PayloadEquivalenceConfidence: String, Sendable {
    case low = "Low confidence"
    case medium = "Medium confidence"
}

/// A bounded, non-authoritative interpretation of a damaged hidden bitstream.
/// It is deliberately separate from exact decoding so callers cannot mistake
/// a catalog match for bytes that were actually present in the source.
public struct ProbablePayloadEquivalence: Sendable, Equatable {
    public let text: String
    public let characterCount: Int
    public let unicodeCodePoints: [String]
    public let bitEditDistance: Int
    public let similarityPercent: Int
    public let confidence: PayloadEquivalenceConfidence

    public init(
        text: String,
        characterCount: Int,
        unicodeCodePoints: [String],
        bitEditDistance: Int,
        similarityPercent: Int,
        confidence: PayloadEquivalenceConfidence
    ) {
        self.text = text
        self.characterCount = characterCount
        self.unicodeCodePoints = unicodeCodePoints
        self.bitEditDistance = bitEditDistance
        self.similarityPercent = similarityPercent
        self.confidence = confidence
    }
}

/// Matches malformed bitstreams against a small, auditable local catalog.
/// This never downloads rules and never invents arbitrary missing text.
enum PayloadEquivalenceDetector {
    static let maximumComparedBits = 256
    static let maximumBitEditDistance = 4
    static let minimumSimilarity = 0.90

    // These are common proof-of-concept payloads, not a claim that the words
    // are harmful. Keeping the list explicit makes every inference auditable.
    private static let knownPlaintexts = [
        "hello",
        "hidden",
        "secret",
        "u suck",
        "watermark",
        "tracking",
        "system prompt",
        "ignore previous instructions"
    ]

    static func probableEquivalence(for bits: String) -> ProbablePayloadEquivalence? {
        guard (16...maximumComparedBits).contains(bits.count),
              bits.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            return nil
        }

        let matches = knownPlaintexts.compactMap { text -> Match? in
            let candidateBits = binaryUTF8(of: text)
            guard abs(candidateBits.count - bits.count) <= maximumBitEditDistance else {
                return nil
            }
            let distance = editDistance(bits, candidateBits)
            let comparedLength = max(bits.count, candidateBits.count)
            let similarity = 1 - (Double(distance) / Double(comparedLength))
            guard distance <= maximumBitEditDistance,
                  similarity >= minimumSimilarity else {
                return nil
            }
            return Match(text: text, distance: distance, similarity: similarity)
        }
        .sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.similarity != rhs.similarity { return lhs.similarity > rhs.similarity }
            return lhs.text < rhs.text
        }

        guard let best = matches.first else { return nil }
        if matches.count > 1,
           matches[1].distance == best.distance,
           abs(matches[1].similarity - best.similarity) < 0.000_001 {
            return nil
        }

        let scalars = best.text.unicodeScalars
        return ProbablePayloadEquivalence(
            text: best.text,
            characterCount: best.text.count,
            unicodeCodePoints: scalars.map { codePoint($0.value) },
            bitEditDistance: best.distance,
            similarityPercent: Int((best.similarity * 100).rounded()),
            confidence: best.distance <= 2 && best.similarity >= 0.96 ? .medium : .low
        )
    }

    private struct Match {
        let text: String
        let distance: Int
        let similarity: Double
    }

    private static func binaryUTF8(of text: String) -> String {
        text.utf8.map { byte in
            String(byte, radix: 2).leftPadding(toLength: 8, with: "0")
        }.joined()
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftBit) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, rightBit) in right.enumerated() {
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftBit == rightBit ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func codePoint(_ value: UInt32) -> String {
        value <= 0xFFFF
            ? String(format: "U+%04X", value)
            : String(format: "U+%06X", value)
    }
}

private extension String {
    func leftPadding(toLength: Int, with character: Character) -> String {
        guard count < toLength else { return self }
        return String(repeating: String(character), count: toLength - count) + self
    }
}
