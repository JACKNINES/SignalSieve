// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct SignalSieveIgnore: Sendable, Equatable {
    public static let fileName = ".signalsieveignore"
    public let patterns: [String]

    public init(patterns: [String]) {
        self.patterns = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    public static func load(from rootURL: URL) -> SignalSieveIgnore {
        let url = rootURL.appendingPathComponent(fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return SignalSieveIgnore(patterns: [])
        }
        return SignalSieveIgnore(patterns: text.components(separatedBy: .newlines))
    }

    public func ignores(_ relativePath: String, isDirectory: Bool) -> Bool {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        return patterns.contains { pattern in
            matches(pattern: pattern, path: normalized, isDirectory: isDirectory)
        }
    }

    private func matches(pattern rawPattern: String, path: String, isDirectory: Bool) -> Bool {
        var pattern = rawPattern
        let directoryOnly = pattern.hasSuffix("/")
        if directoryOnly { pattern.removeLast() }
        guard !directoryOnly || isDirectory else { return false }

        let anchored = pattern.hasPrefix("/")
        if anchored { pattern.removeFirst() }
        guard !pattern.isEmpty else { return false }

        let expression = Self.regularExpression(for: pattern, anchored: anchored)
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return expression?.firstMatch(in: path, range: range) != nil
    }

    private static func regularExpression(
        for pattern: String,
        anchored: Bool
    ) -> NSRegularExpression? {
        var regex = anchored ? "^" : "(?:^|/)"
        let characters = Array(pattern)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "*" {
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    regex += ".*"
                    index += 2
                } else {
                    regex += "[^/]*"
                    index += 1
                }
            } else if character == "?" {
                regex += "[^/]"
                index += 1
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(character))
                index += 1
            }
        }
        regex += "(?:$|/)"
        return try? NSRegularExpression(pattern: regex)
    }
}
