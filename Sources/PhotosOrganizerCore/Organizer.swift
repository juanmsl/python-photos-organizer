import Foundation

public enum Action: String, CaseIterable, Sendable {
    case copy
    case move
    case delete
}

public enum FolderLayout: String, CaseIterable, Identifiable, Sendable {
    case year = "year"                         // <output>/2014/2014-12-06-T-16-22-00.jpg
    case yearMonth = "year/month"              // <output>/2014/12/2014-12-06-T-16-22-00.jpg   (default)
    case yearMonthDay = "year/month/day"       // <output>/2014/12/06/2014-12-06-T-16-22-00.jpg

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .year: "Year (YYYY)"
        case .yearMonth: "Year / Month (YYYY/MM)"
        case .yearMonthDay: "Year / Month / Day (YYYY/MM/DD)"
        }
    }

    public func folders(for date: LocalDateTime) -> [String] {
        let parts = [String(format: "%04d", date.year), String(format: "%02d", date.month), String(format: "%02d", date.day)]
        switch self {
        case .year: return Array(parts.prefix(1))
        case .yearMonth: return Array(parts.prefix(2))
        case .yearMonthDay: return parts
        }
    }
}

public enum Status: String, CaseIterable, Sendable {
    case planned = "Planned"
    case copied = "Copied"
    case moved = "Moved"
    case trashed = "Moved to Trash"
    case deleted = "Deleted"
    case duplicate = "Duplicate (skipped)"
    case noDate = "No date (skipped)"
    case error = "Error"

    /// The file is no longer in the source folder.
    public var removesSource: Bool { [.moved, .trashed, .deleted].contains(self) }
}

public struct OrganizeResult: Sendable {
    public var source: URL
    public var status: Status
    public var date: LocalDateTime?
    public var dateSource: DateSource?
    public var destination: URL?
    public var message: String

    public init(
        source: URL, status: Status, date: LocalDateTime? = nil, dateSource: DateSource? = nil,
        destination: URL? = nil, message: String = ""
    ) {
        self.source = source
        self.status = status
        self.date = date
        self.dateSource = dateSource
        self.destination = destination
        self.message = message
    }
}

public enum OrganizerError: Error, Equatable {
    case outputFolderRequired
}

/// `<output>/2014/12/2014-12-06-T-16-22-00.jpg`; `index` > 0 adds `-1`, `-2`… for same-second shots.
/// The original extension is kept, in lower case.
public func buildDestination(
    outputDir: URL, takenAt: LocalDateTime, fileExtension: String, index: Int = 0, layout: FolderLayout = .yearMonth
) -> URL {
    var name = takenAt.fileStem
    if index > 0 { name += "-\(index)" }
    if !fileExtension.isEmpty { name += "." + fileExtension.lowercased() }
    return layout.folders(for: takenAt).reduce(outputDir) { $0.appending(path: $1, directoryHint: .isDirectory) }
        .appending(path: name, directoryHint: .notDirectory)
}

/// Processes files one at a time, keeping track of names already used in this run.
///
/// With `.delete` no metadata is read and `outputDir` is ignored: each file is sent to the Trash,
/// or removed for good when `permanentDelete` is set.
public actor Organizer {
    public typealias TrashHandler = @Sendable (URL) throws -> Void

    public let outputDir: URL?
    public let action: Action
    public let useFilesystemFallback: Bool
    public let dryRun: Bool
    public let layout: FolderLayout
    public let permanentDelete: Bool
    private let trash: TrashHandler
    /// Destination path → file it was assigned to, so dry runs detect collisions too.
    private var reserved: [String: URL] = [:]

    public init(
        outputDir: URL?,
        action: Action = .copy,
        useFilesystemFallback: Bool = true,
        dryRun: Bool = false,
        layout: FolderLayout = .yearMonth,
        permanentDelete: Bool = false,
        trash: @escaping TrashHandler = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        if action != .delete && outputDir == nil {
            throw OrganizerError.outputFolderRequired
        }
        self.outputDir = outputDir?.standardizedFileURL
        self.action = action
        self.useFilesystemFallback = useFilesystemFallback
        self.dryRun = dryRun
        self.layout = layout
        self.permanentDelete = permanentDelete
        self.trash = trash
    }

    public func process(_ source: URL) async -> OrganizeResult {
        if action == .delete {
            return delete(source)
        }
        guard let capture = await CaptureDateReader.captureDate(of: source, useFilesystemFallback: useFilesystemFallback) else {
            return OrganizeResult(source: source, status: .noDate, message: "No EXIF/metadata date found")
        }

        let (destination, isDuplicate) = resolveDestination(for: source, takenAt: capture.date)
        if isDuplicate {
            return OrganizeResult(
                source: source, status: .duplicate, date: capture.date, dateSource: capture.source,
                destination: destination, message: "Identical file already in output"
            )
        }
        if dryRun {
            return OrganizeResult(source: source, status: .planned, date: capture.date, dateSource: capture.source, destination: destination)
        }

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let status: Status
            if action == .move {
                try fileManager.moveItem(at: source, to: destination)
                status = .moved
            } else {
                try fileManager.copyItem(at: source, to: destination)  // keeps timestamps and attributes
                status = .copied
            }
            reserved[destination.path] = destination  // the source may be gone after a move
            return OrganizeResult(source: source, status: status, date: capture.date, dateSource: capture.source, destination: destination)
        } catch {
            reserved[destination.path] = nil
            return OrganizeResult(source: source, status: .error, message: error.localizedDescription)
        }
    }

    private func delete(_ source: URL) -> OrganizeResult {
        if dryRun {
            return OrganizeResult(
                source: source, status: .planned,
                message: permanentDelete ? "Will be deleted permanently" : "Will be moved to Trash"
            )
        }
        do {
            if permanentDelete {
                try FileManager.default.removeItem(at: source)
                return OrganizeResult(source: source, status: .deleted, message: "Deleted permanently")
            }
            try trash(source)
            return OrganizeResult(source: source, status: .trashed, message: "Moved to Trash")
        } catch {
            return OrganizeResult(source: source, status: .error, message: error.localizedDescription)
        }
    }

    /// The first free destination, or the existing destination that holds identical content.
    private func resolveDestination(for source: URL, takenAt: LocalDateTime) -> (URL, isDuplicate: Bool) {
        var index = 0
        while true {
            let candidate = buildDestination(
                outputDir: outputDir!, takenAt: takenAt, fileExtension: source.pathExtension, index: index, layout: layout
            )
            var other = reserved[candidate.path]
            if other == nil && FileManager.default.fileExists(atPath: candidate.path) {
                other = candidate
            }
            guard let other else {
                reserved[candidate.path] = source
                return (candidate, false)
            }
            if FileManager.default.contentsEqual(atPath: source.path, andPath: other.path) {
                return (candidate, true)
            }
            index += 1
        }
    }
}
