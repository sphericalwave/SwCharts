import Foundation

/// Windowed-paging support for `PeriodBarChart` / `NetPeriodBarChart` —
/// chunks a scale's full point history into fixed-size pages (mirroring
/// Apple Health's per-scale windows) so charts can swipe through history
/// instead of plotting everything at once. Split out as pure functions so
/// it's unit-testable without SwiftUI.
enum ChartPaging {
    /// Bars per page, per scale — mirrors Health app windows (day view =
    /// 24 hourly bars, week = 7 daily bars, ~month = 4 weekly bars, year =
    /// 12 monthly bars, ~year = 4 quarterly bars). `nil` means unpaged —
    /// the whole array renders as a single page (used for `.year`).
    static func pageSize(for scale: ChartTimeframe) -> Int? {
        switch scale {
        case .hour:    return 24
        case .day:     return 7
        case .week:    return 4
        case .month:   return 12
        case .quarter: return 4
        case .year:    return nil
        }
    }

    /// Chunks `points` (ascending by `start`) into pages of `pageSize`,
    /// anchored to the newest end — the last page is always full-sized
    /// (or the only page), any leftover older points form a shorter first
    /// page. `nil` pageSize or a short array yields a single page.
    static func pages(points: [ChartPoint], scale: ChartTimeframe) -> [[ChartPoint]] {
        guard points.isEmpty == false else { return [] }
        guard let pageSize = pageSize(for: scale), points.count > pageSize else {
            return [points]
        }
        var result: [[ChartPoint]] = []
        var idx = points.count
        while idx > 0 {
            let start = Swift.max(0, idx - pageSize)
            result.insert(Array(points[start..<idx]), at: 0)
            idx = start
        }
        return result
    }

    /// Date-range subtitle for a visible page, e.g. "Aug 18 – 24" or,
    /// for a single-day span (typically `.hour`), just "Aug 24".
    static func dateRangeLabel(for points: [ChartPoint], scale: ChartTimeframe) -> String? {
        guard let first = points.first?.start, let last = points.last?.start else { return nil }
        if scale == .hour || Calendar.current.isDate(first, inSameDayAs: last) {
            return first.formatted(.dateTime.month(.abbreviated).day())
        }
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: first, to: last)
    }
}
