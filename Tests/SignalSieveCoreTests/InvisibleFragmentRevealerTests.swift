// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Reveals an ASCII message encoded with Unicode Tags")
func revealsUnicodeTagPayload() {
    let message = "Hola estoy oculto!"
    let source = "def run():\n    print('safe')\(unicodeTags(message))\n"
    let preview = InvisibleFragmentRevealer.reveal(in: source).first

    #expect(preview?.presentation == .decodedPayload)
    #expect(preview?.text == message)
    #expect(preview?.line == 2)
    #expect(preview?.hiddenScalarCount == message.unicodeScalars.count)
}

@Test("Reveals UTF-8 bytes encoded with variation selectors")
func revealsVariationSelectorPayload() {
    let message = "Hola estoy oculto!"
    let source = "const marker = true;\(variationSelectors(message))"
    let preview = InvisibleFragmentRevealer.reveal(in: source).first

    #expect(preview?.presentation == .decodedPayload)
    #expect(preview?.text == message)
}

@Test("Reveals a binary message encoded with zero-width characters")
func revealsZeroWidthPayload() {
    let message = "Hola"
    let source = "let marker = 1;\(zeroWidthBits(message))"
    let preview = InvisibleFragmentRevealer.reveal(in: source).first

    #expect(preview?.presentation == .decodedPayload)
    #expect(preview?.text == message)
}

@Test("Reveals a ZWNJ and ZWJ binary message")
func revealsJoinerBinaryPayload() {
    let message = "u suck"
    let source = "Acting normal\(zeroWidthJoinerBits(message)) 💀"
    let preview = InvisibleFragmentRevealer.reveal(in: source).first

    #expect(preview?.presentation == .decodedPayload)
    #expect(preview?.text == message)
    #expect(preview?.hiddenScalarCount == 48)
    #expect(preview?.zeroWidthBinary?.zeroCodePoint == "U+200C")
    #expect(preview?.zeroWidthBinary?.oneCodePoint == "U+200D")
    #expect(preview?.zeroWidthBinary?.isByteAligned == true)
}

@Test("Reports a truncated zero-width binary payload and labels catalog recovery")
func reportsIncompleteJoinerBinaryPayload() {
    let complete = zeroWidthJoinerBits("u suck")
    var truncatedScalars = Array(complete.unicodeScalars)
    truncatedScalars.removeLast()
    let truncated = String(String.UnicodeScalarView(truncatedScalars))
    let preview = InvisibleFragmentRevealer.reveal(in: "Visible\(truncated)").first

    #expect(preview?.presentation == .incompletePayload)
    #expect(preview?.hiddenScalarCount == 47)
    #expect(preview?.zeroWidthBinary?.completeByteCount == 5)
    #expect(preview?.zeroWidthBinary?.trailingBitCount == 7)
    #expect(preview?.zeroWidthBinary?.missingBitCount == 1)
    #expect(preview?.zeroWidthBinary?.probableTextEquivalence?.text == "u suck")
    #expect(preview?.zeroWidthBinary?.probableTextEquivalence?.bitEditDistance == 1)
    #expect(preview?.zeroWidthBinary?.probableTextEquivalence?.confidence == .medium)
}

@Test("Recovers the documented damaged joiner payload as a low-confidence equivalence")
func recoversDamagedJoinerPayloadEquivalence() {
    let bits = "11101000010000001110011011101001100001101101011"
    let source = "Acting like is worth sum is next level\(zeroWidthJoinerScalars(bits)) 💀"
    let preview = InvisibleFragmentRevealer.reveal(in: source).first
    let equivalence = preview?.zeroWidthBinary?.probableTextEquivalence

    #expect(preview?.presentation == .incompletePayload)
    #expect(preview?.line == 1)
    #expect(preview?.column == 39)
    #expect(preview?.hiddenScalarCount == 47)
    #expect(equivalence?.text == "u suck")
    #expect(equivalence?.characterCount == 6)
    #expect(equivalence?.unicodeCodePoints == [
        "U+0075", "U+0020", "U+0073", "U+0075", "U+0063", "U+006B"
    ])
    #expect(equivalence?.bitEditDistance == 4)
    #expect(equivalence?.similarityPercent == 92)
    #expect(equivalence?.confidence == .low)
}

@Test("Does not assign a known phrase to an unrelated malformed bitstream")
func rejectsUnrelatedMalformedPayloadEquivalence() {
    let bits = String(repeating: "10", count: 23) + "1"
    let preview = InvisibleFragmentRevealer.reveal(
        in: "Visible\(zeroWidthJoinerScalars(bits))"
    ).first

    #expect(preview?.presentation == .incompletePayload)
    #expect(preview?.zeroWidthBinary?.probableTextEquivalence == nil)
}

@Test("Makes a lone invisible scalar visible inside source context")
func revealsVisibleContextFallback() {
    let source = "let greeting = \"Hola\"\u{FE0F}\n"
    let preview = InvisibleFragmentRevealer.reveal(in: source).first

    #expect(preview?.presentation == .visibleContext)
    #expect(preview?.codePoint == "U+FE0F")
    #expect(preview?.text.contains("Hola"))
    #expect(preview?.text.contains("⟦U+FE0F⟧"))
}

private func unicodeTags(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.compactMap { scalar in
        Unicode.Scalar(0xE0000 + scalar.value)
    }))
}

private func variationSelectors(_ text: String) -> String {
    String(String.UnicodeScalarView(text.utf8.compactMap { byte in
        let value = UInt32(byte)
        return Unicode.Scalar(value < 16 ? 0xFE00 + value : 0xE0100 + value - 16)
    }))
}

private func zeroWidthBits(_ text: String) -> String {
    var scalars: [Unicode.Scalar] = []
    for byte in text.utf8 {
        for shift in stride(from: 7, through: 0, by: -1) {
            let value: UInt32 = ((byte >> shift) & 1) == 0 ? 0x200B : 0x200C
            if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
        }
    }
    return String(String.UnicodeScalarView(scalars))
}

private func zeroWidthJoinerBits(_ text: String) -> String {
    var scalars: [Unicode.Scalar] = []
    for byte in text.utf8 {
        for shift in stride(from: 7, through: 0, by: -1) {
            let value: UInt32 = ((byte >> shift) & 1) == 0 ? 0x200C : 0x200D
            if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
        }
    }
    return String(String.UnicodeScalarView(scalars))
}

private func zeroWidthJoinerScalars(_ bits: String) -> String {
    String(String.UnicodeScalarView(bits.compactMap { bit in
        Unicode.Scalar(bit == "0" ? 0x200C : 0x200D)
    }))
}
