import AppKit
import Observation
import PhotosOrganizerCore

struct FileRow: Identifiable {
    var entry: FileEntry
    var result: OrganizeResult?

    var id: String { entry.id }
}

struct ExtensionOption: Identifiable {
    var fileExtension: String
    var count: Int
    var isChecked: Bool

    var id: String { fileExtension }
    var label: String { fileExtension.isEmpty ? "(no extension)" : fileExtension.uppercased() }
}

struct Progress {
    var done = 0
    var total = 0
    var indeterminate = false
}

func formatSize(_ bytes: Int64) -> String {
    var size = Double(bytes)
    for unit in ["B", "KB", "MB", "GB"] {
        if size < 1024 {
            return unit == "B" ? String(format: "%.0f %@", size, unit) : String(format: "%.1f %@", size, unit)
        }
        size /= 1024
    }
    return String(format: "%.1f TB", size)
}

/// State and actions of the main window. Long-running work runs off the main actor (scanning in a
/// detached task, file operations inside the `Organizer` actor); results come back in batches.
@MainActor
@Observable
final class AppModel {
    private(set) var sourceDir: URL?
    private(set) var allEntries: [FileEntry] = []
    private(set) var extensions: [ExtensionOption] = []
    private(set) var rows: [FileRow] = []
    private(set) var outputDir: URL?
    /// Output folder of the last run, used to show destinations as relative paths.
    private(set) var resultsOutputDir: URL?
    private(set) var isBusy = false
    private(set) var progress = Progress()
    private(set) var logLines: [String] = []

    var layout: FolderLayout = .yearMonth { didSet { clearResults() } }
    var action: Action = .copy {
        didSet {
            if action != .delete { permanentDelete = false }
            clearResults()
        }
    }
    /// Deliberately never saved: every session starts on the safer setting (Trash).
    var permanentDelete = false
    var useFilesystemFallback = true

    @ObservationIgnored private var cancelWork: (() -> Void)?
    @ObservationIgnored private var rescanAfterWork = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        restoreSettings()
    }

    // MARK: - Derived state

    var isDeleting: Bool { action == .delete }
    var isReady: Bool { !rows.isEmpty && (isDeleting || outputDir != nil) }

    var selectionSummary: String {
        guard sourceDir != nil else { return "No folder selected." }
        let size = rows.reduce(Int64(0)) { $0 + $1.entry.size }
        return "\(rows.count) of \(allEntries.count) files selected (\(formatSize(size)))"
    }

    var exampleDestination: String {
        let example = buildDestination(
            outputDir: URL(filePath: "/<output>"), takenAt: LocalDateTime(year: 2014, month: 12, day: 6, hour: 16, minute: 22)!,
            fileExtension: "jpg", layout: layout
        )
        return String(example.path.dropFirst())
    }

    func displayDestination(_ result: OrganizeResult?) -> String {
        guard let result else { return "" }
        guard let destination = result.destination else { return result.message }
        if let base = resultsOutputDir?.path, destination.path.hasPrefix(base + "/") {
            return String(destination.path.dropFirst(base.count + 1))
        }
        return destination.path
    }

    // MARK: - Settings

    private func restoreSettings() {
        if let path = defaults.string(forKey: "output_dir"), !path.isEmpty {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                outputDir = URL(filePath: path, directoryHint: .isDirectory)
            }
        }
        action = defaults.string(forKey: "action").flatMap(Action.init) ?? .copy
        layout = defaults.string(forKey: "layout").flatMap(FolderLayout.init) ?? .yearMonth
        useFilesystemFallback = defaults.object(forKey: "fallback") as? Bool ?? true
    }

    func saveSettings() {
        if let sourceDir { defaults.set(sourceDir.path, forKey: "source_dir") }
        defaults.set(outputDir?.path ?? "", forKey: "output_dir")
        defaults.set(action.rawValue, forKey: "action")
        defaults.set(layout.rawValue, forKey: "layout")
        defaults.set(useFilesystemFallback, forKey: "fallback")
    }

    // MARK: - Folders

    func chooseSource() {
        let start = sourceDir ?? defaults.string(forKey: "source_dir").map { URL(filePath: $0) }
        guard let folder = Dialogs.chooseFolder(title: "Select source folder", startingAt: start) else { return }
        sourceDir = folder
        extensions = []
        startScan()
    }

    func chooseOutput() {
        guard let folder = Dialogs.chooseFolder(title: "Select output folder", startingAt: outputDir) else { return }
        outputDir = folder
        clearResults()
    }

    // MARK: - Scanning

    func startScan() {
        guard let sourceDir, !isBusy else { return }
        log("Scanning \(sourceDir.path) …")
        isBusy = true
        progress = Progress(indeterminate: true)

        let scan = Task.detached(priority: .userInitiated) { try FileScanner.scan(sourceDir) }
        cancelWork = { scan.cancel() }
        Task {
            do {
                let entries = try await scan.value
                allEntries = entries
                populateExtensions()
                applyFilter()
                log("Found \(entries.count) files.")
            } catch {
                Dialogs.show("Scan failed", error.localizedDescription, style: .critical)
            }
            progress = Progress()
            finishWork()
        }
    }

    private func populateExtensions() {
        let previouslyChecked = extensions.isEmpty ? nil : Set(extensions.filter(\.isChecked).map(\.fileExtension))
        extensions = FileScanner.countExtensions(allEntries)
            .sorted { $0.key < $1.key }
            .map { fileExtension, count in
                ExtensionOption(
                    fileExtension: fileExtension, count: count,
                    isChecked: previouslyChecked?.contains(fileExtension) ?? MediaTypes.isMedia(fileExtension)
                )
            }
    }

    // MARK: - File-type filter

    func setChecked(_ fileExtension: String, _ checked: Bool) {
        guard let index = extensions.firstIndex(where: { $0.fileExtension == fileExtension }) else { return }
        extensions[index].isChecked = checked
        applyFilter()
    }

    func checkExtensions(where predicate: (String) -> Bool) {
        for index in extensions.indices {
            extensions[index].isChecked = predicate(extensions[index].fileExtension)
        }
        applyFilter()
    }

    private func applyFilter() {
        let selected = Set(extensions.filter(\.isChecked).map(\.fileExtension))
        rows = allEntries.filter { selected.contains($0.fileExtension) }.map { FileRow(entry: $0) }
    }

    private func clearResults() {
        guard rows.contains(where: { $0.result != nil }) else { return }
        for index in rows.indices { rows[index].result = nil }
    }

    // MARK: - Organize / delete

    func start(dryRun: Bool) {
        guard !isBusy else { return }
        if isDeleting {
            startDelete(dryRun: dryRun)
            return
        }
        guard let outputDir else {
            Dialogs.show("Output folder", "Please choose an output folder first.")
            return
        }
        let resolvedOutput = outputDir.resolvingSymlinksInPath().standardizedFileURL
        if let sourceDir, sourceDir.resolvingSymlinksInPath().standardizedFileURL.path == resolvedOutput.path {
            Dialogs.show("Output folder", "The output folder must be different from the source folder.", style: .warning)
            return
        }

        // Never re-process files that already live inside the output folder.
        let outputPrefix = resolvedOutput.path + "/"
        let work = rows.enumerated()
            .filter { !$0.element.entry.url.resolvingSymlinksInPath().path.hasPrefix(outputPrefix) }
            .map { ($0.offset, $0.element.entry.url) }
        guard !work.isEmpty else {
            Dialogs.show("Nothing to do", "No files match the selected file types.")
            return
        }

        if !dryRun && action == .move {
            let text = "\(work.count) files will be MOVED out of the source folder into:\n\(outputDir.path)\n\nContinue?"
            guard Dialogs.confirm("Move files", text) else { return }
        }

        let verb = dryRun ? "Previewing" : (action == .move ? "Moving" : "Copying")
        log("\(verb) \(work.count) files → \(outputDir.path) (\(layout.label))")
        run(work, outputDir: outputDir, action: action, dryRun: dryRun)
    }

    private func startDelete(dryRun: Bool) {
        let work = rows.enumerated().map { ($0.offset, $0.element.entry.url) }
        guard !work.isEmpty else {
            Dialogs.show("Nothing to do", "No files match the selected file types.")
            return
        }
        let permanent = permanentDelete

        if !dryRun {
            let size = formatSize(rows.reduce(Int64(0)) { $0 + $1.entry.size })
            let confirmed = permanent
                ? Dialogs.confirm(
                    "Delete files", "\(work.count) files (\(size)) will be PERMANENTLY DELETED.\n\nThis cannot be undone. Continue?",
                    style: .critical, defaultNo: true
                )
                : Dialogs.confirm(
                    "Delete files", "\(work.count) files (\(size)) will be moved to the Trash.\n\nContinue?",
                    style: .warning, defaultNo: true
                )
            guard confirmed else { return }
        }

        let target = permanent ? "permanently" : "to Trash"
        log("\(dryRun ? "Previewing delete of" : "Deleting") \(work.count) files (\(target))")
        run(work, outputDir: nil, action: .delete, dryRun: dryRun, permanentDelete: permanent)
    }

    private func run(_ work: [(Int, URL)], outputDir: URL?, action: Action, dryRun: Bool, permanentDelete: Bool = false) {
        let organizer: Organizer
        do {
            organizer = try Organizer(
                outputDir: outputDir, action: action, useFilesystemFallback: useFilesystemFallback,
                dryRun: dryRun, layout: layout, permanentDelete: permanentDelete
            )
        } catch {
            Dialogs.show("Cannot start", error.localizedDescription, style: .critical)
            return
        }

        saveSettings()
        clearResults()
        resultsOutputDir = outputDir?.standardizedFileURL
        isBusy = true
        progress = Progress(done: 0, total: work.count)

        let task = Task {
            var summary: [Status: Int] = [:]
            var pending: [(Int, OrganizeResult)] = []
            var lastFlush = ContinuousClock.now
            for (row, url) in work {
                if Task.isCancelled { break }
                let result = await organizer.process(url)  // runs on the organizer actor, off the main thread
                summary[result.status, default: 0] += 1
                pending.append((row, result))
                // Updating the table once per file would re-render it thousands of times.
                if ContinuousClock.now - lastFlush > .milliseconds(100) {
                    apply(pending)
                    pending.removeAll()
                    lastFlush = .now
                }
            }
            apply(pending)
            organizeFinished(summary, cancelled: Task.isCancelled)
        }
        cancelWork = { task.cancel() }
    }

    private func apply(_ results: [(Int, OrganizeResult)]) {
        for (row, result) in results where rows.indices.contains(row) {
            rows[row].result = result
            if result.status == .error {
                log("ERROR \(result.source.path): \(result.message)")
            }
        }
        progress.done += results.count
    }

    private func organizeFinished(_ summary: [Status: Int], cancelled: Bool) {
        let parts = Status.allCases.compactMap { status in summary[status].map { "\(status.rawValue): \($0)" } }
        log((cancelled ? "Cancelled. " : "Done. ") + (parts.isEmpty ? "nothing processed" : parts.joined(separator: ", ")))
        let removed = summary.filter { $0.key.removesSource }.values.reduce(0, +)
        if removed > 0 && sourceDir != nil {
            log("Files were removed from the source folder; rescanning it.")
            rescanAfterWork = true
        }
        finishWork()
    }

    // MARK: - Work lifecycle

    func cancel() {
        guard let cancelWork else { return }
        cancelWork()
        log("Cancelling…")
    }

    private func finishWork() {
        isBusy = false
        cancelWork = nil
        if rescanAfterWork {
            rescanAfterWork = false
            startScan()
        }
    }

    private func log(_ message: String) {
        logLines.append(message)
        if logLines.count > 2000 { logLines.removeFirst(logLines.count - 2000) }
    }
}
