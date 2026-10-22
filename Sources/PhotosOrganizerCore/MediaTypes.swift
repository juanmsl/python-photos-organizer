import Foundation

/// Lower-case extensions, without the dot.
public enum MediaTypes {
    public static let image: Set<String> = ["jpg", "jpeg", "jpe", "png", "tif", "tiff", "heic", "heif", "webp"]
    public static let raw: Set<String> = ["cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "dng", "orf", "rw2", "raf", "pef", "srw"]
    public static let video: Set<String> = ["mp4", "m4v", "mov", "3gp", "3g2", "avi", "mkv", "mts", "m2ts", "wmv", "mpg", "mpeg"]
    /// ISO base media / QuickTime containers: their `mvhd` creation time is stored in UTC.
    public static let quickTime: Set<String> = ["mp4", "m4v", "mov", "3gp", "3g2"]
    public static let media = image.union(raw).union(video)

    /// Pre-selected in the file-type filter.
    public static func isMedia(_ fileExtension: String) -> Bool {
        media.contains(fileExtension.lowercased())
    }
}
