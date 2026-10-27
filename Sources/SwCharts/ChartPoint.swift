import Foundation

/// One bar's worth of data: when its bucket starts, and the value to plot.
/// For `.day` buckets, `value` is typically a raw count; for coarser
/// buckets it's typically a per-day average — `PeriodBarChart` doesn't care
/// which, it just plots and averages whatever it's given.
public struct ChartPoint: Equatable, Sendable {
    public let start: Date
    public let value: Double

    public init(start: Date, value: Double) {
        self.start = start
        self.value = value
    }
}
