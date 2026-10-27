import Foundation

/// An optional target for a `PeriodChartView`: drawn as a dashed line across
/// each bucket, and each bucket's mark is tinted by whether it hit the goal.
///
/// For a `.sum` metric `value` is a **daily** goal and scales with the bucket:
/// ×1 for a day, ×7 for a week, × the month's length for a month (2.5 L of
/// water a day → 17.5 L a week). For `.average`, `.max` and `.min` metrics
/// it's a level and applies to every bucket as-is (a 100% score, a 225 lb
/// lift, a resting HR under 60).
public struct PeriodGoal: Equatable, Sendable {

    /// Which side of the goal counts as a hit.
    public enum Direction: Sendable {
        /// Reaching the goal or going over is a hit (water, steps, % of target).
        case atLeast
        /// Staying at or under the goal is a hit (calories, resting HR).
        case atMost
    }

    public enum Outcome: Equatable, Sendable {
        case hit, miss
    }

    public let value: Double
    public let direction: Direction

    public init(_ value: Double, direction: Direction = .atLeast) {
        self.value = value
        self.direction = direction
    }

    /// The goal for `bucket`: scaled by its length in days for a `.sum`
    /// metric, unchanged otherwise. Day counts come from calendar arithmetic,
    /// so DST weeks and 28–31-day months scale correctly.
    public func target(for bucket: PeriodBucket, aggregation: MetricAggregation,
                       calendar: Calendar) -> Double {
        guard aggregation == .sum else { return value }
        let days = calendar.dateComponents([.day], from: bucket.start, to: bucket.end).day ?? 1
        return value * Double(Swift.max(days, 1))
    }

    /// Hit or miss for `bucket`, or `nil` when it has no data or the outcome
    /// isn't decided yet. A partial `.sum` bucket can still climb, so it only
    /// counts once it's already met an `.atLeast` goal (a hit) or broken an
    /// `.atMost` one (a miss). A partial `.max` / `.min` bucket only moves one
    /// way too, so it gets the same treatment. Partial `.average` buckets are
    /// judged on their value so far.
    public func outcome(for bucket: PeriodBucket, aggregation: MetricAggregation,
                        calendar: Calendar) -> Outcome? {
        guard let actual = bucket.value else { return nil }
        let goal = target(for: bucket, aggregation: aggregation, calendar: calendar)
        let meets = direction == .atLeast ? actual >= goal : actual <= goal
        guard bucket.isPartial, aggregation != .average else { return meets ? .hit : .miss }
        // Which way the running value can still move.
        let canStillReach: Bool
        switch (aggregation, direction) {
        case (.sum, .atLeast), (.max, .atLeast): canStillReach = !meets   // can rise to the goal
        case (.sum, .atMost), (.max, .atMost):   return meets ? nil : .miss // only rises: a break is final
        case (.min, .atMost):                    canStillReach = !meets   // can fall to the goal
        case (.min, .atLeast):                   return meets ? nil : .miss // only falls
        case (.average, _):                      canStillReach = false
        }
        return canStillReach ? nil : .hit
    }
}
