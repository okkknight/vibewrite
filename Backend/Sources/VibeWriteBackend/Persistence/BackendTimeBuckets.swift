import Foundation

enum BackendTimeBuckets {
    static let shanghaiTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static func currentDayRange(now: Date, timeZone: TimeZone = shanghaiTimeZone) -> ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        var adjusted = calendar
        adjusted.timeZone = timeZone
        let startOfDay = adjusted.startOfDay(for: now)
        return startOfDay...now
    }

    static func dailyKey(for date: Date, timeZone: TimeZone = shanghaiTimeZone) -> String {
        let calendar = Calendar(identifier: .gregorian)
        var adjusted = calendar
        adjusted.timeZone = timeZone

        let components = adjusted.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func weeklyKey(for date: Date, timeZone: TimeZone = shanghaiTimeZone) -> String {
        let calendar = Calendar(identifier: .gregorian)
        var adjusted = calendar
        adjusted.timeZone = timeZone

        let startOfDay = adjusted.startOfDay(for: date)
        let weekday = adjusted.component(.weekday, from: startOfDay)
        let offset = (weekday + 5) % 7
        guard let monday = adjusted.date(byAdding: .day, value: -offset, to: startOfDay) else {
            return dailyKey(for: date, timeZone: timeZone)
        }

        let components = adjusted.dateComponents([.year, .month, .day], from: monday)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
