import Foundation

enum OfferWindow {
    static var calendar: Calendar {
        var value = Calendar(identifier: .iso8601)
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return value
    }
    static func day(_ text: String) -> Date? {
        let fields = text.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3, text.count == 10, let y = Int(fields[0]), let m = Int(fields[1]), let d = Int(fields[2]),
              let value = calendar.date(from: DateComponents(year: y, month: m, day: d)), key(value) == text else { return nil }
        return value
    }
    static func key(_ value: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: value)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    static func timestamp(_ text: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = format.date(from: text) { return result }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: text)
    }
    static func nextMonday(_ now: Date) -> Date {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        return calendar.date(byAdding: .day, value: 7, to: start)!
    }
    static func end(_ now: Date) -> String { key(calendar.date(byAdding: .day, value: 6, to: nextMonday(now))!) }
    static func visible(_ offer: SignalOffer, at now: Date = Date()) -> Bool {
        offer.validUntil >= key(now) && offer.validFrom <= end(now)
    }
    static func nextWeek(_ offer: SignalOffer, at now: Date = Date()) -> Bool { offer.validFrom >= key(nextMonday(now)) }
}
