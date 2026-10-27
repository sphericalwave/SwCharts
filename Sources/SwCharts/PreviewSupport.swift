#if DEBUG
import Foundation

/// Shared sample data for `#Preview` blocks and the README screenshot
/// generator (`ScreenshotGenTests`), so both render the same content.
/// DEBUG-only: never compiled into release builds of the library.
enum SwChartsSamples {
    private static let reference = Date(timeIntervalSince1970: 1_700_000_000)

    private static func series(_ values: [Double], step: Calendar.Component) -> [ChartPoint] {
        let cal = Calendar(identifier: .gregorian)
        return values.enumerated().map { index, value in
            ChartPoint(start: cal.date(byAdding: step, value: index, to: reference) ?? reference,
                       value: value)
        }
    }

    static let weekly = series([182, 181, 180.4, 179.8, 180.1, 179.2], step: .weekOfYear)
    static let monthly = series([184, 182.5, 181, 180.2, 179.5, 178.9], step: .month)

    static var weightData: PeriodBarChart.DataSet {
        .init(week: weekly, month: monthly)
    }

    static let netCalorieWeekly = series([320, -180, 410, 90, -260, 150], step: .weekOfYear)
    static let netCalorieMonthly = series([200, -90, 340, -150], step: .month)

    static var netCalorieData: PeriodBarChart.DataSet {
        .init(week: netCalorieWeekly, month: netCalorieMonthly)
    }

    /// Fixed "now" for `PeriodChartView` samples, so renders are stable.
    static let now = reference

    /// ~100 days of samples ending at `now`, skipping every 5th day so the
    /// charts show how gaps are handled.
    private static func daily(_ value: (Int) -> Double) -> [DatedSample] {
        let cal = Calendar(identifier: .gregorian)
        return (0..<100).compactMap { daysAgo in
            guard daysAgo % 5 != 3,
                  let date = cal.date(byAdding: .day, value: -daysAgo, to: now) else { return nil }
            return DatedSample(date: date, value: value(daysAgo))
        }
    }

    static let dailyWeight = daily { daysAgo in
        let d = Double(daysAgo)
        let trend: Double = 178 + d * 0.05
        return trend + sin(d / 3) * 0.6
    }
    static let dailyCalories = daily { daysAgo in
        let wave: Double = cos(Double(daysAgo) / 2) * 350
        return 2_300 + wave
    }
}
#endif
