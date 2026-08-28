// SPDX-License-Identifier: MPL-2.0
import AppKit

/// The one boundary that turns a multi-representation pasteboard item into
/// plain text. Keeping it here makes HTML/RTF removal directly testable without
/// touching the user's global clipboard.
public struct ClipboardPlainTextSnapshot: Sendable, Equatable {
    public let changeCount: Int
    public let text: String

    public init(changeCount: Int, text: String) {
        self.changeCount = changeCount
        self.text = text
    }
}

@MainActor
public enum ClipboardPlainTextWriter {
    public static func snapshot(on pasteboard: NSPasteboard) -> ClipboardPlainTextSnapshot? {
        guard let text = pasteboard.string(forType: .string) else { return nil }
        return ClipboardPlainTextSnapshot(changeCount: pasteboard.changeCount, text: text)
    }

    public static func matches(
        _ expected: ClipboardPlainTextSnapshot,
        on pasteboard: NSPasteboard
    ) -> Bool {
        pasteboard.changeCount == expected.changeCount
            && pasteboard.string(forType: .string) == expected.text
    }

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

    @discardableResult
    public static func replace(
        on pasteboard: NSPasteboard,
        expectedChangeCount: Int,
        expectedText: String,
        replacement: String
    ) -> Bool {
        replace(
            on: pasteboard,
            matching: ClipboardPlainTextSnapshot(
                changeCount: expectedChangeCount,
                text: expectedText
            ),
            replacement: replacement
        )
    }

    /// Performs the application's compare-and-replace operation on the main
    /// actor. NSPasteboard has no cross-process CAS primitive, so callers must
    /// use this single boundary instead of checking in UI code and writing in
    /// a second step.
    @discardableResult
    public static func replace(
        on pasteboard: NSPasteboard,
        matching expected: ClipboardPlainTextSnapshot,
        replacement: String
    ) -> Bool {
        guard matches(expected, on: pasteboard) else {
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
