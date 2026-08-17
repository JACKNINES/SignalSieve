// SPDX-License-Identifier: MPL-2.0
import CoreGraphics
import Foundation
import ImageIO

public struct ClipboardImageRepresentation: Sendable, Equatable {
    public let typeIdentifier: String
    public let data: Data

    public init(typeIdentifier: String, data: Data) {
        self.typeIdentifier = typeIdentifier
        self.data = data
    }
}

public struct ClipboardImagePayload: Sendable, Equatable {
    public let data: Data
    public let fileName: String
    public let sourceTypeIdentifier: String
    public let wasTranscodedToPNG: Bool

    public init(
        data: Data,
        fileName: String,
        sourceTypeIdentifier: String,
        wasTranscodedToPNG: Bool
    ) {
        self.data = data
        self.fileName = fileName
        self.sourceTypeIdentifier = sourceTypeIdentifier
        self.wasTranscodedToPNG = wasTranscodedToPNG
    }
}

public struct ClipboardImageCleaningResult: Sendable, Equatable {
    public let originalPayload: ClipboardImagePayload
    public let cleanedPayload: ClipboardImagePayload
    public let originalReport: FileProvenanceReport
    public let cleanedReport: FileProvenanceReport

    public var removedFindingCount: Int {
        max(0, originalReport.findings.count - cleanedReport.findings.count)
    }

    public init(
        originalPayload: ClipboardImagePayload,
        cleanedPayload: ClipboardImagePayload,
        originalReport: FileProvenanceReport,
        cleanedReport: FileProvenanceReport
    ) {
        self.originalPayload = originalPayload
        self.cleanedPayload = cleanedPayload
        self.originalReport = originalReport
        self.cleanedReport = cleanedReport
    }
}

public enum ClipboardImageImportError: Error, Sendable, Equatable {
    case noSupportedImage
    case imageTooLarge
    case invalidImage
    case couldNotEncode
}

/// Selects a bounded image representation from the clipboard. PNG and JPEG
/// bytes are preserved so their metadata can be inspected. Other supported
/// raster formats are decoded and normalized to a metadata-free PNG locally.
public enum ClipboardImageImporter {
    public static let maximumInputBytes = 64 * 1_024 * 1_024
    public static let maximumPixelCount = 40_000_000
    public static let supportedTypeIdentifiers = [
        "public.png",
        "public.jpeg",
        "public.tiff",
        "public.heic",
        "public.heif",
        "com.compuserve.gif",
        "public.image"
    ]

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let jpegSignature = Data([0xFF, 0xD8])

    public static func importImage(
        from representations: [ClipboardImageRepresentation]
    ) throws -> ClipboardImagePayload {
        let ordered = supportedTypeIdentifiers.compactMap { identifier in
            representations.first { $0.typeIdentifier == identifier }
        }
        guard !ordered.isEmpty else { throw ClipboardImageImportError.noSupportedImage }

        var oversizedRepresentationFound = false
        for representation in ordered {
            guard !representation.data.isEmpty else { continue }
            guard representation.data.count <= maximumInputBytes else {
                oversizedRepresentationFound = true
                continue
            }
            guard isDecodableImage(representation.data) else { continue }

            if representation.data.starts(with: pngSignature) {
                return ClipboardImagePayload(
                    data: representation.data,
                    fileName: "clipboard-image.png",
                    sourceTypeIdentifier: representation.typeIdentifier,
                    wasTranscodedToPNG: false
                )
            }
            if representation.data.starts(with: jpegSignature) {
                return ClipboardImagePayload(
                    data: representation.data,
                    fileName: "clipboard-image.jpg",
                    sourceTypeIdentifier: representation.typeIdentifier,
                    wasTranscodedToPNG: false
                )
            }

            return ClipboardImagePayload(
                data: try regeneratedPNG(from: representation.data),
                fileName: "clipboard-image.png",
                sourceTypeIdentifier: representation.typeIdentifier,
                wasTranscodedToPNG: true
            )
        }
        if oversizedRepresentationFound { throw ClipboardImageImportError.imageTooLarge }
        throw ClipboardImageImportError.invalidImage
    }

    private static func isDecodableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return false
        }
        return true
    }

    /// Decodes the first visible image and writes a fresh PNG without copying
    /// source-container properties. Orientation is baked into the new pixels.
    public static func regeneratedPNG(from data: Data) throws -> Data {
        guard !data.isEmpty else { throw ClipboardImageImportError.invalidImage }
        guard data.count <= maximumInputBytes else {
            throw ClipboardImageImportError.imageTooLarge
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let sourceWidth = integerProperty(properties[kCGImagePropertyPixelWidth]),
              let sourceHeight = integerProperty(properties[kCGImagePropertyPixelHeight]),
              sourceWidth > 0,
              sourceHeight > 0 else {
            throw ClipboardImageImportError.invalidImage
        }
        guard sourceWidth <= maximumPixelCount / sourceHeight,
              sourceWidth * sourceHeight <= maximumPixelCount else {
            throw ClipboardImageImportError.imageTooLarge
        }

        let maximumDimension = max(sourceWidth, sourceHeight)
        let decodingOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            decodingOptions as CFDictionary
        ) else {
            throw ClipboardImageImportError.invalidImage
        }
        let canonicalImage = try canonicalSRGBImage(image)

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw ClipboardImageImportError.couldNotEncode
        }
        CGImageDestinationAddImage(destination, canonicalImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ClipboardImageImportError.couldNotEncode
        }
        let regenerated = output as Data
        do {
            // ImageIO can synthesize a minimal eXIf orientation chunk even
            // when no source properties are supplied. Remove that generated
            // container data as a final deterministic pass.
            return try FileMetadataCleaner.cleanedData(regenerated, format: .png)
        } catch FileMetadataCleaningError.noSupportedMetadata {
            return regenerated
        } catch {
            throw ClipboardImageImportError.couldNotEncode
        }
    }

    private static func integerProperty(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let integer = value as? Int { return integer }
        return nil
    }

    private static func canonicalSRGBImage(_ image: CGImage) throws -> CGImage {
        guard image.width > 0,
              image.height > 0,
              image.width <= Int.max / 4,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            throw ClipboardImageImportError.couldNotEncode
        }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        guard let canonical = context.makeImage() else {
            throw ClipboardImageImportError.couldNotEncode
        }
        return canonical
    }
}

/// Rebuilds a clipboard image from decoded visible pixels, then reanalyzes the
/// new PNG. This removes source-container metadata but intentionally makes no
/// claim about watermarks encoded in the visible pixel values themselves.
public enum ClipboardImageCleaner {
    public static func makeFreshCopy(
        from payload: ClipboardImagePayload
    ) throws -> ClipboardImageCleaningResult {
        let originalReport = FileProvenanceAnalyzer.analyze(
            payload.data,
            fileName: payload.fileName
        )
        let cleanedData = try ClipboardImageImporter.regeneratedPNG(from: payload.data)
        let cleanedPayload = ClipboardImagePayload(
            data: cleanedData,
            fileName: "clipboard-image-signalsieve-clean.png",
            sourceTypeIdentifier: "public.png",
            wasTranscodedToPNG: true
        )
        let cleanedReport = FileProvenanceAnalyzer.analyze(
            cleanedData,
            fileName: cleanedPayload.fileName
        )
        guard cleanedReport.findings.isEmpty,
              !cleanedReport.containsC2PAContainer else {
            throw FileMetadataCleaningError.verificationFailed
        }
        return ClipboardImageCleaningResult(
            originalPayload: payload,
            cleanedPayload: cleanedPayload,
            originalReport: originalReport,
            cleanedReport: cleanedReport
        )
    }
}
