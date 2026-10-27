import Foundation

/// A timeframe a `PeriodBarChart` can be switched to. Raw values are stable —
/// hosts persisting the selection (e.g. via `@AppStorage`) can rely on them.
public enum ChartTimeframe: String, CaseIterable, Identifiable, Equatable, Sendable {
    case hour, day, week, month, quarter, year

    public var id: String { rawValue }

    /// Segmented-picker label.
    public var short: String {
        switch self {
        case .hour:    return "H"
        case .day:     return "D"
        case .week:    return "W"
        case .month:   return "M"
        case .quarter: return "Q"
        case .year:    return "Y"
        }
    }

    /// Generic per-scale heading. Hosts wanting different phrasing can
    /// ignore this and supply their own — nothing else depends on it.
    public var title: String {
        switch self {
        case .hour:    return "Hourly plays"
        case .day:     return "Daily plays"
        case .week:    return "Weekly avg plays"
        case .month:   return "Monthly avg plays"
        case .quarter: return "Quarterly avg plays"
        case .year:    return "Yearly avg plays"
        }
    }
}
