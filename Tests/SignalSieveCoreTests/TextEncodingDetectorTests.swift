// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Detects and round-trips UTF encodings and byte order")
func detectsAndRoundTripsTextEncoding() throws {
    let text = "let value = \"Hola\"\u{200B}\n"
    let cases: [(TextEncodingKind, Bool)] = [
        (.utf8, false), (.utf8, true),
        (.utf16LittleEndian, false), (.utf16LittleEndian, true),
        (.utf16BigEndian, false), (.utf16BigEndian, true),
        (.utf32LittleEndian, false), (.utf32LittleEndian, true),
        (.utf32BigEndian, false), (.utf32BigEndian, true)
    ]

    for (encoding, bom) in cases {
        let data = try #require(TextEncodingDetector.encode(text, as: encoding, includeByteOrderMark: bom))
        let decoded = try #require(TextEncodingDetector.decode(data))
        #expect(decoded.text == text)
        #expect(decoded.encoding == encoding)
        #expect(decoded.hasByteOrderMark == bom)
        #expect(decoded.encodedData() == data)
    }
}

@Test("Does not decode an executable signature as text")
func executableRemainsBinary() {
    let data = Data([0x7F, 0x45, 0x4C, 0x46, 0x02, 0x00, 0x00, 0x00])
    #expect(BinaryContentDetector.analyze(data).kind == .rawBinary)
}
