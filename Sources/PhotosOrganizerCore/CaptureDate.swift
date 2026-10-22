import AVFoundation
import Foundation
import ImageIO

/// Where a capture date came from, shown in the *Date source* column.
public enum DateSource: String, Sendable {
    case exif = "EXIF"
    case video = "Video metadata"
    case filesystem = "File date"
}

public struct CaptureDate: Equatable, Sendable {
    public var date: LocalDateTime
    public var source: DateSource

    public init(_ date: LocalDateTime, _ source: DateSource) {
        self.date = date
        self.source = source
    }
}

/// Lookup order:
///   * Photos and RAW: EXIF `DateTimeOriginal` → `DateTimeDigitized` → TIFF `DateTime` (ImageIO).
///   * Videos: Apple's `com.apple.quicktime.creationdate` (local time as recorded) → QuickTime/MP4
///     `mvhd` creation time (UTC, shown in the computer's time zone) → AVFoundation creation date.
///   * Optional fallback: the file-system date (the earlier of creation and modification time).
public enum CaptureDateReader {
    public static func captureDate(of url: URL, useFilesystemFallback: Bool = true) async -> CaptureDate? {
        let fileExtension = url.pathExtension.lowercased()
        if MediaTypes.video.contains(fileExtension) {
            if let date = await videoDate(url, fileExtension: fileExtension) {
                return CaptureDate(date, .video)
            }
        } else if let date = imageDate(url) {
            return CaptureDate(date, .exif)
        }
        if useFilesystemFallback, let date = filesystemDate(url) {
            return CaptureDate(date, .filesystem)
        }
        return nil
    }

    // MARK: - EXIF

    public static let minimumExifYear = 1900  // rejects blank EXIF dates such as 0000:00:00 00:00:00
    public static let minimumVideoYear = 1970  // QuickTime's "zero" date decodes as 1904-01-01

    /// Parses EXIF-style dates such as `2014:12:06 16:22:00`; also accepts `-`, `/` and `T`
    /// separators and trailing NULs or time-zone offsets. The wall time is kept as written.
    public static func parseExifDate(_ value: String?, minimumYear: Int = minimumExifYear) -> LocalDateTime? {
        guard let value,
              let match = value.firstMatch(of: /(\d{4})[:\-\/](\d{2})[:\-\/](\d{2})[ T](\d{2}):(\d{2}):(\d{2})/)
        else { return nil }
        let parts = [match.1, match.2, match.3, match.4, match.5, match.6].map { Int($0)! }
        guard parts[0] >= minimumYear else { return nil }
        return LocalDateTime(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4], second: parts[5])
    }

    static func imageDate(_ url: URL) -> LocalDateTime? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, options)
            ?? CGImageSourceCopyProperties(source, options)) as? [CFString: Any]
        guard let properties else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let candidates = [
            exif[kCGImagePropertyExifDateTimeOriginal],
            exif[kCGImagePropertyExifDateTimeDigitized],
            tiff[kCGImagePropertyTIFFDateTime],
        ]
        for case let value as String in candidates {
            if let date = parseExifDate(value) {
                return date
            }
        }
        return nil
    }

    // MARK: - Video

    static func videoDate(_ url: URL, fileExtension: String) async -> LocalDateTime? {
        let asset = AVURLAsset(url: url)
        if MediaTypes.quickTime.contains(fileExtension) {
            // iPhones write the local time plus its offset, e.g. "2014-12-06T16:22:00-0500".
            if let metadata = try? await asset.load(.metadata),
               let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataCreationDate).first,
               let text = try? await item.load(.stringValue),
               let date = parseExifDate(text, minimumYear: minimumVideoYear) {
                return date
            }
            if let utc = QuickTimeMovieHeader.creationDate(of: url) {
                let date = LocalDateTime(utc)
                if date.year >= minimumVideoYear { return date }
            }
        }
        if let item = try? await asset.load(.creationDate),
           let value = try? await item.load(.dateValue) {
            let date = LocalDateTime(value)
            if date.year >= minimumVideoYear { return date }
        }
        return nil
    }

    // MARK: - File system

    static func filesystemDate(_ url: URL) -> LocalDateTime? {
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) else {
            return nil
        }
        let dates = [values.creationDate, values.contentModificationDate].compactMap { $0 }
        return dates.min().map { LocalDateTime($0) }
    }
}
