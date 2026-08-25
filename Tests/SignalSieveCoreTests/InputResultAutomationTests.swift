// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import Testing

@Test("Input automation follows the selected deterministic protocol")
func preparesAutomaticInputResultUsingSelectedProtocol() {
    let source = "heart: \u{2764}\u{FE0F} visible\u{200B}payload"
    #expect(InputResultAutomationPolicy.prepareDeterministicResult(
        from: source,
        isEnabled: true,
        using: .safeClean
    ) == "heart: \u{2764}\u{FE0F} visiblepayload")
    #expect(InputResultAutomationPolicy.prepareDeterministicResult(
        from: source,
        isEnabled: true,
        using: .strictClean
    ) == "heart: \u{2764} visiblepayload")
    #expect(InputResultAutomationPolicy.prepareDeterministicResult(
        from: source,
        isEnabled: false,
        using: .safeClean
    ) == nil)
    #expect(InputResultAutomationPolicy.prepareDeterministicResult(
        from: "",
        isEnabled: true,
        using: .strictClean
    ) == "")
}

@Test("Input automation distinguishes OCR and an unselected protocol")
func recognizesAutomaticInputOCRProtocol() {
    #expect(InputResultAutomationPolicy.prepareDeterministicResult(
        from: "Visible text",
        isEnabled: true,
        using: .visualTransfer
    ) == nil)
    #expect(InputResultAutomationPolicy.prepareDeterministicResult(
        from: "Visible text",
        isEnabled: true,
        using: .reviewAll
    ) == nil)
    #expect(InputResultAutomationPolicy.shouldUseVisualTransfer(
        isEnabled: true,
        using: .visualTransfer
    ))
    #expect(!InputResultAutomationPolicy.shouldUseVisualTransfer(
        isEnabled: false,
        using: .visualTransfer
    ))
    #expect(!InputResultAutomationPolicy.shouldUseVisualTransfer(
        isEnabled: true,
        using: .safeClean
    ))
}
