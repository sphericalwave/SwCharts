import SwiftUI

/// GitHub-style calendar heatmap: one column per week, seven rows, oldest
/// column left. Renders plain content (no `Section` wrapper) so the host
/// decides the container and supplies its own header/footer.
///
/// `opacity` is the caller's per-day intensity, already resolved to 0...1 —
/// this view just lays out the grid and fills each cell, the same way
/// `PeriodBarChart` takes pre-computed `ChartPoint.value` rather than raw data.
public struct CalendarHeatmap: View {
    private let weeks: Int
    private let color: Color
    private let cellSize: CGFloat
    private let spacing: CGFloat
    private let today: Date
    private let opacity: (Date) -> Double
    /// Internal-only escape hatch for `ScreenshotGenTests`: `ImageRenderer`
    /// can't capture `ScrollView` content offscreen (it stays blank), so the
    /// snapshot renders the same grid without the scroll container.
    private let scrollable: Bool

    public init(
        weeks: Int,
        color: Color = .accentColor,
        cellSize: CGFloat = 12,
        spacing: CGFloat = 3,
        today: Date = Date(),
        opacity: @escaping (Date) -> Double
    ) {
        self.init(weeks: weeks, color: color, cellSize: cellSize, spacing: spacing,
                   today: today, scrollable: true, opacity: opacity)
    }

    init(
        weeks: Int,
        color: Color = .accentColor,
        cellSize: CGFloat = 12,
        spacing: CGFloat = 3,
        today: Date = Date(),
        scrollable: Bool,
        opacity: @escaping (Date) -> Double
    ) {
        self.weeks = weeks
        self.color = color
        self.cellSize = cellSize
        self.spacing = spacing
        self.today = today
        self.scrollable = scrollable
        self.opacity = opacity
    }

    public var body: some View {
        let days = Self.days(weeks: weeks, today: today)
        let columns = stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }

        let grid = HStack(alignment: .top, spacing: spacing) {
            ForEach(columns.indices, id: \.self) { index in
                VStack(spacing: spacing) {
                    ForEach(columns[index], id: \.self) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(opacity(day)))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
        .padding(.vertical, 4)

        // ScrollView proposes a flexible height; without a concrete frame it
        // collapses to zero in contexts that don't force one (e.g. offscreen
        // rendering for the README screenshots).
        return Group {
            if scrollable {
                ScrollView(.horizontal, showsIndicators: false) { grid }
            } else {
                grid
            }
        }
        .frame(height: 7 * cellSize + 6 * spacing + 8)
    }

    /// Trailing `weeks` weeks of days, oldest first, padded so the grid
    /// starts on a week boundary.
    static func days(weeks: Int, today: Date) -> [Date] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: today)
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: startOfToday)?.start,
              let firstDay = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: weekStart)
        else { return [] }

        let span = (calendar.dateComponents([.day], from: firstDay, to: startOfToday).day ?? 0) + 1
        return (0..<span).compactMap { calendar.date(byAdding: .day, value: $0, to: firstDay) }
    }
}

#if DEBUG
#Preview("CalendarHeatmap") {
    Form {
        Section {
            CalendarHeatmap(weeks: 17) { day in
                Double.random(in: 0...1)
            }
        } header: {
            Text("Last 17 weeks")
        }
    }
}
#endif
