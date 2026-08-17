// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import SignalSieveCore

@Test("Visual transfer recovers simple text using local OCR")
func visualRoundTrip() throws {
    let result = try VisualTransfer.roundTrip("Clean text 123")

    #expect(result.text.localizedCaseInsensitiveContains("Clean text"))
    #expect(result.text.contains("123"))
}

@Test("Visual transfer rejects empty or whitespace-only input")
func visualRoundTripRejectsEmptyInput() {
    do {
        _ = try VisualTransfer.roundTrip("  \n\t")
        Issue.record("Whitespace-only input was accepted")
    } catch let error as VisualTransferError {
        #expect(error.errorDescription == VisualTransferError.emptyInput.errorDescription)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("Visual transfer does not reproduce a zero-width character")
func visualRoundTripDropsHiddenCharacter() throws {
    let result = try VisualTransfer.roundTrip("hola\u{200B}mundo")

    #expect(result.text.localizedCaseInsensitiveContains("holamundo"))
    #expect(HiddenTextAnalyzer.inspect(result.text).isClean)
}

@Test("OCR reconstruction joins visual wrapping with spaces")
func visualTransferReconstructsSoftWraps() {
    let lines = [
        VisualTransfer.RecognizedLine(
            text: "A long paragraph wraps",
            boundingBox: CGRect(x: 0.1, y: 0.80, width: 0.8, height: 0.05)
        ),
        VisualTransfer.RecognizedLine(
            text: "onto another visual row",
            boundingBox: CGRect(x: 0.1, y: 0.72, width: 0.8, height: 0.05)
        ),
        VisualTransfer.RecognizedLine(
            text: "without a source newline.",
            boundingBox: CGRect(x: 0.1, y: 0.64, width: 0.8, height: 0.05)
        )
    ]

    #expect(
        VisualTransfer.reconstructText(lines, expectedLineBreakCount: 0)
            == "A long paragraph wraps onto another visual row without a source newline."
    )
}

@Test("OCR reconstruction retains the largest explicit line gap")
func visualTransferReconstructsExplicitBreaks() {
    let lines = [
        VisualTransfer.RecognizedLine(
            text: "First wrapped row",
            boundingBox: CGRect(x: 0.1, y: 0.82, width: 0.8, height: 0.05)
        ),
        VisualTransfer.RecognizedLine(
            text: "continues here.",
            boundingBox: CGRect(x: 0.1, y: 0.75, width: 0.8, height: 0.05)
        ),
        VisualTransfer.RecognizedLine(
            text: "Second source line.",
            boundingBox: CGRect(x: 0.1, y: 0.60, width: 0.8, height: 0.05)
        )
    ]

    #expect(
        VisualTransfer.reconstructText(lines, expectedLineBreakCount: 1)
            == "First wrapped row continues here.\nSecond source line."
    )
}
