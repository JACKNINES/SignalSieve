// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore

enum ClipboardImagePasteboardReader {
    static func read(
        from pasteboard: NSPasteboard = .general
    ) throws -> ClipboardImagePayload {
        let availableTypes = Set((pasteboard.types ?? []).map(\.rawValue))
        let representations = ClipboardImageImporter.supportedTypeIdentifiers.compactMap {
            identifier -> ClipboardImageRepresentation? in
            guard availableTypes.contains(identifier),
                  let data = pasteboard.data(forType: NSPasteboard.PasteboardType(identifier)) else {
                return nil
            }
            return ClipboardImageRepresentation(typeIdentifier: identifier, data: data)
        }
        return try ClipboardImageImporter.importImage(from: representations)
    }

    @discardableResult
    static func write(
        _ payload: ClipboardImagePayload,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        let type: NSPasteboard.PasteboardType
        if payload.data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) {
            type = .png
        } else if payload.data.starts(with: Data([0xFF, 0xD8])) {
            type = NSPasteboard.PasteboardType("public.jpeg")
        } else {
            return false
        }

        let item = NSPasteboardItem()
        guard item.setData(payload.data, forType: type) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
