// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum TextEncodingKind: String, Sendable, CaseIterable {
    case utf8 = "UTF-8"
    case utf16LittleEndian = "UTF-16 LE"
    case utf16BigEndian = "UTF-16 BE"
    case utf32LittleEndian = "UTF-32 LE"
    case utf32BigEndian = "UTF-32 BE"
}

public struct DecodedTextFile: Sendable, Equatable {
    public let text: String
    public let encoding: TextEncodingKind
    public let hasByteOrderMark: Bool

    public init(text: String, encoding: TextEncodingKind, hasByteOrderMark: Bool) {
        self.text = text
        self.encoding = encoding
        self.hasByteOrderMark = hasByteOrderMark
    }

    public func encodedData() -> Data? {
        TextEncodingDetector.encode(
            text,
            as: encoding,
            includeByteOrderMark: hasByteOrderMark
        )
    }
}

public enum TextEncodingDetector {
    public static func decode(_ data: Data) -> DecodedTextFile? {
        guard !data.isEmpty else {
            return DecodedTextFile(text: "", encoding: .utf8, hasByteOrderMark: false)
        }

        let bytes = Array(data.prefix(4))
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return decode(data.dropFirst(4), as: .utf32BigEndian, hadBOM: true)
        }
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return decode(data.dropFirst(4), as: .utf32LittleEndian, hadBOM: true)
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return decode(data.dropFirst(3), as: .utf8, hadBOM: true)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return decode(data.dropFirst(2), as: .utf16BigEndian, hadBOM: true)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return decode(data.dropFirst(2), as: .utf16LittleEndian, hadBOM: true)
        }

        for encoding in heuristicCandidates(for: data) {
            if let decoded = decode(data[...], as: encoding, hadBOM: false),
               isPlausibleText(decoded.text) {
                return decoded
            }
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return DecodedTextFile(text: utf8, encoding: .utf8, hasByteOrderMark: false)
        }
        return nil
    }

    public static func encode(
        _ text: String,
        as encoding: TextEncodingKind,
        includeByteOrderMark: Bool
    ) -> Data? {
        let stringEncoding = foundationEncoding(for: encoding)
        guard var data = text.data(using: stringEncoding, allowLossyConversion: false) else {
            return nil
        }
        guard includeByteOrderMark else { return data }

        var prefix = Data(byteOrderMark(for: encoding))
        prefix.append(data)
        data = prefix
        return data
    }

    private static func decode(
        _ data: Data.SubSequence,
        as encoding: TextEncodingKind,
        hadBOM: Bool
    ) -> DecodedTextFile? {
        guard let text = String(data: Data(data), encoding: foundationEncoding(for: encoding)) else {
            return nil
        }
        return DecodedTextFile(text: text, encoding: encoding, hasByteOrderMark: hadBOM)
    }

    private static func heuristicCandidates(for data: Data) -> [TextEncodingKind] {
        let sample = Array(data.prefix(4_096))
        guard sample.count >= 4 else { return [] }

        let quarterCounts = (0..<4).map { offset in
            stride(from: offset, to: sample.count, by: 4).filter { sample[$0] == 0 }.count
        }
        let quarterTotals = (0..<4).map { offset in
            Array(stride(from: offset, to: sample.count, by: 4)).count
        }
        let quarterRatios = zip(quarterCounts, quarterTotals).map {
            Double($0) / Double(max($1, 1))
        }
        if data.count.isMultiple(of: 4) {
            if quarterRatios[0] > 0.70, quarterRatios[1] > 0.70, quarterRatios[2] > 0.70 {
                return [.utf32BigEndian, .utf16BigEndian]
            }
            if quarterRatios[1] > 0.70, quarterRatios[2] > 0.70, quarterRatios[3] > 0.70 {
                return [.utf32LittleEndian, .utf16LittleEndian]
            }
        }

        let even = stride(from: 0, to: sample.count, by: 2).filter { sample[$0] == 0 }.count
        let odd = stride(from: 1, to: sample.count, by: 2).filter { sample[$0] == 0 }.count
        let pairs = max(sample.count / 2, 1)
        if Double(even) / Double(pairs) > 0.55 { return [.utf16BigEndian] }
        if Double(odd) / Double(pairs) > 0.55 { return [.utf16LittleEndian] }
        return []
    }

    private static func isPlausibleText(_ text: String) -> Bool {
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return false
        }
        let scalars = text.unicodeScalars
        let undesirable = scalars.filter { scalar in
            scalar.properties.generalCategory == .control
                && scalar.value != 0x09
                && scalar.value != 0x0A
                && scalar.value != 0x0D
        }.count
        return Double(undesirable) / Double(max(scalars.count, 1)) < 0.03
    }

    private static func foundationEncoding(for encoding: TextEncodingKind) -> String.Encoding {
        switch encoding {
        case .utf8: .utf8
        case .utf16LittleEndian: .utf16LittleEndian
        case .utf16BigEndian: .utf16BigEndian
        case .utf32LittleEndian: .utf32LittleEndian
        case .utf32BigEndian: .utf32BigEndian
        }
    }

    private static func byteOrderMark(for encoding: TextEncodingKind) -> [UInt8] {
        switch encoding {
        case .utf8: [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian: [0xFF, 0xFE]
        case .utf16BigEndian: [0xFE, 0xFF]
        case .utf32LittleEndian: [0xFF, 0xFE, 0x00, 0x00]
        case .utf32BigEndian: [0x00, 0x00, 0xFE, 0xFF]
        }
    }
}
