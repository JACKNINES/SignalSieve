// SPDX-License-Identifier: MPL-2.0

/// Pure policy for the editable Input/Result workspace. Returning `nil` means
/// the existing Result must be left untouched because automation is disabled.
public enum InputResultAutomationPolicy {
    public static func prepareSafeResult(
        from input: String,
        isEnabled: Bool
    ) -> String? {
        guard isEnabled else { return nil }
        guard !input.isEmpty else { return "" }
        return TextCleaner.clean(input, mode: .safe).text
    }
}
