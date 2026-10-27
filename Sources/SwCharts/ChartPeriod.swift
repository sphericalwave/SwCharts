import Foundation

/// The standard Day/Week/Month period for a stats chart. Each period shows a
/// fixed trailing window: the last 28 days as daily points, the last 12 weeks
/// as weekly buckets, or the last 12 months as monthly buckets.
///
/// Raw values are stable — hosts persisting the selection (e.g. via
/// `@AppStorage`) can rely on them.
public enum ChartPeriod: String, CaseIterable, Identifiable, Equatable, Sendable {
    case day, week, month

    public var id: String { rawValue }

    /// Segmented-picker label.
    public var short: String {
        switch self {
        case .day:   return "D"
        case .week:  return "W"
        case .month: return "M"
        }
    }

    /// Number of buckets in the visible window.
    public var bucketCount: Int {
        switch self {
        case .day:   return 28
        case .week:  return 12
        case .month: return 12
        }
    }

    /// The calendar unit one bucket spans.
    public var component: Calendar.Component {
        switch self {
        case .day:   return .day
        case .week:  return .weekOfYear
        case .month: return .month
        }
    }

    /// "Daily" / "Weekly" / "Monthly" — prefixes the aggregation label
    /// ("Weekly total", "Daily avg").
    public var adjective: String {
        switch self {
        case .day:   return "Daily"
        case .week:  return "Weekly"
        case .month: return "Monthly"
        }
    }

    /// The visible window in words, e.g. "last 12 weeks".
    public var windowDescription: String {
        switch self {
        case .day:   return "last 28 days"
        case .week:  return "last 12 weeks"
        case .month: return "last 12 months"
        }
    }

    /// What the bucket containing "now" is called in the header.
    public var currentLabel: String {
        switch self {
        case .day:   return "Today"
        case .week:  return "This week"
        case .month: return "This month"
        }
    }
}

/// How a metric's samples combine into a bucket. Declared once per metric:
/// `.sum` for things that accumulate (calories, reps, sessions, minutes),
/// `.average` for levels (heart rate, score, %, weight), `.max` / `.min` for
/// bests (heaviest set, peak or lowest heart rate).
public enum MetricAggregation: String, CaseIterable, Equatable, Sendable {
    case sum, average, max, min

    /// Chart label: "total", "avg", "max" or "min".
    public var label: String {
        switch self {
        case .sum:     return "total"
        case .average: return "avg"
        case .max:     return "max"
        case .min:     return "min"
        }
    }

    /// Combines values with this rule. `nil` for an empty input — no data is
    /// not the same as zero.
    public func combine(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        switch self {
        case .sum:     return values.reduce(0, +)
        case .average: return values.reduce(0, +) / Double(values.count)
        case .max:     return values.max()
        case .min:     return values.min()
        }
    }
}
