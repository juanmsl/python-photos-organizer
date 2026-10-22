import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PhotosOrganizerCore

// MARK: - Helpers

/// A temporary folder that is removed when the test ends.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "photos-organizer-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func path(_ relative: String) -> URL { url.appending(path: relative) }
}

/// Writes an 8×8 JPEG with an optional EXIF `DateTimeOriginal`. Different colours give different bytes.
@discardableResult
func makeJPEG(_ url: URL, takenAt: String?, color: (CGFloat, CGFloat, CGFloat) = (1, 0, 0)) throws -> URL {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let context = CGContext(
        data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    let image = context.makeImage()!

    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    var properties: [CFString: Any] = [:]
    if let takenAt {
        properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: takenAt]
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> LocalDateTime {
    LocalDateTime(year: year, month: month, day: day, hour: hour, minute: minute, second: second)!
}

// MARK: - Naming and layouts

@Test func buildDestinationMatchesRequestedPattern() {
    let destination = buildDestination(outputDir: URL(filePath: "/out"), takenAt: date(2014, 12, 6, 16, 22, 0), fileExtension: "JPG")
    #expect(destination.path == "/out/2014/12/2014-12-06-T-16-22-00.jpg")
}

@Test(arguments: [
    (FolderLayout.year, "/out/2014/2014-12-06-T-16-22-00.jpg"),
    (FolderLayout.yearMonth, "/out/2014/12/2014-12-06-T-16-22-00.jpg"),
    (FolderLayout.yearMonthDay, "/out/2014/12/06/2014-12-06-T-16-22-00.jpg"),
])
func buildDestinationFolderLayouts(layout: FolderLayout, expected: String) {
    let destination = buildDestination(
        outputDir: URL(filePath: "/out"), takenAt: date(2014, 12, 6, 16, 22, 0), fileExtension: "jpg", layout: layout
    )
    #expect(destination.path == expected)
}

@Test func suffixAndMissingExtension() {
    let destination = buildDestination(outputDir: URL(filePath: "/out"), takenAt: date(2014, 12, 6, 16, 22, 0), fileExtension: "", index: 2)
    #expect(destination.path == "/out/2014/12/2014-12-06-T-16-22-00-2")
}

@Test func organizerUsesSelectedLayout() async throws {
    let tmp = try TempDir()
    let source = try makeJPEG(tmp.path("in/a.jpg"), takenAt: "2014:12:06 16:22:00")
    let result = try await Organizer(outputDir: tmp.path("out"), layout: .yearMonthDay).process(source)
    #expect(result.destination?.path == tmp.path("out/2014/12/06/2014-12-06-T-16-22-00.jpg").path)
    #expect(FileManager.default.fileExists(atPath: result.destination!.path))
}

// MARK: - Metadata

@Test(arguments: [
    ("2014:12:06 16:22:00", date(2014, 12, 6, 16, 22, 0)),
    ("2014:12:06 16:22:00\0", date(2014, 12, 6, 16, 22, 0)),
    ("2014-12-06T16:22:00", date(2014, 12, 6, 16, 22, 0)),
    ("2014-12-06T16:22:00-0500", date(2014, 12, 6, 16, 22, 0)),
    ("0000:00:00 00:00:00", nil),
    ("    :  :     :  :  ", nil),
    ("2014:02:30 10:00:00", nil),
] as [(String, LocalDateTime?)])
func parseExifDate(raw: String, expected: LocalDateTime?) {
    #expect(CaptureDateReader.parseExifDate(raw) == expected)
}

@Test func parseExifDateOfNil() {
    #expect(CaptureDateReader.parseExifDate(nil) == nil)
}

@Test func readsExifDate() async throws {
    let tmp = try TempDir()
    let photo = try makeJPEG(tmp.path("a.jpg"), takenAt: "2014:12:06 16:22:00")
    let capture = await CaptureDateReader.captureDate(of: photo)
    #expect(capture == CaptureDate(date(2014, 12, 6, 16, 22, 0), .exif))
}

@Test func fallsBackToFilesystemDateOnlyWhenEnabled() async throws {
    let tmp = try TempDir()
    let photo = try makeJPEG(tmp.path("a.jpg"), takenAt: nil)
    #expect(await CaptureDateReader.captureDate(of: photo, useFilesystemFallback: false) == nil)
    #expect(await CaptureDateReader.captureDate(of: photo, useFilesystemFallback: true)?.source == .filesystem)
}

@Test func readsQuickTimeMovieHeader() throws {
    let tmp = try TempDir()
    // 2014-12-06 16:22:00 UTC, in seconds since 1904-01-01.
    let seconds = UInt32(1_417_882_920 + 2_082_844_800)
    var mvhd = Data([0, 0, 0, 0])  // version 0, flags
    mvhd.append(contentsOf: withUnsafeBytes(of: seconds.bigEndian, Array.init))
    mvhd.append(Data(count: 92))
    func box(_ type: String, _ content: Data) -> Data {
        var data = Data(withUnsafeBytes(of: UInt32(8 + content.count).bigEndian, Array.init))
        data.append(type.data(using: .ascii)!)
        data.append(content)
        return data
    }
    let file = box("ftyp", Data("qt  ".utf8) + Data(count: 4)) + box("moov", box("mvhd", mvhd))
    let url = tmp.path("clip.mov")
    try file.write(to: url)

    #expect(QuickTimeMovieHeader.creationDate(of: url) == Date(timeIntervalSince1970: 1_417_882_920))
}

@Test func quickTimeZeroDateIsIgnored() throws {
    let tmp = try TempDir()
    let url = tmp.path("broken.mp4")
    try Data("not a movie at all".utf8).write(to: url)
    #expect(QuickTimeMovieHeader.creationDate(of: url) == nil)
}

// MARK: - Copy / move

@Test func copyIntoYearMonthFolders() async throws {
    let tmp = try TempDir()
    let source = try makeJPEG(tmp.path("in/nested/IMG_0001.JPG"), takenAt: "2014:12:06 16:22:00")
    let result = try await Organizer(outputDir: tmp.path("out")).process(source)

    #expect(result.status == .copied)
    #expect(result.destination?.path == tmp.path("out/2014/12/2014-12-06-T-16-22-00.jpg").path)
    #expect(FileManager.default.fileExists(atPath: result.destination!.path))
    #expect(FileManager.default.fileExists(atPath: source.path))
}

@Test func moveRemovesSource() async throws {
    let tmp = try TempDir()
    let source = try makeJPEG(tmp.path("in/a.jpg"), takenAt: "2020:01:02 03:04:05")
    let result = try await Organizer(outputDir: tmp.path("out"), action: .move).process(source)
    #expect(result.status == .moved)
    #expect(!FileManager.default.fileExists(atPath: source.path))
}

@Test func sameSecondDifferentContentGetsSuffix() async throws {
    let tmp = try TempDir()
    let first = try makeJPEG(tmp.path("in/a.jpg"), takenAt: "2014:12:06 16:22:00", color: (1, 0, 0))
    let second = try makeJPEG(tmp.path("in/b.jpg"), takenAt: "2014:12:06 16:22:00", color: (0, 0, 1))
    let organizer = try Organizer(outputDir: tmp.path("out"))

    #expect(await organizer.process(first).destination?.lastPathComponent == "2014-12-06-T-16-22-00.jpg")
    #expect(await organizer.process(second).destination?.lastPathComponent == "2014-12-06-T-16-22-00-1.jpg")
}

@Test(arguments: [true, false])
func identicalFileIsReportedAsDuplicate(dryRun: Bool) async throws {
    let tmp = try TempDir()
    let first = try makeJPEG(tmp.path("in/a.jpg"), takenAt: "2014:12:06 16:22:00")
    let copy = tmp.path("in/copy-of-a.jpg")
    try FileManager.default.copyItem(at: first, to: copy)

    let organizer = try Organizer(outputDir: tmp.path("out"), dryRun: dryRun)
    _ = await organizer.process(first)
    #expect(await organizer.process(copy).status == .duplicate)
}

@Test func dryRunDoesNotTouchDisk() async throws {
    let tmp = try TempDir()
    let source = try makeJPEG(tmp.path("in/a.jpg"), takenAt: "2014:12:06 16:22:00")
    let result = try await Organizer(outputDir: tmp.path("out"), dryRun: true).process(source)
    #expect(result.status == .planned)
    #expect(!FileManager.default.fileExists(atPath: tmp.path("out").path))
}

@Test func noDateIsSkippedWithoutFallback() async throws {
    let tmp = try TempDir()
    let source = try makeJPEG(tmp.path("in/a.jpg"), takenAt: nil)
    let result = try await Organizer(outputDir: tmp.path("out"), useFilesystemFallback: false).process(source)
    #expect(result.status == .noDate)
}

// MARK: - Scanning

@Test func scanIsRecursiveAndSkipsHidden() throws {
    let tmp = try TempDir()
    try makeJPEG(tmp.path("a.jpg"), takenAt: nil)
    try makeJPEG(tmp.path("sub/deeper/b.JPG"), takenAt: nil)
    try Data("x".utf8).write(to: tmp.path(".DS_Store"))
    try FileManager.default.createDirectory(at: tmp.path(".hidden"), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: tmp.path(".hidden/c.jpg"))

    let entries = try FileScanner.scan(tmp.url)
    #expect(entries.map(\.relativePath) == ["a.jpg", "sub/deeper/b.JPG"])
    #expect(Set(entries.map(\.fileExtension)) == ["jpg"])
    #expect(FileScanner.countExtensions(entries) == ["jpg": 2])
}

// MARK: - Delete

@Test func deleteDryRunKeepsFile() async throws {
    let tmp = try TempDir()
    let source = try makeJPEG(tmp.path("a.jpg"), takenAt: nil)
    let result = try await Organizer(outputDir: nil, action: .delete, dryRun: true).process(source)
    #expect(result.status == .planned)
    #expect(FileManager.default.fileExists(atPath: source.path))
}

final class TrashSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [URL] = []
    var items: [URL] { lock.withLock { _items } }
    func record(_ url: URL) { lock.withLock { _items.append(url) } }
}

@Test func deleteMovesToTrashByDefault() async throws {
    let tmp = try TempDir()
    let source = try makeJPEG(tmp.path("a.jpg"), takenAt: nil)
    let spy = TrashSpy()

    let result = try await Organizer(outputDir: nil, action: .delete, trash: { spy.record($0) }).process(source)

    #expect(result.status == .trashed)
    #expect(spy.items == [source])
}

@Test func permanentDeleteRemovesFile() async throws {
    let tmp = try TempDir()
    let source = try makeJPEG(tmp.path("a.jpg"), takenAt: nil)
    let spy = TrashSpy()

    let result = try await Organizer(outputDir: nil, action: .delete, permanentDelete: true, trash: { spy.record($0) })
        .process(source)

    #expect(result.status == .deleted)
    #expect(spy.items.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: source.path))
}

@Test func deleteReportsErrors() async throws {
    let tmp = try TempDir()
    let result = try await Organizer(outputDir: nil, action: .delete, permanentDelete: true).process(tmp.path("missing.jpg"))
    #expect(result.status == .error)
}

@Test func copyRequiresOutputDir() {
    #expect(throws: OrganizerError.outputFolderRequired) {
        try Organizer(outputDir: nil, action: .copy)
    }
}
