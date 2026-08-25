// SPDX-License-Identifier: MPL-2.0

/// Pure policy for the editable Input/Result workspace. Returning `nil` means
/// the existing Result must be left untouched because automation is disabled
/// or the selected protocol requires the asynchronous OCR boundary.
public enum InputResultAutomationPolicy {
    public static func prepareDeterministicResult(
        from input: String,
        isEnabled: Bool,
        using selection: ClipboardAutomationProtocol
    ) -> String? {
        guard isEnabled else { return nil }
        guard let mode = selection.cleaningMode else { return nil }
        guard !input.isEmpty else { return "" }
        return TextCleaner.clean(input, mode: mode).text
    }

    public static func shouldUseVisualTransfer(
        isEnabled: Bool,
        using selection: ClipboardAutomationProtocol
    ) -> Bool {
        isEnabled && selection == .visualTransfer
    }
}
