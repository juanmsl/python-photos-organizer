import Foundation

public struct FileEntry: Hashable, Identifiable, Sendable {
    public var url: URL
    public var relativePath: String
    /// Lower-case, without the dot (`"jpg"`); `""` when the file has none.
    public var fileExtension: String
    public var size: Int64

    public var id: String { relativePath }

    public init(url: URL, relativePath: String, fileExtension: String, size: Int64) {
        self.url = url
        self.relativePath = relativePath
        self.fileExtension = fileExtension
        self.size = size
    }
}

public enum FileScanner {
    /// Every file under `root` (sub-folders included), sorted by relative path.
    ///
    /// Hidden files and folders (names starting with ".") are skipped by default, which also drops
    /// macOS noise such as `.DS_Store` and `._*` AppleDouble files. Symbolic links to folders are not
    /// followed. Stops early, returning what it found so far, when the current task is cancelled.
    public static func scan(_ root: URL, includeHidden: Bool = false) throws -> [FileEntry] {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, errorHandler: { _, _ in true }  // skip unreadable folders
        ) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: root.path])
        }

        var entries: [FileEntry] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            let name = url.lastPathComponent
            guard var values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if !includeHidden && name.hasPrefix(".") {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isSymbolicLink == true {
                guard let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: Set(keys)) else {
                    continue  // broken link
                }
                values = target
            }
            guard values.isRegularFile == true else { continue }

            entries.append(FileEntry(
                url: url,
                // `level` is the depth below `root`; comparing path prefixes breaks on /var vs /private/var.
                relativePath: url.pathComponents.suffix(enumerator.level).joined(separator: "/"),
                fileExtension: url.pathExtension.lowercased(),
                size: Int64(values.fileSize ?? 0)
            ))
        }
        return entries.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    /// How many files there are of each extension.
    public static func countExtensions(_ entries: some Sequence<FileEntry>) -> [String: Int] {
        entries.reduce(into: [:]) { counts, entry in counts[entry.fileExtension, default: 0] += 1 }
    }
}
