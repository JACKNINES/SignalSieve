// SPDX-License-Identifier: MPL-2.0
import CoreGraphics
import Foundation
import ImageIO

public struct PixelSpectralForensicsReport: Sendable, Equatable {
    public let score: Double
    public let threshold: Double
    public let sampledPixelCount: Int
    public let carrierFrequencyX: Int
    public let carrierFrequencyY: Int
    public let normalizedCorrelation: Double
    public let peakProminence: Double
    public let tileCoherence: Double
    public let residualRMS: Double
    public let hasEnoughSamples: Bool

    public init(
        score: Double,
        threshold: Double,
        sampledPixelCount: Int,
        carrierFrequencyX: Int,
        carrierFrequencyY: Int,
        normalizedCorrelation: Double,
        peakProminence: Double,
        tileCoherence: Double,
        residualRMS: Double,
        hasEnoughSamples: Bool
    ) {
        self.score = score
        self.threshold = threshold
        self.sampledPixelCount = sampledPixelCount
        self.carrierFrequencyX = carrierFrequencyX
        self.carrierFrequencyY = carrierFrequencyY
        self.normalizedCorrelation = normalizedCorrelation
        self.peakProminence = peakProminence
        self.tileCoherence = tileCoherence
        self.residualRMS = residualRMS
        self.hasEnoughSamples = hasEnoughSamples
    }

    public var isElevated: Bool {
        hasEnoughSamples && score >= threshold
    }
}

public enum PixelSpectralForensicsError: Error, Sendable, Equatable {
    case invalidImage
    case imageTooLarge
    case couldNotRender
    case couldNotEncode
}

/// A provider-neutral screen for weak, spatially periodic luminance carriers.
/// It does not possess any vendor key or model and therefore cannot authenticate
/// SynthID or attribute an image to a particular generator.
public enum PixelSpectralForensics {
    public static let maximumPixelCount = 40_000_000
    public static let maximumSampledPixels = 262_144
    public static let minimumReliableSamples = 4_096
    public static let elevatedThreshold = 0.62

    public static func analyze(_ data: Data) throws -> PixelSpectralForensicsReport {
        let raster = try rasterize(data)
        return analyze(raster).report
    }

    public static func regenerate(_ data: Data, strength: Double) throws -> Data {
        var raster = try rasterize(data)
        let analysis = analyze(raster)
        let carrier = analysis.carrier
        let boundedStrength = min(0.70, max(0.05, strength))
        let gain = 0.55 + boundedStrength * 0.95
        let maximumChannelChange = max(1, Int((2 + boundedStrength * 10).rounded()))
        let twoPi = 2 * Double.pi

        for y in 0..<raster.height {
            for x in 0..<raster.width {
                let offset = (y * raster.width + x) * 4
                guard raster.bytes[offset + 3] != 0 else { continue }
                let phase = twoPi * (
                    Double(carrier.frequencyX) * Double(x) / Double(raster.width)
                    + Double(carrier.frequencyY) * Double(y) / Double(raster.height)
                )
                let projection = carrier.cosineAmplitude * cos(phase)
                    + carrier.sineAmplitude * sin(phase)
                var channelChange = Int((projection * 255 * gain).rounded())
                channelChange = min(maximumChannelChange, max(-maximumChannelChange, channelChange))

                if channelChange == 0, analysis.report.isElevated,
                   coordinateHash(x: x, y: y) % 5 == 0 {
                    channelChange = projection >= 0 ? 1 : -1
                }
                guard channelChange != 0 else { continue }
                for channel in 0..<3 {
                    let value = Int(raster.bytes[offset + channel]) - channelChange
                    raster.bytes[offset + channel] = UInt8(min(255, max(0, value)))
                }
            }
        }
        return try encode(raster)
    }

    private struct Raster {
        let width: Int
        let height: Int
        var bytes: [UInt8]
        let sourceType: CFString
        let orientation: Int?
    }

    private struct Carrier {
        let frequencyX: Int
        let frequencyY: Int
        let normalizedCorrelation: Double
        let cosineAmplitude: Double
        let sineAmplitude: Double
        let tileCoherence: Double
    }

    private struct Analysis {
        let report: PixelSpectralForensicsReport
        let carrier: Carrier
    }

    private static func analyze(_ raster: Raster) -> Analysis {
        let totalPixels = raster.width * raster.height
        let samplingStep = max(
            1,
            Int(ceil(sqrt(Double(totalPixels) / Double(maximumSampledPixels))))
        )
        let sampledWidth = (raster.width + samplingStep - 1) / samplingStep
        let sampledHeight = (raster.height + samplingStep - 1) / samplingStep
        var luminance = [Double](repeating: 0, count: sampledWidth * sampledHeight)

        for sampleY in 0..<sampledHeight {
            let sourceY = min(raster.height - 1, sampleY * samplingStep)
            for sampleX in 0..<sampledWidth {
                let sourceX = min(raster.width - 1, sampleX * samplingStep)
                let offset = (sourceY * raster.width + sourceX) * 4
                let alpha = Double(raster.bytes[offset + 3]) / 255
                guard alpha > 0 else { continue }
                let red = Double(raster.bytes[offset]) / 255
                let green = Double(raster.bytes[offset + 1]) / 255
                let blue = Double(raster.bytes[offset + 2]) / 255
                luminance[sampleY * sampledWidth + sampleX] =
                    (0.2126 * red + 0.7152 * green + 0.0722 * blue) * alpha
            }
        }

        var residual = [Double](repeating: 0, count: luminance.count)
        var residualEnergy = 0.0
        var residualCount = 0
        if sampledWidth >= 3, sampledHeight >= 3 {
            for y in 1..<(sampledHeight - 1) {
                for x in 1..<(sampledWidth - 1) {
                    var neighborSum = 0.0
                    for offsetY in -1...1 {
                        for offsetX in -1...1 where offsetX != 0 || offsetY != 0 {
                            neighborSum += luminance[(y + offsetY) * sampledWidth + x + offsetX]
                        }
                    }
                    let value = luminance[y * sampledWidth + x] - neighborSum / 8
                    residual[y * sampledWidth + x] = value
                    residualEnergy += value * value
                    residualCount += 1
                }
            }
        }
        let residualRMS = residualCount == 0 ? 0 : sqrt(residualEnergy / Double(residualCount))
        let frequencies = candidateFrequencies(width: sampledWidth, height: sampledHeight)
        let carriers = frequencies.map {
            measureCarrier(
                residual: residual,
                width: sampledWidth,
                height: sampledHeight,
                frequencyX: $0.0,
                frequencyY: $0.1,
                residualRMS: residualRMS
            )
        }
        let fallback = Carrier(
            frequencyX: 0,
            frequencyY: 0,
            normalizedCorrelation: 0,
            cosineAmplitude: 0,
            sineAmplitude: 0,
            tileCoherence: 0
        )
        let best = carriers.max { $0.normalizedCorrelation < $1.normalizedCorrelation } ?? fallback
        let sortedCorrelations = carriers.map(\.normalizedCorrelation).sorted()
        let median = sortedCorrelations.isEmpty
            ? 0
            : sortedCorrelations[sortedCorrelations.count / 2]
        let prominence = median > 0.000_001
            ? min(20, best.normalizedCorrelation / median)
            : 0

        let correlationScore = clamp((best.normalizedCorrelation - 0.08) / 0.34)
        let prominenceScore = clamp((prominence - 1.8) / 5.2)
        let coherenceScore = clamp((best.tileCoherence - 0.42) / 0.48)
        let energyReliability = clamp(residualRMS / 0.002)
        let enoughSamples = residualCount >= minimumReliableSamples
            && sampledWidth >= 32
            && sampledHeight >= 32
        let sampleReliability = min(1, Double(residualCount) / Double(minimumReliableSamples))
        let score = clamp(
            (0.58 * correlationScore + 0.24 * prominenceScore + 0.18 * coherenceScore)
                * energyReliability
                * sampleReliability
        )
        let report = PixelSpectralForensicsReport(
            score: score,
            threshold: elevatedThreshold,
            sampledPixelCount: residualCount,
            carrierFrequencyX: best.frequencyX,
            carrierFrequencyY: best.frequencyY,
            normalizedCorrelation: best.normalizedCorrelation,
            peakProminence: prominence,
            tileCoherence: best.tileCoherence,
            residualRMS: residualRMS,
            hasEnoughSamples: enoughSamples
        )
        return Analysis(report: report, carrier: best)
    }

    private static func candidateFrequencies(width: Int, height: Int) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        let maximumFrequency = min(32, min(width, height) / 4)
        guard maximumFrequency >= 6 else { return result }
        for frequency in Swift.stride(from: 6, through: maximumFrequency, by: 2) {
            result.append((frequency, 0))
            result.append((0, frequency))
            result.append((frequency, frequency))
            result.append((frequency, -frequency))
            if frequency >= 10 {
                result.append((frequency, frequency / 2))
                result.append((frequency / 2, -frequency))
            }
        }
        return result
    }

    private static func measureCarrier(
        residual: [Double],
        width: Int,
        height: Int,
        frequencyX: Int,
        frequencyY: Int,
        residualRMS: Double
    ) -> Carrier {
        let tileColumns = 4
        let tileRows = 4
        let tileCount = tileColumns * tileRows
        var tileCosine = [Double](repeating: 0, count: tileCount)
        var tileSine = [Double](repeating: 0, count: tileCount)
        var tileSamples = [Int](repeating: 0, count: tileCount)
        var cosineSum = 0.0
        var sineSum = 0.0
        var sampleCount = 0
        let twoPi = 2 * Double.pi

        guard width >= 3, height >= 3 else {
            return Carrier(
                frequencyX: frequencyX,
                frequencyY: frequencyY,
                normalizedCorrelation: 0,
                cosineAmplitude: 0,
                sineAmplitude: 0,
                tileCoherence: 0
            )
        }
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let phase = twoPi * (
                    Double(frequencyX) * Double(x) / Double(width)
                    + Double(frequencyY) * Double(y) / Double(height)
                )
                let value = residual[y * width + x]
                let cosineValue = value * cos(phase)
                let sineValue = value * sin(phase)
                cosineSum += cosineValue
                sineSum += sineValue
                sampleCount += 1

                let tileX = min(tileColumns - 1, x * tileColumns / width)
                let tileY = min(tileRows - 1, y * tileRows / height)
                let tileIndex = tileY * tileColumns + tileX
                tileCosine[tileIndex] += cosineValue
                tileSine[tileIndex] += sineValue
                tileSamples[tileIndex] += 1
            }
        }
        guard sampleCount > 0 else {
            return Carrier(
                frequencyX: frequencyX,
                frequencyY: frequencyY,
                normalizedCorrelation: 0,
                cosineAmplitude: 0,
                sineAmplitude: 0,
                tileCoherence: 0
            )
        }
        let residualCosineAmplitude = 2 * cosineSum / Double(sampleCount)
        let residualSineAmplitude = 2 * sineSum / Double(sampleCount)
        let amplitude = hypot(residualCosineAmplitude, residualSineAmplitude)
        let normalizedCorrelation = residualRMS > 0.000_000_1
            ? min(1, amplitude / (residualRMS * sqrt(2)))
            : 0
        let phaseX = 2 * Double.pi * Double(frequencyX) / Double(width)
        let phaseY = 2 * Double.pi * Double(frequencyY) / Double(height)
        let neighborhoodResponse = 1 - (
            2 * cos(phaseX)
                + 2 * cos(phaseY)
                + 4 * cos(phaseX) * cos(phaseY)
        ) / 8
        let recoveryDivisor = max(0.05, abs(neighborhoodResponse))
        var cosineAmplitude = residualCosineAmplitude / recoveryDivisor
        var sineAmplitude = residualSineAmplitude / recoveryDivisor
        let recoveredAmplitude = hypot(cosineAmplitude, sineAmplitude)
        let maximumRecoveredAmplitude = 0.06
        if recoveredAmplitude > maximumRecoveredAmplitude {
            let scale = maximumRecoveredAmplitude / recoveredAmplitude
            cosineAmplitude *= scale
            sineAmplitude *= scale
        }

        var unitX = 0.0
        var unitY = 0.0
        var includedTiles = 0
        for index in 0..<tileCount where tileSamples[index] >= 32 {
            let tileAmplitude = hypot(tileCosine[index], tileSine[index])
            guard tileAmplitude > 0.000_000_1 else { continue }
            unitX += tileCosine[index] / tileAmplitude
            unitY += tileSine[index] / tileAmplitude
            includedTiles += 1
        }
        let coherence = includedTiles == 0
            ? 0
            : min(1, hypot(unitX, unitY) / Double(includedTiles))
        return Carrier(
            frequencyX: frequencyX,
            frequencyY: frequencyY,
            normalizedCorrelation: normalizedCorrelation,
            cosineAmplitude: cosineAmplitude,
            sineAmplitude: sineAmplitude,
            tileCoherence: coherence
        )
    }

    private static func rasterize(_ data: Data) throws -> Raster {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PixelSpectralForensicsError.invalidImage
        }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              width <= maximumPixelCount / height,
              width * height <= maximumPixelCount,
              width * height <= Int.max / 4 else {
            throw PixelSpectralForensicsError.imageTooLarge
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            throw PixelSpectralForensicsError.couldNotRender
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any]
        return Raster(
            width: width,
            height: height,
            bytes: bytes,
            sourceType: type,
            orientation: properties?[kCGImagePropertyOrientation] as? Int
        )
    }

    private static func encode(_ raster: Raster) throws -> Data {
        var bytes = raster.bytes
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &bytes,
                width: raster.width,
                height: raster.height,
                bitsPerComponent: 8,
                bytesPerRow: raster.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
              ),
              let image = context.makeImage() else {
            throw PixelSpectralForensicsError.couldNotRender
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            raster.sourceType,
            1,
            nil
        ) else {
            throw PixelSpectralForensicsError.couldNotEncode
        }
        var properties: [CFString: Any] = [:]
        if let orientation = raster.orientation, orientation != 1 {
            properties[kCGImagePropertyOrientation] = orientation
        }
        if (raster.sourceType as String).lowercased().contains("jpeg") {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.95
        }
        CGImageDestinationAddImage(
            destination,
            image,
            properties.isEmpty ? nil : properties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw PixelSpectralForensicsError.couldNotEncode
        }
        let encoded = output as Data
        do {
            switch (raster.sourceType as String).lowercased() {
            case let type where type.contains("png"):
                return try FileMetadataCleaner.cleanedData(encoded, format: .png)
            case let type where type.contains("jpeg") || type.contains("jpg"):
                return try FileMetadataCleaner.cleanedData(encoded, format: .jpeg)
            default:
                return encoded
            }
        } catch {
            throw PixelSpectralForensicsError.couldNotEncode
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func coordinateHash(x: Int, y: Int) -> UInt32 {
        var value = UInt32(truncatingIfNeeded: x) &* 0x9E37_79B1
        value ^= UInt32(truncatingIfNeeded: y) &* 0x85EB_CA77
        value ^= value >> 16
        value &*= 0x7FEB_352D
        value ^= value >> 15
        return value
    }
}
