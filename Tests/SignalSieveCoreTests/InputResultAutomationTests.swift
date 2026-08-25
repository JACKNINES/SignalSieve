// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import Testing

@Test("Input automation prepares Safe Clean output and can be disabled")
func preparesAutomaticInputResult() {
    let source = "visible\u{200B}payload"
    #expect(InputResultAutomationPolicy.prepareSafeResult(
        from: source,
        isEnabled: true
    ) == "visiblepayload")
    #expect(InputResultAutomationPolicy.prepareSafeResult(
        from: source,
        isEnabled: false
    ) == nil)
    #expect(InputResultAutomationPolicy.prepareSafeResult(
        from: "",
        isEnabled: true
    ) == "")
}
