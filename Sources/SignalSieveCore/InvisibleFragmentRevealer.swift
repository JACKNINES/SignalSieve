// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum RevealedFragmentPresentation: String, Sendable {
    case decodedPayload = "Decoded hidden fragment"
    case binaryPayload = "Opaque binary payload"
    case incompletePayload = "Incomplete hidden payload"
    case visibleContext = "Visible source fragment"
}

public struct ZeroWidthBinaryDetails: Sendable, Equatable {
    public let zeroCodePoint: String
    public let oneCodePoint: String
    public let bits: String
    public let completeByteCount: Int
    public let trailingBitCount: Int
    public let isPreviewTruncated: Bool
    public let probableTextEquivalence: ProbablePayloadEquivalence?

    public var isByteAligned: Bool { trailingBitCount == 0 }
    public var missingBitCount: Int { isByteAligned ? 0 : 8 - trailingBitCount }

    public init(
        zeroCodePoint: String,
        oneCodePoint: String,
        bits: String,
        completeByteCount: Int,
        trailingBitCount: Int,
        isPreviewTruncated: Bool,
        probableTextEquivalence: ProbablePayloadEquivalence? = nil
    ) {
        self.zeroCodePoint = zeroCodePoint
        self.oneCodePoint = oneCodePoint
        self.bits = bits
        self.completeByteCount = completeByteCount
        self.trailingBitCount = trailingBitCount
        self.isPreviewTruncated = isPreviewTruncated
        self.probableTextEquivalence = probableTextEquivalence
    }
}

public struct RevealedInvisibleFragment: Identifiable, Sendable, Equatable {
    public let id: Int
    public let findingNumber: Int
    public let codePoint: String
    public let line: Int
    public let column: Int
    public let presentation: RevealedFragmentPresentation
    public let text: String
    public let hiddenScalarCount: Int
    public let scalarPositions: [Int]
    public let zeroWidthBinary: ZeroWidthBinaryDetails?

    public init(
        id: Int,
        findingNumber: Int,
        codePoint: String,
        line: Int,
        column: Int,
        presentation: RevealedFragmentPresentation,
        text: String,
        hiddenScalarCount: Int,
        scalarPositions: [Int],
        zeroWidthBinary: ZeroWidthBinaryDetails? = nil
    ) {
        self.id = id
        self.findingNumber = findingNumber
        self.codePoint = codePoint
        self.line = line
        self.column = column
        self.presentation = presentation
        self.text = text
        self.hiddenScalarCount = hiddenScalarCount
        self.scalarPositions = scalarPositions
        self.zeroWidthBinary = zeroWidthBinary
    }
}

/// Makes invisible findings reviewable without evaluating or executing their
/// contents. Known encodings are decoded only into a bounded display string.
public enum InvisibleFragmentRevealer {
    public static let maximumPreviewCharacters = 180
    public static let maximumPreviewsPerFile = 5
    public static let maximumBinaryPreviewBits = 512

    private struct LocatedScalar {
        let scalar: Unicode.Scalar
        let position: Int
        let line: Int
        let column: Int
    }

    public static func reveal(in text: String) -> [RevealedInvisibleFragment] {
        let located = locatedScalars(in: text)
        let inspection = HiddenTextAnalyzer.inspect(text)
        let findings = inspection.actionableFindings
        guard !findings.isEmpty else { return [] }

        let findingByPosition = Dictionary(
            uniqueKeysWithValues: findings.enumerated().map { index, finding in
                (finding.scalarPosition, (number: index + 1, finding: finding))
            }
        )
        var previews: [RevealedInvisibleFragment] = []
        var coveredPositions: Set<Int> = []

        appendTagPayloads(
            from: located,
            findingByPosition: findingByPosition,
            previews: &previews,
            coveredPositions: &coveredPositions
        )
        appendVariationSelectorPayloads(
            from: located,
            findingByPosition: findingByPosition,
            previews: &previews,
            coveredPositions: &coveredPositions
        )
        appendZeroWidthPayloads(
            from: located,
            findingByPosition: findingByPosition,
            previews: &previews,
            coveredPositions: &coveredPositions
        )

        for (index, finding) in findings.enumerated()
        where previews.count < maximumPreviewsPerFile
                && !coveredPositions.contains(finding.scalarPosition) {
            guard let location = located.first(where: { $0.position == finding.scalarPosition }) else {
                continue
            }
            previews.append(
                RevealedInvisibleFragment(
                    id: previews.count,
                    findingNumber: index + 1,
                    codePoint: finding.codePoint,
                    line: location.line,
                    column: location.column,
                    presentation: .visibleContext,
                    text: visibleContext(in: text, line: location.line, column: location.column),
                    hiddenScalarCount: 1,
                    scalarPositions: [finding.scalarPosition]
                )
            )
        }

        return Array(previews.prefix(maximumPreviewsPerFile)).enumerated().map { index, preview in
            RevealedInvisibleFragment(
                id: index,
                findingNumber: preview.findingNumber,
                codePoint: preview.codePoint,
                line: preview.line,
                column: preview.column,
                presentation: preview.presentation,
                text: preview.text,
                hiddenScalarCount: preview.hiddenScalarCount,
                scalarPositions: preview.scalarPositions,
                zeroWidthBinary: preview.zeroWidthBinary
            )
        }
    }

    private static func appendTagPayloads(
        from located: [LocatedScalar],
        findingByPosition: [Int: (number: Int, finding: HiddenElement)],
        previews: inout [RevealedInvisibleFragment],
        coveredPositions: inout Set<Int>
    ) {
        appendDecodedRuns(
            from: located,
            matching: { (0xE0000...0xE007F).contains($0.value) },
            decode: { run in
                let bytes = run.compactMap { item -> UInt8? in
                    guard (0xE0020...0xE007E).contains(item.scalar.value) else { return nil }
                    return UInt8(item.scalar.value - 0xE0000)
                }
                guard bytes.count >= 2 else { return nil }
                return displayableText(from: bytes)
            },
            findingByPosition: findingByPosition,
            previews: &previews,
            coveredPositions: &coveredPositions
        )
    }

    private static func appendVariationSelectorPayloads(
        from located: [LocatedScalar],
        findingByPosition: [Int: (number: Int, finding: HiddenElement)],
        previews: inout [RevealedInvisibleFragment],
        coveredPositions: inout Set<Int>
    ) {
        appendDecodedRuns(
            from: located,
            matching: { isVariationSelector($0.value) },
            decode: { run in
                guard run.count >= 2 else { return nil }
                let directBytes = run.map { variationSelectorByte($0.scalar.value) }
                if let direct = displayableText(from: directBytes) {
                    return direct
                }

                guard run.count >= 4,
                      run.count.isMultiple(of: 2),
                      run.allSatisfy({ (0xFE00...0xFE0F).contains($0.scalar.value) }) else {
                    return nil
                }
                var nibbleBytes: [UInt8] = []
                var index = 0
                while index < run.count {
                    let high = UInt8(run[index].scalar.value - 0xFE00)
                    let low = UInt8(run[index + 1].scalar.value - 0xFE00)
                    nibbleBytes.append((high << 4) | low)
                    index += 2
                }
                return displayableText(from: nibbleBytes)
            },
            findingByPosition: findingByPosition,
            previews: &previews,
            coveredPositions: &coveredPositions
        )
    }

    private static func appendZeroWidthPayloads(
        from located: [LocatedScalar],
        findingByPosition: [Int: (number: Int, finding: HiddenElement)],
        previews: inout [RevealedInvisibleFragment],
        coveredPositions: inout Set<Int>
    ) {
        let pairs: [(zero: UInt32, one: UInt32)] = [
            (0x200B, 0x200C), (0x200C, 0x200B),
            (0x200C, 0x200D), (0x200D, 0x200C)
        ]
        var index = 0
        while index < located.count, previews.count < maximumPreviewsPerFile {
            guard [0x200B, 0x200C, 0x200D].contains(located[index].scalar.value) else {
                index += 1
                continue
            }

            let start = index
            while index < located.count,
                  [0x200B, 0x200C, 0x200D].contains(located[index].scalar.value) {
                index += 1
            }
            let run = Array(located[start..<index])
            let uniqueValues = Set(run.map(\.scalar.value))
            guard run.count >= 16,
                  uniqueValues.count == 2,
                  let first = run.first,
                  let sourceFinding = findingByPosition[first.position] else {
                continue
            }

            let compatibleMappings = pairs.filter { pair in
                run.allSatisfy { item in
                    item.scalar.value == pair.zero || item.scalar.value == pair.one
                }
            }
            guard let defaultMapping = compatibleMappings.first else { continue }

            var selectedMapping = defaultMapping
            var selectedBits = binaryBits(in: run, zero: defaultMapping.zero, one: defaultMapping.one)
            var decodedText: String?

            if run.count.isMultiple(of: 8) {
                for mapping in compatibleMappings {
                    let bits = binaryBits(in: run, zero: mapping.zero, one: mapping.one)
                    if let decoded = displayableText(from: bytes(from: bits)) {
                        selectedMapping = mapping
                        selectedBits = bits
                        decodedText = decoded
                        break
                    }
                }
            }

            let trailingBitCount = run.count % 8
            let presentation: RevealedFragmentPresentation
            let text: String
            if let decodedText {
                presentation = .decodedPayload
                text = decodedText
            } else if trailingBitCount == 0 {
                presentation = .binaryPayload
                text = bytes(from: selectedBits)
                    .prefix(32)
                    .map { String(format: "%02X", $0) }
                    .joined(separator: " ")
            } else {
                presentation = .incompletePayload
                text = String(selectedBits.prefix(maximumBinaryPreviewBits))
            }

            let bitPreview = String(selectedBits.prefix(maximumBinaryPreviewBits))
            previews.append(
                RevealedInvisibleFragment(
                    id: previews.count,
                    findingNumber: sourceFinding.number,
                    codePoint: sourceFinding.finding.codePoint,
                    line: first.line,
                    column: first.column,
                    presentation: presentation,
                    text: text,
                    hiddenScalarCount: run.count,
                    scalarPositions: run.map(\.position),
                    zeroWidthBinary: ZeroWidthBinaryDetails(
                        zeroCodePoint: codePoint(selectedMapping.zero),
                        oneCodePoint: codePoint(selectedMapping.one),
                        bits: bitPreview,
                        completeByteCount: run.count / 8,
                        trailingBitCount: trailingBitCount,
                        isPreviewTruncated: selectedBits.count > maximumBinaryPreviewBits,
                        probableTextEquivalence: decodedText == nil
                            ? PayloadEquivalenceDetector.probableEquivalence(for: selectedBits)
                            : nil
                    )
                )
            )
            coveredPositions.formUnion(run.map(\.position))
        }
    }

    private static func binaryBits(
        in run: [LocatedScalar],
        zero: UInt32,
        one: UInt32
    ) -> String {
        run.map { item in
            item.scalar.value == zero ? "0" : (item.scalar.value == one ? "1" : "")
        }.joined()
    }

    private static func bytes(from bits: String) -> [UInt8] {
        let characters = Array(bits)
        var result: [UInt8] = []
        for byteStart in stride(from: 0, through: characters.count - 8, by: 8) {
            var byte: UInt8 = 0
            for bitOffset in 0..<8 {
                byte <<= 1
                if characters[byteStart + bitOffset] == "1" { byte |= 1 }
            }
            result.append(byte)
        }
        return result
    }

    private static func appendDecodedRuns(
        from located: [LocatedScalar],
        matching: (Unicode.Scalar) -> Bool,
        decode: ([LocatedScalar]) -> String?,
        findingByPosition: [Int: (number: Int, finding: HiddenElement)],
        previews: inout [RevealedInvisibleFragment],
        coveredPositions: inout Set<Int>
    ) {
        var index = 0
        while index < located.count, previews.count < maximumPreviewsPerFile {
            guard matching(located[index].scalar) else {
                index += 1
                continue
            }
            let start = index
            while index < located.count, matching(located[index].scalar) { index += 1 }
            let run = Array(located[start..<index])
            guard let decoded = decode(run),
                  let first = run.first,
                  let sourceFinding = findingByPosition[first.position] else { continue }

            previews.append(
                RevealedInvisibleFragment(
                    id: previews.count,
                    findingNumber: sourceFinding.number,
                    codePoint: sourceFinding.finding.codePoint,
                    line: first.line,
                    column: first.column,
                    presentation: .decodedPayload,
                    text: decoded,
                    hiddenScalarCount: run.count,
                    scalarPositions: run.map(\.position)
                )
            )
            coveredPositions.formUnion(run.map(\.position))
        }
    }

    private static func locatedScalars(in text: String) -> [LocatedScalar] {
        var result: [LocatedScalar] = []
        var position = 1
        var line = 1
        var column = 1
        var previousWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            result.append(LocatedScalar(scalar: scalar, position: position, line: line, column: column))
            position += 1
            if scalar.value == 0x0D {
                line += 1
                column = 1
                previousWasCarriageReturn = true
            } else if scalar.value == 0x0A {
                if !previousWasCarriageReturn { line += 1 }
                column = 1
                previousWasCarriageReturn = false
            } else {
                column += 1
                previousWasCarriageReturn = false
            }
        }
        return result
    }

    private static func visibleContext(in text: String, line: Int, column: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard line > 0, line <= lines.count else { return "⟦invisible content⟧" }
        var scalars = Array(lines[line - 1].unicodeScalars)
        if scalars.last?.value == 0x0D { scalars.removeLast() }
        let target = max(0, min(scalars.count - 1, column - 1))
        let start = max(0, target - 45)
        let end = min(scalars.count, target + 46)
        let tokens = scalars[start..<end].map { scalar -> String in
            if HiddenTextAnalyzer.classify(scalar) != nil {
                return "⟦\(codePoint(scalar.value))⟧"
            }
            return String(scalar)
        }
        let context = (start > 0 ? "…" : "")
            + tokens.joined()
            + (end < scalars.count ? "…" : "")
        return bounded(context)
    }

    private static func displayableText(from bytes: [UInt8]) -> String? {
        guard let decoded = String(data: Data(bytes), encoding: .utf8) else { return nil }
        let scalars = decoded.unicodeScalars
        let visibleCount = scalars.filter { scalar in
            let category = scalar.properties.generalCategory
            return category != .control
                && category != .format
                && category != .privateUse
                && category != .unassigned
                || scalar.value == 0x09
                || scalar.value == 0x0A
                || scalar.value == 0x0D
        }.count
        guard scalars.count >= 2,
              visibleCount == scalars.count,
              decoded.contains(where: { !$0.isWhitespace }) else { return nil }

        let escaped = decoded
            .replacingOccurrences(of: "\r\n", with: " ↵ ")
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .replacingOccurrences(of: "\r", with: " ↵ ")
            .replacingOccurrences(of: "\t", with: " ⇥ ")
        return bounded(escaped)
    }

    private static func isVariationSelector(_ value: UInt32) -> Bool {
        (0xFE00...0xFE0F).contains(value) || (0xE0100...0xE01EF).contains(value)
    }

    private static func variationSelectorByte(_ value: UInt32) -> UInt8 {
        if (0xFE00...0xFE0F).contains(value) { return UInt8(value - 0xFE00) }
        return UInt8(value - 0xE0100 + 16)
    }

    private static func codePoint(_ value: UInt32) -> String {
        value <= 0xFFFF
            ? String(format: "U+%04X", value)
            : String(format: "U+%06X", value)
    }

    private static func bounded(_ text: String) -> String {
        if text.count <= maximumPreviewCharacters { return text }
        return String(text.prefix(maximumPreviewCharacters)) + "…"
    }
}
