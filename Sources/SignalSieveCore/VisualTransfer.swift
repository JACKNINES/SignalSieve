// SPDX-License-Identifier: MPL-2.0
import AppKit
import CoreText
import Foundation
import Vision

public enum VisualTransferError: LocalizedError {
    case emptyInput
    case renderingFailed
    case noTextRecognized

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "There is no text to process."
        case .renderingFailed:
            return "The text could not be rendered as an image."
        case .noTextRecognized:
            return "Vision did not recognize text in the generated image."
        }
    }
}

public struct VisualTransferResult: Sendable {
    public let text: String
    public let sourceCharacterCount: Int
    public let recognizedCharacterCount: Int

    public init(text: String, sourceCharacterCount: Int, recognizedCharacterCount: Int) {
        self.text = text
        self.sourceCharacterCount = sourceCharacterCount
        self.recognizedCharacterCount = recognizedCharacterCount
    }
}

public enum VisualTransfer {
    struct RecognizedLine: Sendable, Equatable {
        let text: String
        let boundingBox: CGRect
    }

    /// Performs an entirely local text -> bitmap -> OCR round trip.
    public static func roundTrip(_ text: String) throws -> VisualTransferResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VisualTransferError.emptyInput
        }

        let source = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let expectedLineBreakCount = source.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        let image = try render(source)
        let recognized = try recognize(
            image,
            expectedLineBreakCount: expectedLineBreakCount
        )

        return VisualTransferResult(
            text: recognized,
            sourceCharacterCount: text.count,
            recognizedCharacterCount: recognized.count
        )
    }

    private static func render(_ text: String) throws -> CGImage {
        let canvasWidth: CGFloat = 1_200
        let padding: CGFloat = 72
        let textWidth = canvasWidth - (padding * 2)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 7
        style.paragraphSpacing = 12
        style.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 28, nil),
            .foregroundColor: NSColor.black.cgColor,
            .paragraphStyle: style
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            nil,
            CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            nil
        )
        let canvasHeight = max(220, ceil(measured.height) + (padding * 2))
        guard let context = CGContext(
            data: nil,
            width: Int(canvasWidth),
            height: Int(canvasHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VisualTransferError.renderingFailed
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.textMatrix = .identity

        let path = CGMutablePath()
        path.addRect(
            CGRect(
                x: padding,
                y: padding,
                width: textWidth,
                height: canvasHeight - (padding * 2)
            )
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)

        guard let cgImage = context.makeImage() else {
            throw VisualTransferError.renderingFailed
        }
        return cgImage
    }

    private static func recognize(
        _ image: CGImage,
        expectedLineBreakCount: Int
    ) throws -> String {
        do {
            return try recognize(
                image,
                level: .accurate,
                usesLanguageCorrection: true,
                languages: ["es-ES", "en-US"],
                expectedLineBreakCount: expectedLineBreakCount
            )
        } catch {
            // Some macOS installations do not have the on-device accurate
            // language model available. Fast recognition remains local and
            // preserves the bitmap boundary that Visual Transfer promises.
            return try recognize(
                image,
                level: .fast,
                usesLanguageCorrection: false,
                languages: [],
                expectedLineBreakCount: expectedLineBreakCount
            )
        }
    }

    private static func recognize(
        _ image: CGImage,
        level: VNRequestTextRecognitionLevel,
        usesLanguageCorrection: Bool,
        languages: [String],
        expectedLineBreakCount: Int
    ) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = usesLanguageCorrection
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }
        request.minimumTextHeight = 0.006

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])

        let observations = (request.results ?? []).sorted { left, right in
            let yDifference = abs(left.boundingBox.midY - right.boundingBox.midY)
            if yDifference < 0.012 {
                return left.boundingBox.minX < right.boundingBox.minX
            }
            return left.boundingBox.midY > right.boundingBox.midY
        }

        let lines = observations.compactMap { observation -> RecognizedLine? in
            guard let text = observation.topCandidates(1).first?.string else {
                return nil
            }
            return RecognizedLine(text: text, boundingBox: observation.boundingBox)
        }
        guard !lines.isEmpty else {
            throw VisualTransferError.noTextRecognized
        }
        return reconstructText(
            lines,
            expectedLineBreakCount: expectedLineBreakCount
        )
    }

    /// Rejoins OCR rows that came from visual word wrapping. When the source
    /// contained explicit line breaks, the largest vertical gaps are retained.
    static func reconstructText(
        _ lines: [RecognizedLine],
        expectedLineBreakCount: Int
    ) -> String {
        let cleanedLines = lines.compactMap { line -> RecognizedLine? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedLine(text: text, boundingBox: line.boundingBox)
        }
        guard let first = cleanedLines.first else { return "" }
        guard cleanedLines.count > 1 else { return first.text }

        let gaps = zip(cleanedLines, cleanedLines.dropFirst()).enumerated().map {
            index, pair in
            let gap = max(0, pair.0.boundingBox.minY - pair.1.boundingBox.maxY)
            return (index: index, gap: gap)
        }
        let retainedBreakCount = min(
            max(0, expectedLineBreakCount),
            gaps.count
        )
        let retainedBreaks = Set(
            gaps
                .sorted {
                    if $0.gap == $1.gap { return $0.index < $1.index }
                    return $0.gap > $1.gap
                }
                .prefix(retainedBreakCount)
                .map(\.index)
        )

        var result = first.text
        for index in 1..<cleanedLines.count {
            result += retainedBreaks.contains(index - 1) ? "\n" : " "
            result += cleanedLines[index].text
        }
        return result
    }
}
