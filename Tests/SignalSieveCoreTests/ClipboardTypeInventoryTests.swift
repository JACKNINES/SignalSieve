// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import Testing

@Test("Recognizes image, file, HTML, and rich-text pasteboard representations")
func recognizesClipboardRepresentations() {
    let inventory = ClipboardTypeAnalyzer.analyze(typeIdentifiers: [
        "public.png",
        "public.file-url",
        "public.html",
        "public.rtf",
        "public.utf8-plain-text"
    ])

    #expect(inventory.kinds == [.image, .fileURL, .html, .richText])
    #expect(inventory.requiresFileProvenanceReview)
    #expect(inventory.containsRichTextRepresentation)
}

@Test("Plain text alone does not request file-provenance review")
func ignoresPlainTextForFileProvenance() {
    let inventory = ClipboardTypeAnalyzer.analyze(typeIdentifiers: [
        "public.utf8-plain-text"
    ])

    #expect(inventory.kinds.isEmpty)
    #expect(!inventory.requiresFileProvenanceReview)
    #expect(!inventory.containsRichTextRepresentation)
}

@MainActor
@Test("Plain-text replacement physically removes HTML and RTF pasteboard representations")
func replacesRichPasteboardWithPlainText() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }

    let text = "Guarda .build/vendor entre corridas"
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    pasteboard.setData(
        Data("<p>Guarda <code>.build/vendor</code> entre corridas</p>".utf8),
        forType: .html
    )
    pasteboard.setData(Data("{\\rtf1 styled}".utf8), forType: .rtf)

    let before = ClipboardTypeAnalyzer.analyze(
        typeIdentifiers: (pasteboard.types ?? []).map(\.rawValue)
    )
    #expect(before.containsRichTextRepresentation)
    #expect(ClipboardPlainTextWriter.replace(
        on: pasteboard,
        expectedText: text,
        replacement: text
    ))

    let after = ClipboardTypeAnalyzer.analyze(
        typeIdentifiers: (pasteboard.types ?? []).map(\.rawValue)
    )
    #expect(pasteboard.string(forType: .string) == text)
    #expect(!after.containsRichTextRepresentation)
    #expect(pasteboard.data(forType: .html) == nil)
    #expect(pasteboard.data(forType: .rtf) == nil)
}
