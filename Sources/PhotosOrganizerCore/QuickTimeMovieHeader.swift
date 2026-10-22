import Foundation

/// Reads the creation time from the `moov/mvhd` box of QuickTime and ISO base media files
/// (MOV, MP4, M4V, 3GP). Only box headers are read, so large videos are not loaded into memory.
enum QuickTimeMovieHeader {
    /// Seconds between 1904-01-01 (QuickTime epoch) and 1970-01-01.
    private static let epochOffset: UInt64 = 2_082_844_800

    /// The creation time as an absolute date (it is stored in UTC), or `nil` when it is missing or unset.
    static func creationDate(of url: URL) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(),
              let moov = findBox("moov", in: handle, from: 0, to: fileSize),
              let mvhd = findBox("mvhd", in: handle, from: moov.contentStart, to: moov.end)
        else { return nil }

        guard (try? handle.seek(toOffset: mvhd.contentStart)) != nil,
              let header = try? handle.read(upToCount: 12), header.count >= 8
        else { return nil }
        let version = header[header.startIndex]
        let seconds: UInt64
        if version == 1 {
            guard header.count >= 12 else { return nil }
            seconds = bigEndian(header.dropFirst(4).prefix(8))
        } else {
            seconds = bigEndian(header.dropFirst(4).prefix(4))
        }
        guard seconds > epochOffset else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds - epochOffset))
    }

    private struct Box {
        var contentStart: UInt64
        var end: UInt64
    }

    private static func findBox(_ type: String, in handle: FileHandle, from start: UInt64, to end: UInt64) -> Box? {
        var offset = start
        while offset + 8 <= end {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let header = try? handle.read(upToCount: 16), header.count >= 8
            else { return nil }
            var size = bigEndian(header.prefix(4))
            var headerSize: UInt64 = 8
            if size == 1 {
                guard header.count >= 16 else { return nil }
                size = bigEndian(header.dropFirst(8).prefix(8))
                headerSize = 16
            } else if size == 0 {
                size = end - offset  // box runs to the end of its parent
            }
            guard size >= headerSize, offset + size <= end else { return nil }
            let boxType = String(decoding: header.dropFirst(4).prefix(4), as: UTF8.self)
            if boxType == type {
                return Box(contentStart: offset + headerSize, end: offset + size)
            }
            offset += size
        }
        return nil
    }

    private static func bigEndian(_ bytes: some Collection<UInt8>) -> UInt64 {
        bytes.reduce(0) { $0 << 8 | UInt64($1) }
    }
}
