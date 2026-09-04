//
//  Zip.swift
//  DeckKit
//
//  Created by David Sherlock on 2026.
//
//  Copied from swift-text-docx, which needs the same thing for .docx. Two
//  copies of a pinned, pure function is a trade worth making over a package
//  that exists to hold one file; a THIRD user means extracting it properly.
//
//  The container. A .pptx is a zip archive with a fixed set of members, and
//  this writes exactly that much of the zip format: stored entries, a
//  central directory, and the end record.
//
//  Stored rather than deflated, on purpose. The members are a few kilobytes
//  of XML; compressing them would save less than the size of a font and
//  cost a dependency on a compression library — or a port of one. Every
//  reader accepts stored entries, because the format has always allowed
//  them, and the timestamps are pinned so the same document is the same
//  bytes every time it is written.
//

import Foundation

enum Zip {

    /// One member of an archive.
    struct Entry {
        let name: String
        let data: Data
    }

    /// The archive, with every entry stored.
    static func archive(_ entries: [Entry]) -> Data {
        var out = Data()
        var directory = Data()

        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(out.count)

            // Local file header.
            out.append(le32(0x0403_4B50))
            out.append(le16(20))                    // version needed: 2.0
            out.append(le16(0))                     // flags
            out.append(le16(0))                     // method: stored
            out.append(le16(0))                     // time: 00:00
            out.append(le16(0x0021))                // date: 1980-01-01
            out.append(le32(crc))
            out.append(le32(UInt32(entry.data.count)))
            out.append(le32(UInt32(entry.data.count)))
            out.append(le16(UInt16(name.count)))
            out.append(le16(0))                     // extra length
            out.append(name)
            out.append(entry.data)

            // Central directory record.
            directory.append(le32(0x0201_4B50))
            directory.append(le16(20))              // made by
            directory.append(le16(20))              // needed
            directory.append(le16(0))
            directory.append(le16(0))
            directory.append(le16(0))
            directory.append(le16(0x0021))
            directory.append(le32(crc))
            directory.append(le32(UInt32(entry.data.count)))
            directory.append(le32(UInt32(entry.data.count)))
            directory.append(le16(UInt16(name.count)))
            directory.append(le16(0))               // extra
            directory.append(le16(0))               // comment
            directory.append(le16(0))               // disk
            directory.append(le16(0))               // internal attributes
            directory.append(le32(0))               // external attributes
            directory.append(le32(offset))
            directory.append(name)
        }

        let directoryOffset = UInt32(out.count)
        out.append(directory)

        // End of central directory.
        out.append(le32(0x0605_4B50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(directory.count)))
        out.append(le32(directoryOffset))
        out.append(le16(0))
        return out
    }

    /// The members of an archive this wrote — stored entries only, which is
    /// all it writes. For tests and for a caller that wants to look inside
    /// a document it made.
    static func entries(in data: Data) -> [String: Data] {
        var members: [String: Data] = [:]
        var cursor = data.startIndex

        while cursor + 30 <= data.endIndex, read32(data, at: cursor) == 0x0403_4B50 {
            let method = read16(data, at: cursor + 8)
            let size = Int(read32(data, at: cursor + 18))
            let nameLength = Int(read16(data, at: cursor + 26))
            let extraLength = Int(read16(data, at: cursor + 28))
            let nameStart = cursor + 30
            let dataStart = nameStart + nameLength + extraLength
            guard dataStart + size <= data.endIndex else { break }

            let name = String(decoding: data[nameStart..<nameStart + nameLength], as: UTF8.self)
            if method == 0 { members[name] = Data(data[dataStart..<dataStart + size]) }
            cursor = dataStart + size
        }
        return members
    }

    // MARK: Bytes

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }

    private static func read16(_ data: Data, at index: Int) -> UInt16 {
        UInt16(data[index]) | UInt16(data[index + 1]) << 8
    }

    private static func read32(_ data: Data, at index: Int) -> UInt32 {
        UInt32(data[index]) | UInt32(data[index + 1]) << 8
            | UInt32(data[index + 2]) << 16 | UInt32(data[index + 3]) << 24
    }

    // MARK: CRC-32

    /// The IEEE polynomial, as every zip reader checks it. Table-driven;
    /// the table is built once.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }
}
