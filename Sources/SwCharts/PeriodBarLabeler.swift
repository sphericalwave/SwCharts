import Foundation

/// Bar-axis label formatting for `PeriodBarChart`'s non-day scales, split out
/// as pure functions so it's unit-testable without SwiftUI.
enum PeriodBarLabeler {
    /// `.day` isn't handled here — its bars key off the real `Date` and get
    /// their axis labels from `chartXAxis`, not this categorical label.
    ///
    /// Month and quarter labels drop the year except at a year boundary (the
    /// first bar, or the first period of a new year) — repeating it on every
    /// bar just crowds out the categorical axis without adding information.
    static func label(for point: ChartPoint, index: Int, scale: ChartTimeframe) -> String {
        let cal = Calendar.current
        switch scale {
        case .hour:
            let f = DateFormatter()
            f.dateFormat = "ha"
            return f.string(from: point.start)
        case .day:
            return ""
        case .week:
            let f = DateFormatter()
            f.dateFormat = "M/d"
            return f.string(from: point.start)
        case .month:
            let f = DateFormatter()
            f.dateFormat = "MMM"
            let month = f.string(from: point.start)
            let isYearStart = index == 0 || cal.component(.month, from: point.start) == 1
            return isYearStart ? "\(month) '\(shortYear(point.start, cal))" : month
        case .quarter:
            let q = (cal.component(.month, from: point.start) - 1) / 3 + 1
            let isYearStart = index == 0 || q == 1
            return isYearStart ? "Q\(q) '\(shortYear(point.start, cal))" : "Q\(q)"
        case .year:
            let f = DateFormatter()
            f.dateFormat = "yyyy"
            return f.string(from: point.start)
        }
    }

    private static func shortYear(_ date: Date, _ calendar: Calendar) -> String {
        String(format: "%02d", calendar.component(.year, from: date) % 100)
    }
}
