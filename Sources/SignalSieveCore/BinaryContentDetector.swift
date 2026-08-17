// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum BinaryContentKind: String, Sendable, CaseIterable {
    case rawBinary = "Binary data"
    case base64 = "Base64-encoded data"
    case hexadecimal = "Hexadecimal data"
    case binaryDigits = "Binary digit stream"
    case byteEscapes = "Escaped byte sequence"
}

public struct BinaryContentAnalysis: Sendable, Equatable {
    public let kind: BinaryContentKind?
    public let confidence: CodeLanguageConfidence
    public let byteCount: Int
    public let evidence: String

    public init(
        kind: BinaryContentKind?,
        confidence: CodeLanguageConfidence = .none,
        byteCount: Int = 0,
        evidence: String = ""
    ) {
        self.kind = kind
        self.confidence = confidence
        self.byteCount = byteCount
        self.evidence = evidence
    }

    public var isDetected: Bool { kind != nil }
    public var displayName: String { kind?.rawValue ?? "Not binary data" }
}

public enum BinaryContentDetector {
    public static func analyze(_ text: String) -> BinaryContentAnalysis {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return BinaryContentAnalysis(kind: nil) }

        let raw = Data(text.utf8)
        let rawAnalysis = analyze(raw)
        if rawAnalysis.isDetected { return rawAnalysis }

        if let count = escapedByteCount(in: trimmed), count >= 4 {
            return BinaryContentAnalysis(
                kind: .byteEscapes,
                confidence: count >= 8 ? .high : .medium,
                byteCount: count,
                evidence: "Repeated byte escape tokens"
            )
        }

        let compact = trimmed.filter { !$0.isWhitespace }
        if compact.count >= 32,
           compact.count.isMultiple(of: 8),
           compact.allSatisfy({ $0 == "0" || $0 == "1" }) {
            return BinaryContentAnalysis(
                kind: .binaryDigits,
                confidence: compact.count >= 64 ? .high : .medium,
                byteCount: compact.count / 8,
                evidence: "A stream containing only complete 8-bit groups"
            )
        }

        if let count = hexadecimalByteCount(in: trimmed), count >= 8 {
            return BinaryContentAnalysis(
                kind: .hexadecimal,
                confidence: count >= 16 ? .high : .medium,
                byteCount: count,
                evidence: "A sequence of hexadecimal byte values"
            )
        }

        if let decoded = base64Payload(from: trimmed) {
            return BinaryContentAnalysis(
                kind: .base64,
                confidence: decoded.count >= 32 ? .high : .medium,
                byteCount: decoded.count,
                evidence: "A structurally valid Base64 payload"
            )
        }

        return BinaryContentAnalysis(kind: nil)
    }

    public static func analyze(_ data: Data) -> BinaryContentAnalysis {
        guard !data.isEmpty else { return BinaryContentAnalysis(kind: nil) }

        if let signature = knownSignature(in: data) {
            return BinaryContentAnalysis(
                kind: .rawBinary,
                confidence: .high,
                byteCount: data.count,
                evidence: signature
            )
        }

        let sample = data.prefix(8_192)
        let nulCount = sample.filter { $0 == 0 }.count
        let suspiciousControlCount = sample.filter { byte in
            byte < 0x09 || (byte > 0x0D && byte < 0x20)
        }.count
        let ratio = Double(suspiciousControlCount) / Double(max(sample.count, 1))
        if nulCount > 0 || ratio > 0.08 || String(data: data, encoding: .utf8) == nil {
            return BinaryContentAnalysis(
                kind: .rawBinary,
                confidence: nulCount > 0 || ratio > 0.20 ? .high : .medium,
                byteCount: data.count,
                evidence: nulCount > 0
                    ? "Contains null bytes"
                    : "Byte distribution is not valid plain UTF-8 text"
            )
        }

        return BinaryContentAnalysis(kind: nil)
    }

    private static func knownSignature(in data: Data) -> String? {
        let bytes = Array(data.prefix(8))
        let signatures: [([UInt8], String)] = [
            ([0x7F, 0x45, 0x4C, 0x46], "ELF executable signature"),
            ([0x4D, 0x5A], "Windows executable signature"),
            ([0xCF, 0xFA, 0xED, 0xFE], "Mach-O executable signature"),
            ([0xCA, 0xFE, 0xBA, 0xBE], "Mach-O universal binary signature"),
            ([0x50, 0x4B, 0x03, 0x04], "ZIP container signature"),
            ([0x1F, 0x8B], "Gzip signature"),
            ([0x89, 0x50, 0x4E, 0x47], "PNG image signature"),
            ([0xFF, 0xD8, 0xFF], "JPEG image signature"),
            ([0x25, 0x50, 0x44, 0x46], "PDF signature")
        ]
        return signatures.first { signature, _ in
            bytes.count >= signature.count && Array(bytes.prefix(signature.count)) == signature
        }?.1
    }

    private static func escapedByteCount(in text: String) -> Int? {
        let pattern = #"(?:\\x[0-9A-Fa-f]{2}|\\u\{[0-9A-Fa-f]{2}\}|0x[0-9A-Fa-f]{2})(?:[\s,]+(?:\\x[0-9A-Fa-f]{2}|\\u\{[0-9A-Fa-f]{2}\}|0x[0-9A-Fa-f]{2})){3,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let matched = (text as NSString).substring(with: match.range)
        let tokenPattern = #"(?:\\x[0-9A-Fa-f]{2}|\\u\{[0-9A-Fa-f]{2}\}|0x[0-9A-Fa-f]{2})"#
        let tokenRegex = try? NSRegularExpression(pattern: tokenPattern)
        return tokenRegex?.numberOfMatches(
            in: matched,
            range: NSRange(location: 0, length: (matched as NSString).length)
        )
    }

    private static func hexadecimalByteCount(in text: String) -> Int? {
        let compact = text
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .filter { !$0.isWhitespace && $0 != ":" && $0 != "-" && $0 != "," }
        guard compact.count >= 16,
              compact.count.isMultiple(of: 2),
              compact.allSatisfy({ $0.isHexDigit }) else { return nil }
        return compact.count / 2
    }

    private static func base64Payload(from text: String) -> Data? {
        let payload: String
        if text.lowercased().hasPrefix("data:"), let comma = text.firstIndex(of: ",") {
            let header = text[..<comma].lowercased()
            guard header.contains(";base64") else { return nil }
            payload = String(text[text.index(after: comma)...])
        } else {
            payload = text
        }

        let compact = payload.filter { !$0.isWhitespace }
        guard compact.count >= 24,
              compact.count.isMultiple(of: 4),
              compact.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }),
              compact.contains("=") || compact.count >= 40,
              Set(compact).count >= 8 else { return nil }
        return Data(base64Encoded: compact, options: [])
    }
}
