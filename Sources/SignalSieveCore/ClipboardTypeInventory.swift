// SPDX-License-Identifier: MPL-2.0
public enum ClipboardContentKind: String, CaseIterable, Sendable, Equatable {
    case image = "Image data"
    case fileURL = "File reference"
    case html = "HTML representation"
    case richText = "Rich-text representation"
}

public struct ClipboardTypeInventory: Sendable, Equatable {
    public let kinds: [ClipboardContentKind]

    public init(kinds: [ClipboardContentKind]) {
        self.kinds = kinds
    }

    public var requiresFileProvenanceReview: Bool {
        kinds.contains(.image) || kinds.contains(.fileURL)
    }

    public var containsRichTextRepresentation: Bool {
        kinds.contains(.html) || kinds.contains(.richText)
    }
}

public enum ClipboardTypeAnalyzer {
    private static let imageTypes = Set([
        "public.image",
        "public.png",
        "public.jpeg",
        "public.tiff",
        "public.heic",
        "public.heif",
        "com.compuserve.gif",
        "com.adobe.pdf"
    ])
    private static let fileTypes = Set([
        "public.file-url",
        "NSFilenamesPboardType"
    ])
    private static let htmlTypes = Set([
        "public.html",
        "Apple HTML pasteboard type"
    ])
    private static let richTextTypes = Set([
        "public.rtf",
        "public.rtfd",
        "NeXT Rich Text Format v1.0 pasteboard type"
    ])

    public static func analyze(typeIdentifiers: [String]) -> ClipboardTypeInventory {
        let identifiers = Set(typeIdentifiers)
        var kinds: [ClipboardContentKind] = []
        if !identifiers.isDisjoint(with: imageTypes) { kinds.append(.image) }
        if !identifiers.isDisjoint(with: fileTypes) { kinds.append(.fileURL) }
        if !identifiers.isDisjoint(with: htmlTypes) { kinds.append(.html) }
        if !identifiers.isDisjoint(with: richTextTypes) { kinds.append(.richText) }
        return ClipboardTypeInventory(kinds: kinds)
    }
}
