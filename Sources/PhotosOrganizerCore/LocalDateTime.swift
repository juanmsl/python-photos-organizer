import Foundation

/// A wall-clock date and time with no time zone, like an EXIF `DateTimeOriginal`.
///
/// Names and folders are built from these components directly, so a photo taken at 16:22 on the
/// camera's clock is always named `…-T-16-22-00`, whatever the computer's time zone or DST rules.
public struct LocalDateTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var second: Int

    /// Returns `nil` for impossible dates such as `2014-02-30` or `0000-00-00`.
    public init?(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) {
        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        components.calendar = Self.gregorian
        components.timeZone = Self.gregorian.timeZone
        guard year >= 1, components.isValidDate else { return nil }
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    /// The wall-clock time of `date` in `timeZone` (the computer's zone by default).
    public init(_ date: Date, in timeZone: TimeZone = .current) {
        var calendar = Self.gregorian
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        year = parts.year!
        month = parts.month!
        day = parts.day!
        hour = parts.hour!
        minute = parts.minute!
        second = parts.second!
    }

    /// `2014-12-06-T-16-22-00`
    public var fileStem: String {
        String(format: "%04d-%02d-%02d-T-%02d-%02d-%02d", year, month, day, hour, minute, second)
    }

    /// `2014-12-06 16:22:00`
    public var description: String {
        String(format: "%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day, lhs.hour, lhs.minute, lhs.second)
            < (rhs.year, rhs.month, rhs.day, rhs.hour, rhs.minute, rhs.second)
    }

    private static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
