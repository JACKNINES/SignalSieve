// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Detects common textual binary representations")
func detectsTextualBinaryRepresentations() {
    #expect(BinaryContentDetector.analyze("SGVsbG8sIFNpZ25hbCBTaWV2ZSE=").kind == .base64)
    #expect(BinaryContentDetector.analyze("89 50 4E 47 0D 0A 1A 0A").kind == .hexadecimal)
    #expect(BinaryContentDetector.analyze("01010011 01101001 01100111 01101110").kind == .binaryDigits)
    #expect(BinaryContentDetector.analyze(#"\x48 \x65 \x6c \x6c \x6f"#).kind == .byteEscapes)
}

@Test("Detects raw binary signatures and null bytes")
func detectsRawBinaryData() {
    #expect(BinaryContentDetector.analyze(Data([0x7F, 0x45, 0x4C, 0x46, 0x02])).kind == .rawBinary)
    #expect(BinaryContentDetector.analyze(Data([0x41, 0x00, 0x42])).kind == .rawBinary)
}

@Test("Does not classify ordinary prose and common code as binary")
func avoidsBinaryFalsePositives() {
    #expect(!BinaryContentDetector.analyze("A normal sentence about privacy and copied text.").isDetected)
    #expect(!BinaryContentDetector.analyze("let value = 0xFF; print(value)").isDetected)
}
