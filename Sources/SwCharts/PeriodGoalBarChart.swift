import SwiftUI
import Charts

/// A `Section`-ready bar chart switchable across day/week/month/quarter/year
/// (via a segmented picker) with an optional glowing "Goal" bar and a padded,
/// non-zero y-domain — the presentation body-composition metrics want, where
/// values cluster in a narrow band and a `0…max` axis flattens every bar to the
/// same height.
///
/// Unlike `PeriodBarChart` (which plots the day scale against real dates), every
/// scale here uses a short categorical label. That's what lets a trailing "Goal"
/// bar sit alongside the data bars on any scale.
///
/// Scales with fewer than `minimumPoints` points are hidden from the picker.
/// Pass `offeredScales` to keep a scale out of the picker entirely — even when
/// there's data for it, and while loading.
///
/// Renders plain content (no `Section` wrapper) so the host decides the
/// container — drop it in a `Section` inside a `Form`, or in a custom card row.
public struct PeriodGoalBarChart: View {

    /// Reuses `PeriodBarChart`'s per-scale point container.
    public typealias DataSet = PeriodBarChart.DataSet

    private let data: DataSet
    @Binding private var selection: ChartTimeframe
    private let goal: Double?
    private let title: String
    private let barColor: Color
    private let goalLabel: String
    private let valueSpecifier: String
    private let isLoading: Bool
    private let minimumPoints: Int
    private let emptyTitle: String
    private let emptyMessage: String
    private let showsScalePicker: Bool
    private let offeredScales: [ChartTimeframe]

    @State private var selectedLabel: String?

    /// How many pages back from the newest page is currently visible.
    /// 0 = newest. Reset to 0 whenever the scale changes.
    @State private var pageOffset: Int = 0

    public init(
        data: DataSet,
        selection: Binding<ChartTimeframe>,
        goal: Double? = nil,
        title: String,
        barColor: Color = .accentColor,
        goalLabel: String = "Goal",
        valueSpecifier: String = "%.1f",
        isLoading: Bool = false,
        minimumPoints: Int = 2,
        emptyTitle: String = "No data",
        emptyMessage: String = "Not enough data yet.",
        showsScalePicker: Bool = true,
        offeredScales: [ChartTimeframe] = ChartTimeframe.allCases
    ) {
        self.data = data
        self._selection = selection
        self.goal = goal
        self.title = title
        self.barColor = barColor
        self.goalLabel = goalLabel
        self.valueSpecifier = valueSpecifier
        self.isLoading = isLoading
        self.minimumPoints = minimumPoints
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.showsScalePicker = showsScalePicker
        self.offeredScales = offeredScales
    }

    private var availableScales: [ChartTimeframe] {
        Self.availableScales(data: data, offered: offeredScales, minimumPoints: minimumPoints)
    }

    /// The offered scales with enough points to plot, in timeframe order.
    /// Pure so it's unit-testable.
    static func availableScales(data: DataSet, offered: [ChartTimeframe], minimumPoints: Int) -> [ChartTimeframe] {
        ChartTimeframe.allCases.filter {
            offered.contains($0) && data.points(for: $0).count >= minimumPoints
        }
    }

    /// Padded domain around the data (and goal, if any). Pure so it's unit-testable.
    /// Clamped at 0 when the data itself is non-negative (weight, waist, body-fat) —
    /// prevents a stray negative axis after padding. Left unclamped when the data
    /// is genuinely negative (e.g. assisted/negative-load sets), since clamping a
    /// negative-only range to 0 would invert lowerBound above upperBound.
    static func paddedDomain(points: [ChartPoint], goal: Double?) -> ClosedRange<Double> {
        var values = points.map(\.value)
        if let goal { values.append(goal) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        if lo == hi {
            let pad = Swift.max(1, abs(lo) * 0.1)
            let lower = lo >= 0 ? Swift.max(0, lo - pad) : lo - pad
            return lower...(hi + pad)
        }
        let pad = Swift.max(1, (hi - lo) * 0.15)
        let lower = lo >= 0 ? Swift.max(0, lo - pad) : lo - pad
        return lower...(hi + pad)
    }

    /// Categorical x label for a bar. Day gets a short "M/d" (PeriodBarLabeler
    /// intentionally leaves day blank, since PeriodBarChart labels it off the axis).
    static func label(for point: ChartPoint, index: Int, scale: ChartTimeframe) -> String {
        guard scale == .day else {
            return PeriodBarLabeler.label(for: point, index: index, scale: scale)
        }
        return dayFormatter.string(from: point.start)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

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
            picker(scales: ChartTimeframe.allCases.filter(offeredScales.contains))
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
            TimelineView(.animation) { context in
                TabView(selection: pageBinding) {
                    ForEach(pages.indices, id: \.self) { i in
                        chart(points: pages[i], scale: scale, glow: glowIntensity(at: context.date))
                            .tag(i)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .frame(height: 160)
            }
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
    private func chart(points: [ChartPoint], scale: ChartTimeframe, glow: Double) -> some View {
        let domain = Self.paddedDomain(points: points, goal: goal)
        Chart {
            // Bars start at the domain floor, not 0. With a non-zero y-domain a
            // plain `y:` BarMark still draws from 0 — far below the plot — and
            // that overflow isn't always clipped by the host container (a `List`
            // row lets it bleed over the picker and axis labels). Anchoring at
            // `domain.lowerBound` keeps every bar inside the plot.
            ForEach(Array(points.enumerated()), id: \.offset) { index, p in
                let label = Self.label(for: p, index: index, scale: scale)
                BarMark(
                    x: .value("Period", label),
                    yStart: .value("Floor", domain.lowerBound),
                    yEnd: .value("Value", p.value)
                )
                    .foregroundStyle(selectedLabel == label ? Color.primary : barColor)
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        if selectedLabel == label {
                            Text("\(p.value, specifier: valueSpecifier)")
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundStyle(.primary)
                        }
                    }
            }
            if let goal {
                BarMark(
                    x: .value("Period", goalLabel),
                    yStart: .value("Floor", domain.lowerBound),
                    yEnd: .value("Value", goal)
                )
                    .foregroundStyle(Color.primary)
                    .goalGlow(intensity: glow)
                    .annotation(position: .top) {
                        Text("\(goal, specifier: valueSpecifier)")
                            .font(.caption2)
                            .foregroundStyle(.primary)
                    }
            }
        }
        .frame(height: 160)
        .chartYScale(domain: domain)
        .chartXSelection(value: $selectedLabel)
    }

    /// Hidden when the host drives the scale from elsewhere — a single control
    /// above a stack of charts, say, rather than one picker per chart.
    @ViewBuilder
    private func picker(scales: [ChartTimeframe]) -> some View {
        if showsScalePicker {
            Picker("Timeframe", selection: $selection) {
                ForEach(scales) { s in
                    Text(s.short).tag(s)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// 0…1 pulse driving the goal bar's glow.
    private func glowIntensity(at date: Date) -> Double {
        let cycleDuration = 2.4
        let phase = (date.timeIntervalSinceReferenceDate / cycleDuration) * (2.0 * Double.pi)
        return (sin(phase) + 1.0) / 2.0
    }
}

private extension ChartContent {
    func goalGlow(intensity: Double) -> some ChartContent {
        let clamped = Swift.min(1.0, Swift.max(0.0, intensity))
        let opacity = 0.75 + (0.25 * clamped)
        let shadowOpacity = 0.4 + (0.5 * clamped)
        let radius = 2.0 + (4.0 * clamped)
        return self
            .opacity(opacity)
            .shadow(color: Color.primary.opacity(shadowOpacity), radius: radius)
    }
}

#if DEBUG
#Preview("PeriodGoalBarChart") {
    Form {
        Section {
            PeriodGoalBarChart(
                data: SwChartsSamples.weightData,
                selection: .constant(.month),
                goal: 178,
                title: "Weight (lbs)",
                barColor: .green
            )
        }
    }
}
#endif
