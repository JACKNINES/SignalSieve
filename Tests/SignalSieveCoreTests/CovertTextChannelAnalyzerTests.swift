// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Decodes a four-symbol zero-width alphabet")
func decodesBase4ZeroWidthChannel() {
    let report = CovertTextChannelAnalyzer.analyze("Visible\(base4Payload("Hi"))")
    let finding = report.findings.first { $0.kind == .zeroWidthBase4 }

    #expect(finding?.decodedPayload == "Hi")
    #expect(finding?.riskLevel == .high)
    #expect(finding?.carrierCount == 8)
}

@Test("Decodes a message carried by two visually blank space classes")
func decodesMixedSpaceAlphabet() {
    let text = spacePayload("OK")
    let finding = CovertTextChannelAnalyzer.analyze(text).findings.first {
        $0.kind == .mixedSpaceAlphabet
    }

    #expect(finding?.decodedPayload == "OK")
    #expect(finding?.riskLevel == .high)
}

@Test("Decodes a binary channel in trailing spaces and tabs")
func decodesTrailingWhitespaceChannel() {
    let text = trailingWhitespacePayload("OK")
    let finding = CovertTextChannelAnalyzer.analyze(text).findings.first {
        $0.kind == .trailingWhitespace
    }

    #expect(finding?.decodedPayload == "OK")
    #expect(finding?.carrierCount == 16)
    let cleaned = TextCleaner.clean(text, mode: .safe)
    #expect(!CovertTextChannelAnalyzer.analyze(cleaned.text).hasSuspiciousChannel)
    #expect(cleaned.removedCount == 16)
}

@Test("Does not flag ordinary prose, emoji composition, or indentation")
func rejectsOrdinaryTextAsCovertChannel() {
    let text = "A short ordinary paragraph with normal spaces.\n\tIndented text is not trailing data. 👨‍👩‍👧"
    #expect(CovertTextChannelAnalyzer.analyze(text).findings.isEmpty)
}

@Test("Reports recurring Cyrillic look-alikes in predominantly Latin text")
func reportsPeriodicConfusableChannel() {
    let text = "alpha pаttern beta pаttern gamma pаttern delta pаttern"
    let finding = CovertTextChannelAnalyzer.analyze(text).findings.first {
        $0.kind == .confusableSubstitution
    }
    #expect(finding != nil)
    #expect(finding?.riskLevel == .medium)
}

private func base4Payload(_ text: String) -> String {
    let alphabet: [UInt32] = [0x200B, 0x200C, 0x200D, 0x2060]
    var scalars: [Unicode.Scalar] = []
    for byte in text.utf8 {
        for shift in stride(from: 6, through: 0, by: -2) {
            let digit = Int((byte >> shift) & 0x03)
            if let scalar = Unicode.Scalar(alphabet[digit]) { scalars.append(scalar) }
        }
    }
    return String(String.UnicodeScalarView(scalars))
}

private func spacePayload(_ text: String) -> String {
    var result = "word"
    for byte in text.utf8 {
        for shift in stride(from: 7, through: 0, by: -1) {
            result.append(((byte >> shift) & 1) == 0 ? " " : "\u{2004}")
            result.append("word")
        }
    }
    return result
}

private func trailingWhitespacePayload(_ text: String) -> String {
    var lines: [String] = []
    for byte in text.utf8 {
        for shift in stride(from: 7, through: 0, by: -1) {
            lines.append("visible" + (((byte >> shift) & 1) == 0 ? " " : "\t"))
        }
    }
    return lines.joined(separator: "\n")
}
