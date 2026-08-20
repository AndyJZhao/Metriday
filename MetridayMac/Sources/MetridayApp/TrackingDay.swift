import Foundation

/// Timing-style logical workday boundaries.
///
/// A selected date is the civil date on which the logical day starts. When a
/// day wraps at e.g. 05:00, the logical day labelled 2026-08-20 runs from
/// 05:00 on the 20th through 04:59:59 on the 21st. Activity segments keep a
/// stable 0...24h axis relative to that boundary.
enum TrackingDay {
    static let secondsPerDay = 24 * 60 * 60

    static func clampedWrapMinute(_ minute: Int) -> Int {
        min(1_439, max(0, minute))
    }

    static func logicalDayLabel(
        for date: Date,
        wrapAtMinute rawWrapAtMinute: Int,
        calendar: Calendar = .current
    ) -> Date {
        let wrapAtMinute = clampedWrapMinute(rawWrapAtMinute)
        let civilDay = calendar.startOfDay(for: date)
        guard wrapAtMinute > 0 else { return civilDay }
        let wallMinute = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        guard wallMinute < wrapAtMinute else { return civilDay }
        return calendar.date(byAdding: .day, value: -1, to: civilDay) ?? civilDay
    }

    static func startDate(
        for logicalDayLabel: Date,
        wrapAtMinute rawWrapAtMinute: Int,
        calendar: Calendar = .current
    ) -> Date {
        let civilDay = calendar.startOfDay(for: logicalDayLabel)
        let wrapAtMinute = clampedWrapMinute(rawWrapAtMinute)
        return calendar.date(byAdding: .minute, value: wrapAtMinute, to: civilDay) ?? civilDay
    }

    static func endDate(
        for logicalDayLabel: Date,
        wrapAtMinute: Int,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(
            byAdding: .day,
            value: 1,
            to: startDate(for: logicalDayLabel, wrapAtMinute: wrapAtMinute, calendar: calendar)
        ) ?? startDate(for: logicalDayLabel, wrapAtMinute: wrapAtMinute, calendar: calendar)
    }

    static func range(
        for logicalDayLabel: Date,
        wrapAtMinute: Int,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let start = startDate(for: logicalDayLabel, wrapAtMinute: wrapAtMinute, calendar: calendar)
        return (start, endDate(for: logicalDayLabel, wrapAtMinute: wrapAtMinute, calendar: calendar))
    }

    static func axisSeconds(
        for date: Date,
        logicalDayLabel: Date,
        wrapAtMinute rawWrapAtMinute: Int,
        calendar: Calendar = .current
    ) -> Int {
        let wrapAtMinute = clampedWrapMinute(rawWrapAtMinute)
        let logicalStart = calendar.startOfDay(for: logicalDayLabel)
        let civilDate = calendar.startOfDay(for: date)
        let dayOffset = calendar.dateComponents([.day], from: logicalStart, to: civilDate).day ?? 0
        let wallSeconds = calendar.component(.hour, from: date) * 60 * 60
            + calendar.component(.minute, from: date) * 60
            + calendar.component(.second, from: date)
        let value = dayOffset * secondsPerDay + wallSeconds - wrapAtMinute * 60
        return min(secondsPerDay, max(0, value))
    }

    static func date(
        forAxisSeconds rawSeconds: Int,
        logicalDayLabel: Date,
        wrapAtMinute rawWrapAtMinute: Int,
        calendar: Calendar = .current
    ) -> Date {
        let seconds = min(secondsPerDay, max(0, rawSeconds))
        let start = startDate(
            for: logicalDayLabel,
            wrapAtMinute: rawWrapAtMinute,
            calendar: calendar
        )
        return start.addingTimeInterval(TimeInterval(seconds))
    }

    static func wallSecond(
        forAxisSeconds rawSeconds: Int,
        wrapAtMinute rawWrapAtMinute: Int
    ) -> (civilDayOffset: Int, second: Int) {
        let wrapAtMinute = clampedWrapMinute(rawWrapAtMinute)
        let absolute = wrapAtMinute * 60 + min(secondsPerDay, max(0, rawSeconds))
        if absolute >= secondsPerDay {
            return (1, absolute - secondsPerDay)
        }
        return (0, absolute)
    }
}
