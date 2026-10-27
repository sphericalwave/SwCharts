import SwiftUI
import Charts

/// A `Section`-ready-host bar chart switchable across day/week/month/quarter/year
/// (via a segmented picker) for signed values that diverge around zero — a net
/// balance rather than a magnitude. Unlike `PeriodGoalBarChart`, the y-domain is
/// never clamped at 0: it always spans both above and below zero so a value that's
/// currently all-positive (or all-negative) still shows the zero baseline it could
/// cross. Bars grow up from zero for positive values, down from zero for negative
/// ones, colored `positiveColor`/`negativeColor` respectively.
///
/// Every scale uses a short categorical label, same as `PeriodGoalBarChart`.
///
/// Scales with fewer than `minimumPoints` points are hidden from the picker.
///
/// Renders plain content (no `Section` wrapper) so the host decides the
/// container — drop it in a `Section` inside a `Form`, or in a custom card row.
public struct NetPeriodBarChart: View {

    /// Reuses `PeriodBarChart`'s per-scale point container.
    public typealias DataSet = PeriodBarChart.DataSet

    private let data: DataSet
    @Binding private var selection: ChartTimeframe
    private let title: String
    private let positiveColor: Color
    private let negativeColor: Color
    private let valueSpecifier: String
    private let isLoading: Bool
    private let minimumPoints: Int
    private let emptyTitle: String
    private let emptyMessage: String

    @State private var selectedLabel: String?

    /// How many pages back from the newest page is currently visible.
    /// 0 = newest. Reset to 0 whenever the scale changes.
    @State private var pageOffset: Int = 0

    public init(
        data: DataSet,
        selection: Binding<ChartTimeframe>,
        title: String,
        positiveColor: Color = .blue,
        negativeColor: Color = .red,
        valueSpecifier: String = "%.1f",
        isLoading: Bool = false,
        minimumPoints: Int = 2,
        emptyTitle: String = "No data",
        emptyMessage: String = "Not enough data yet."
    ) {
        self.data = data
        self._selection = selection
        self.title = title
        self.positiveColor = positiveColor
        self.negativeColor = negativeColor
        self.valueSpecifier = valueSpecifier
        self.isLoading = isLoading
        self.minimumPoints = minimumPoints
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
    }

    private var availableScales: [ChartTimeframe] {
        ChartTimeframe.allCases.filter { data.points(for: $0).count >= minimumPoints }
    }

    /// Padded domain around the data, always spanning zero. Pure so it's
    /// unit-testable. Unlike `PeriodGoalBarChart.paddedDomain`, the lower bound
    /// is never clamped at 0 — these values are signed and can go negative.
    static func paddedDomain(points: [ChartPoint]) -> ClosedRange<Double> {
        var values = points.map(\.value)
        values.append(0)
        guard let lo = values.min(), let hi = values.max() else { return -1...1 }
        if lo == hi {
            let pad = Swift.max(1, abs(lo) * 0.1)
            return (lo - pad)...(hi + pad)
        }
        let pad = Swift.max(1, (hi - lo) * 0.15)
        return (lo - pad)...(hi + pad)
    }

    public var body: some View {
        let scales = availableScales
        Group {
            if isLoading {
                loadingBody
            } else if scales.isEmpty {
                emptyBody
            } else {
                // A persisted selection can outlive its data — fall back to the
                // widest scale still available.
                let scale = scales.contains(selection) ? selection : scales[0]
                let points = data.points(for: scale)
                loadedBody(points: points, scale: scale, scales: scales)
            }
        }
    }

    private var loadingBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
            picker(scales: ChartTimeframe.allCases)
        }
        .padding(.vertical, 4)
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
        .padding(.vertical, 4)
    }

    private func loadedBody(points: [ChartPoint], scale: ChartTimeframe, scales: [ChartTimeframe]) -> some View {
        let pages = ChartPaging.pages(points: points, scale: scale)
        let index = pages.isEmpty ? 0 : pages.count - 1 - min(pageOffset, pages.count - 1)
        let visiblePoints = pages.isEmpty ? [] : pages[index]
        let avg = visiblePoints.isEmpty ? 0 : visiblePoints.reduce(0) { $0 + $1.value } / Double(visiblePoints.count)
        let dateRange = ChartPaging.dateRangeLabel(for: visiblePoints, scale: scale)
        let pageBinding = Binding<Int>(
            get: { index },
            set: { newIndex in pageOffset = max(0, min(pages.count - 1, pages.count - 1 - newIndex)) }
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let dateRange {
                        Text(dateRange)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text("avg \(avg, specifier: valueSpecifier)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            TabView(selection: pageBinding) {
                ForEach(pages.indices, id: \.self) { i in
                    chart(points: pages[i], scale: scale)
                        .tag(i)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .frame(height: 160)
            .onChange(of: scale) {
                pageOffset = 0
                selectedLabel = nil
            }
            picker(scales: scales)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func chart(points: [ChartPoint], scale: ChartTimeframe) -> some View {
        let domain = Self.paddedDomain(points: points)
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { index, p in
                let label = PeriodGoalBarChart.label(for: p, index: index, scale: scale)
                BarMark(
                    x: .value("Period", label),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Value", p.value)
                )
                    .foregroundStyle(selectedLabel == label ? Color.primary : (p.value >= 0 ? positiveColor : negativeColor))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        if selectedLabel == label {
                            Text("\(p.value, specifier: valueSpecifier)")
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundStyle(.primary)
                        }
                    }
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .frame(height: 160)
        .chartYScale(domain: domain)
        .chartXSelection(value: $selectedLabel)
    }

    private func picker(scales: [ChartTimeframe]) -> some View {
        Picker("Timeframe", selection: $selection) {
            ForEach(scales) { s in
                Text(s.short).tag(s)
            }
        }
        .pickerStyle(.segmented)
    }
}

#if DEBUG
#Preview("NetPeriodBarChart") {
    Form {
        Section {
            NetPeriodBarChart(
                data: SwChartsSamples.netCalorieData,
                selection: .constant(.week),
                title: "Net Calories"
            )
        }
    }
}
#endif
