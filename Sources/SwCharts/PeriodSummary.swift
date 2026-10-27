import Foundation

/// Header numbers for a `PeriodChartView`: the average over the visible
/// window, the latest period's value, and its change vs the period before.
/// Pure so it's unit-testable without SwiftUI.
public struct PeriodSummary: Equatable, Sendable {
    /// Mean of the bucket values that have data. For a `.sum` metric a
    /// partial bucket is left out (a half-finished week's total would drag the
    /// average down) unless it's the only bucket with data.
    public let windowAverage: Double?
    /// The newest bucket with data — possibly the partial "so far" one.
    public let latest: PeriodBucket?
    /// The bucket with data immediately before `latest`.
    public let previous: PeriodBucket?
    /// `(latest - previous) / |previous|`, as a fraction (0.12 = +12%).
    /// `nil` when there's nothing to compare, when `previous` is zero, or when
    /// `latest` is a partial `.sum` bucket — a running total vs a finished
    /// one isn't a like-for-like change, and the standard doesn't project.
    public let percentChange: Double?

    public init(buckets: [PeriodBucket], aggregation: MetricAggregation) {
        let withData = buckets.filter { $0.value != nil }

        let averaged = aggregation == .sum && withData.contains(where: { !$0.isPartial })
            ? withData.filter { !$0.isPartial }
            : withData
        windowAverage = MetricAggregation.average.combine(averaged.compactMap(\.value))

        latest = withData.last
        previous = withData.count > 1 ? withData[withData.count - 2] : nil

        if let latest, let previous,
           let now = latest.value, let before = previous.value, before != 0,
           !(aggregation == .sum && latest.isPartial) {
            percentChange = (now - before) / abs(before)
        } else {
            percentChange = nil
        }
    }
}
