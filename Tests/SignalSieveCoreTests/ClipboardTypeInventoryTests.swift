// SPDX-License-Identifier: MPL-2.0
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
}

@Test("Plain text alone does not request file-provenance review")
func ignoresPlainTextForFileProvenance() {
    let inventory = ClipboardTypeAnalyzer.analyze(typeIdentifiers: [
        "public.utf8-plain-text"
    ])

    #expect(inventory.kinds.isEmpty)
    #expect(!inventory.requiresFileProvenanceReview)
}
