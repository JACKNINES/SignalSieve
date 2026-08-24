// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum OpaqueIdentifierKind: String, Sendable, Codable, Equatable {
    case uuid = "UUID"
}

public struct OpaqueIdentifierFinding: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: OpaqueIdentifierKind
    public let value: String
    public let line: Int
    public let column: Int

    public init(kind: OpaqueIdentifierKind, value: String, line: Int, column: Int) {
        self.id = "\(kind.rawValue):\(line):\(column):\(value.lowercased())"
        self.kind = kind
        self.value = value
        self.line = line
        self.column = column
    }

    public var version: Int? {
        guard kind == .uuid,
              let nibble = value.split(separator: "-").dropFirst(2).first?.first,
              let value = Int(String(nibble), radix: 16),
              (1...8).contains(value) else {
            return nil
        }
        return value
    }

    /// Searches only for the identifier class; the UUID value is never sent.
    public var researchURL: URL? {
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "UUID opaque identifier privacy correlation security")
        ]
        return components?.url
    }
}

public struct OpaqueIdentifierAnalysis: Sendable, Equatable {
    public let findings: [OpaqueIdentifierFinding]

    public init(findings: [OpaqueIdentifierFinding]) {
        self.findings = findings
    }

    public var containsIdentifiers: Bool { !findings.isEmpty }
}

/// Finds opaque identifiers that may correlate copies across systems. A UUID
/// is not inherently malicious; the finding is a privacy review signal.
public enum OpaqueIdentifierAnalyzer {
    private static let uuidExpression = try? NSRegularExpression(
        pattern: #"(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])"#
    )

    public static func analyze(_ text: String) -> OpaqueIdentifierAnalysis {
        guard let uuidExpression, !text.isEmpty else {
            return OpaqueIdentifierAnalysis(findings: [])
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let findings: [OpaqueIdentifierFinding] = uuidExpression
            .matches(in: text, range: fullRange)
            .compactMap { match -> OpaqueIdentifierFinding? in
                guard let range: Range<String.Index> = Range(match.range, in: text) else { return nil }
                let location = lineAndColumn(in: text, at: range.lowerBound)
                return OpaqueIdentifierFinding(
                    kind: .uuid,
                    value: String(text[range]),
                    line: location.line,
                    column: location.column
                )
            }
        return OpaqueIdentifierAnalysis(findings: findings)
    }

    private static func lineAndColumn(
        in text: String,
        at index: String.Index
    ) -> (line: Int, column: Int) {
        let prefix = text[..<index]
        let line = prefix.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        let lastNewline = prefix.lastIndex(of: "\n")
        let columnStart = lastNewline.map { text.index(after: $0) } ?? text.startIndex
        return (line, text.distance(from: columnStart, to: index) + 1)
    }
}
