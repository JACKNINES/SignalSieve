// SPDX-License-Identifier: MPL-2.0
import AppKit

/// The one boundary that turns a multi-representation pasteboard item into
/// plain text. Keeping it here makes HTML/RTF removal directly testable without
/// touching the user's global clipboard.
public enum ClipboardPlainTextWriter {
    @discardableResult
    public static func replace(
        on pasteboard: NSPasteboard,
        expectedText: String,
        replacement: String
    ) -> Bool {
        guard pasteboard.string(forType: .string) == expectedText else {
            return false
        }
        write(replacement, to: pasteboard)
        return true
    }

    public static func write(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
