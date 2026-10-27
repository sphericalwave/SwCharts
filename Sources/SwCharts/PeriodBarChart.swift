import SwiftUI
import Charts

/// A `Section`-ready bar chart switchable across day/week/month/quarter/year,
/// via a segmented picker. One bar per `ChartPoint`; the day scale plots
/// against real dates (so `chartXAxis` can show narrow weekday letters),
/// the coarser scales plot against short categorical labels (see
/// `PeriodBarLabeler`) since a date string doesn't stay readable once a
/// chart has more than a handful of bars.
///
/// Scales with fewer than `minimumPoints` are hidden from the picker
/// entirely — a single bar has no shape to show.
public struct PeriodBarChart: View {

    /// Data for every scale the chart can switch to. Scales with no data
    /// (or too little to plot) are simply absent from the picker.
    public struct DataSet {
        public var hour: [ChartPoint]
        public var day: [ChartPoint]
        public var week: [ChartPoint]
        public var month: [ChartPoint]
        public var quarter: [ChartPoint]
        public var year: [ChartPoint]

        public init(
            hour: [ChartPoint] = [],
            day: [ChartPoint] = [],
            week: [ChartPoint] = [],
            month: [ChartPoint] = [],
            quarter: [ChartPoint] = [],
            year: [ChartPoint] = []
        ) {
            self.hour = hour
            self.day = day
            self.week = week
            self.month = month
            self.quarter = quarter
            self.year = year
        }

        func points(for scale: ChartTimeframe) -> [ChartPoint] {
            switch scale {
            case .hour:    return hour
            case .day:     return day
            case .week:    return week
            case .month:   return month
            case .quarter: return quarter
            case .year:    return year
            }
        }
    }

    private let data: DataSet
    @Binding private var selection: ChartTimeframe
    private let isLoading: Bool
    private let minimumPoints: Int
    private let emptyTitle: String
    private let emptyMessage: String
    private let title: ((ChartTimeframe) -> String)?
    private let valueLabel: ((Double) -> String)?

    /// How many pages back from the newest page is currently visible.
    /// 0 = newest. Reset to 0 whenever the scale changes.
    @State private var pageOffset: Int = 0

    public init(
        data: DataSet,
        selection: Binding<ChartTimeframe>,
        isLoading: Bool = false,
        minimumPoints: Int = 2,
        emptyTitle: String = "Avg plays",
        emptyMessage: String = "Not enough data yet.",
        title: ((ChartTimeframe) -> String)? = nil,
        valueLabel: ((Double) -> String)? = nil
    ) {
        self.data = data
        self._selection = selection
        self.isLoading = isLoading
        self.minimumPoints = minimumPoints
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.title = title
        self.valueLabel = valueLabel
    }

    private var availableScales: [ChartTimeframe] {
        ChartTimeframe.allCases.filter { data.points(for: $0).count >= minimumPoints }
    }

    public var body: some View {
        let scales = availableScales
        Section {
            if isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 160)
                    Picker("Timeframe", selection: $selection) {
                        ForEach(ChartTimeframe.allCases) { s in
                            Text(s.short).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            } else if scales.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(emptyTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(emptyMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
                .padding(.vertical, 4)
            } else {
                // The persisted selection can outlive its data (e.g. yearly
                // picked, then history trimmed) — fall back to the widest
                // scale still available.
                let scale = scales.contains(selection) ? selection : scales[0]
                let points = data.points(for: scale)
                let pages = ChartPaging.pages(points: points, scale: scale)
                let index = pages.isEmpty ? 0 : pages.count - 1 - min(pageOffset, pages.count - 1)
                let visiblePoints = pages.isEmpty ? [] : pages[index]
                let avg = visiblePoints.isEmpty ? 0 : visiblePoints.reduce(0) { $0 + $1.value } / Double(visiblePoints.count)
                let dateRange = ChartPaging.dateRangeLabel(for: visiblePoints, scale: scale)
                let pageBinding = Binding<Int>(
                    get: { index },
                    set: { newIndex in pageOffset = max(0, min(pages.count - 1, pages.count - 1 - newIndex)) }
                )
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title?(scale) ?? scale.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let dateRange {
                                Text(dateRange)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text(valueLabel?(avg) ?? String(format: "avg %.1f", avg))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    TabView(selection: pageBinding) {
                        ForEach(pages.indices, id: \.self) { i in
                            chart(points: pages[i], scale: scale, maxValue: max(pages[i].map(\.value).max() ?? 0, 1))
                                .tag(i)
                        }
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    #endif
                    .frame(height: 160)
                    .onChange(of: scale) { pageOffset = 0 }
                    Picker("Timeframe", selection: $selection) {
                        ForEach(scales) { s in
                            Text(s.short).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func chart(points: [ChartPoint], scale: ChartTimeframe, maxValue: Double) -> some View {
        if scale == .day {
            Chart(points, id: \.start) { p in
                BarMark(x: .value("Day", p.start, unit: .day), y: .value("Value", p.value))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: 160)
            .chartYScale(domain: 0...maxValue * 1.15)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .clipped()
        } else {
            Chart(Array(points.enumerated()), id: \.offset) { index, p in
                let label = PeriodBarLabeler.label(for: p, index: index, scale: scale)
                BarMark(x: .value("Period", label), y: .value("Value", p.value))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: 160)
            .chartYScale(domain: 0...maxValue * 1.15)
            .clipped()
        }
    }
}

#if DEBUG
#Preview("PeriodBarChart") {
    Form {
        PeriodBarChart(data: SwChartsSamples.weightData, selection: .constant(.week))
    }
}
#endif
