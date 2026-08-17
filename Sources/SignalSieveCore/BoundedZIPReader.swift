// SPDX-License-Identifier: MPL-2.0
import CSignalSieveZip
import Foundation

enum BoundedZIPError: Error, Equatable {
    case invalidContainer
    case unsupportedZIP64
    case tooManyEntries
    case entryTooLarge
    case unsupportedCompression
    case encryptedEntry
    case invalidPath
    case duplicateEntry
    case decompressionFailed
    case checksumMismatch
}

struct BoundedZIPEntry: Sendable, Equatable {
    let name: String
    let compressionMethod: UInt16
    let flags: UInt16
    let crc32: UInt32
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

struct BoundedZIPReader {
    static let maximumEntryCount = 4_096
    static let maximumCentralDirectoryBytes = 16 * 1_024 * 1_024
    static let maximumExtractedEntryBytes = 8 * 1_024 * 1_024

    let data: Data
    let entries: [BoundedZIPEntry]

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.parseEntries(in: data)
    }

    func entry(named name: String) -> BoundedZIPEntry? {
        entries.first { $0.name == name }
    }

    func data(for entry: BoundedZIPEntry) throws -> Data {
        guard entry.uncompressedSize <= Self.maximumExtractedEntryBytes else {
            throw BoundedZIPError.entryTooLarge
        }
        let offset = entry.localHeaderOffset
        guard Self.littleEndianUInt32(data, at: offset) == 0x04034B50,
              let nameLength = Self.littleEndianUInt16(data, at: offset + 26).map(Int.init),
              let extraLength = Self.littleEndianUInt16(data, at: offset + 28).map(Int.init) else {
            throw BoundedZIPError.invalidContainer
        }
        let payloadStart = offset + 30 + nameLength + extraLength
        guard payloadStart >= 0,
              entry.compressedSize >= 0,
              payloadStart <= data.count - entry.compressedSize else {
            throw BoundedZIPError.invalidContainer
        }
        let compressed = Data(data[payloadStart..<(payloadStart + entry.compressedSize)])
        let extracted: Data
        switch entry.compressionMethod {
        case 0:
            guard compressed.count == entry.uncompressedSize else {
                throw BoundedZIPError.invalidContainer
            }
            extracted = compressed
        case 8:
            extracted = try inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw BoundedZIPError.unsupportedCompression
        }
        guard Self.crc32(extracted) == entry.crc32 else {
            throw BoundedZIPError.checksumMismatch
        }
        return extracted
    }

    private static func parseEntries(in data: Data) throws -> [BoundedZIPEntry] {
        guard data.count >= 22,
              let endOffset = endOfCentralDirectoryOffset(in: data),
              let diskNumber = littleEndianUInt16(data, at: endOffset + 4),
              let centralDisk = littleEndianUInt16(data, at: endOffset + 6),
              let entryCount = littleEndianUInt16(data, at: endOffset + 10).map(Int.init),
              let centralSize = littleEndianUInt32(data, at: endOffset + 12).map(Int.init),
              let centralOffset = littleEndianUInt32(data, at: endOffset + 16).map(Int.init) else {
            throw BoundedZIPError.invalidContainer
        }
        guard diskNumber == 0, centralDisk == 0 else {
            throw BoundedZIPError.unsupportedZIP64
        }
        guard entryCount <= maximumEntryCount else {
            throw BoundedZIPError.tooManyEntries
        }
        guard centralSize <= maximumCentralDirectoryBytes,
              centralOffset >= 0,
              centralSize >= 0,
              centralOffset <= data.count - centralSize,
              centralOffset + centralSize <= endOffset else {
            throw BoundedZIPError.invalidContainer
        }

        var entries: [BoundedZIPEntry] = []
        var names: Set<String> = []
        var offset = centralOffset
        for _ in 0..<entryCount {
            guard littleEndianUInt32(data, at: offset) == 0x02014B50,
                  let flags = littleEndianUInt16(data, at: offset + 8),
                  let method = littleEndianUInt16(data, at: offset + 10),
                  let checksum = littleEndianUInt32(data, at: offset + 16),
                  let compressedSize32 = littleEndianUInt32(data, at: offset + 20),
                  let uncompressedSize32 = littleEndianUInt32(data, at: offset + 24),
                  let nameLength = littleEndianUInt16(data, at: offset + 28).map(Int.init),
                  let extraLength = littleEndianUInt16(data, at: offset + 30).map(Int.init),
                  let commentLength = littleEndianUInt16(data, at: offset + 32).map(Int.init),
                  let localOffset32 = littleEndianUInt32(data, at: offset + 42) else {
                throw BoundedZIPError.invalidContainer
            }
            guard compressedSize32 != UInt32.max,
                  uncompressedSize32 != UInt32.max,
                  localOffset32 != UInt32.max else {
                throw BoundedZIPError.unsupportedZIP64
            }
            guard flags & 0x0001 == 0 else {
                throw BoundedZIPError.encryptedEntry
            }
            let recordLength = 46 + nameLength + extraLength + commentLength
            guard recordLength >= 46, offset <= data.count - recordLength else {
                throw BoundedZIPError.invalidContainer
            }
            let nameData = Data(data[(offset + 46)..<(offset + 46 + nameLength)])
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
            guard let name, isSafePath(name) else {
                throw BoundedZIPError.invalidPath
            }
            guard names.insert(name).inserted else {
                throw BoundedZIPError.duplicateEntry
            }
            entries.append(BoundedZIPEntry(
                name: name,
                compressionMethod: method,
                flags: flags,
                crc32: checksum,
                compressedSize: Int(compressedSize32),
                uncompressedSize: Int(uncompressedSize32),
                localHeaderOffset: Int(localOffset32)
            ))
            offset += recordLength
        }
        guard offset == centralOffset + centralSize else {
            throw BoundedZIPError.invalidContainer
        }
        return entries
    }

    private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        let lowerBound = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= lowerBound {
            if littleEndianUInt32(data, at: offset) == 0x06054B50,
               let commentLength = littleEndianUInt16(data, at: offset + 20).map(Int.init),
               offset + 22 + commentLength == data.count {
                return offset
            }
            offset -= 1
        }
        return nil
    }

    private static func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\") else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains("..")
    }

    private func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0, expectedSize <= Self.maximumExtractedEntryBytes else {
            throw BoundedZIPError.entryTooLarge
        }
        if expectedSize == 0 { return Data() }
        var output = [UInt8](repeating: 0, count: expectedSize)
        var written = 0
        let status = compressed.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                ss_inflate_raw(
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress,
                    compressed.count,
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                    expectedSize,
                    &written
                )
            }
        }
        guard status == 0, written == expectedSize else {
            throw BoundedZIPError.decompressionFailed
        }
        return Data(output)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var checksum: UInt32 = 0xFFFF_FFFF
        for byte in data {
            checksum ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = UInt32(bitPattern: -Int32(checksum & 1))
                checksum = (checksum >> 1) ^ (0xEDB8_8320 & mask)
            }
        }
        return ~checksum
    }

    private static func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
