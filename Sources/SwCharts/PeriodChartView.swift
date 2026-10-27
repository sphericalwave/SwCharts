import SwiftUI
import Charts

/// The standard Day/Week/Month stats chart. Feed it raw dated samples, the
/// selected `ChartPeriod` and the metric's `MetricAggregation`; it buckets
/// them with `PeriodBucketer` (28 days / 12 Monday-start weeks / 12 months),
/// and shows:
///
/// - a header with the title, "Weekly total" / "Daily avg" and the window,
///   the average over the visible window, and the latest period's value with
///   its % change vs the period before (`PeriodSummary`);
/// - the buckets as a trend-colored line (`.line`, the `SlopeColoredLineChart`
///   look) or bars (`.bar`), with a dashed rule at the window average;
/// - the current, unfinished week or month faded and labelled "so far";
/// - drag-to-read: slide a finger across the chart and the header shows the
///   bucket under it. The selection stays after the finger lifts;
/// - optionally a `bucketDetail` line naming what a bucket's value came
///   from (the lift behind a weekly max), in the header and on the selected
///   point;
/// - optionally a `PeriodGoal`: a dashed goal line across each bucket (scaled
///   per period for `.sum` metrics) and each bar/point tinted hit or miss.
///
/// Empty buckets are gaps, not zeros. Pair it with a `PeriodPicker` in the
/// navigation bar's principal slot. Renders plain content — wrap it in your
/// own `Section` or card.
public struct PeriodChartView: View {

    /// How buckets are drawn. `.line` suits levels (weight, HR, score) — its
    /// y-axis is padded around the data instead of starting at zero. `.bar`
    /// suits totals (calories, minutes) and starts at zero.
    public enum Style: Sendable {
        case line, bar
    }

    private let title: String
    private let period: ChartPeriod
    private let aggregation: MetricAggregation
    private let style: Style
    private let buckets: [PeriodBucket]
    private let summary: PeriodSummary
    private let calendar: Calendar
    private let valueLabel: (Double) -> String
    private let risingColor: Color
    private let fallingColor: Color
    private let barColor: Color
    private let goal: PeriodGoal?
    private let hitColor: Color
    private let missColor: Color
    private let height: CGFloat
    private let bucketDetail: ((PeriodBucket) -> String?)?

    @State private var selectedDate: Date?

    public init(
        title: String,
        samples: [DatedSample],
        period: ChartPeriod,
        aggregation: MetricAggregation,
        style: Style = .line,
        valueLabel: @escaping (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) },
        risingColor: Color = .blue,
        fallingColor: Color = .red,
        barColor: Color = .accentColor,
        goal: PeriodGoal? = nil,
        hitColor: Color = .green,
        missColor: Color = .orange,
        height: CGFloat = 160,
        bucketDetail: ((PeriodBucket) -> String?)? = nil,
        bucketer: PeriodBucketer = PeriodBucketer(),
        now: Date = .now
    ) {
        let buckets = bucketer.buckets(for: samples, period: period, aggregation: aggregation, now: now)
        self.title = title
        self.period = period
        self.aggregation = aggregation
        self.style = style
        self.buckets = buckets
        self.summary = PeriodSummary(buckets: buckets, aggregation: aggregation)
        self.calendar = bucketer.calendar
        self.valueLabel = valueLabel
        self.risingColor = risingColor
        self.fallingColor = fallingColor
        self.barColor = barColor
        self.goal = goal
        self.hitColor = hitColor
        self.missColor = missColor
        self.height = height
        self.bucketDetail = bucketDetail
    }

    private var selectedBucket: PeriodBucket? {
        selectedDate.flatMap { Self.bucket(nearest: $0, in: buckets) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if summary.latest == nil {
                Text("No data in the \(period.windowDescription).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: height)
            } else {
                chart
            }
        }
        .padding(.vertical, 4)
        .onChange(of: period) { selectedDate = nil }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text("\(period.adjective) \(aggregation.label) · \(period.windowDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let average = summary.windowAverage {
                    Text("avg \(valueLabel(average))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let goal, let newest = buckets.last {
                    let hits = buckets.filter { outcome(of: $0) == .hit }.count
                    let judged = buckets.filter { outcome(of: $0) != nil }.count
                    Text("goal \(valueLabel(goal.target(for: Self.fullBucket(newest, period: period, calendar: calendar), aggregation: aggregation, calendar: calendar))) · \(hits)/\(judged) hit")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let shown = selectedBucket ?? summary.latest, let value = shown.value {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(valueLabel(value))
                        .font(.title3.monospacedDigit().bold())
                    HStack(spacing: 4) {
                        Text([bucketDetail?(shown), caption(for: shown)]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if selectedBucket == nil, let change = summary.percentChange {
                            changeLabel(change)
                        }
                    }
                }
            }
        }
    }

    private func changeLabel(_ change: Double) -> some View {
        HStack(spacing: 1) {
            Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
            Text(abs(change).formatted(.percent.precision(.fractionLength(abs(change) < 0.1 ? 1 : 0))))
        }
        .font(.caption.monospacedDigit().bold())
        .foregroundStyle(change >= 0 ? risingColor : fallingColor)
    }

    private func caption(for bucket: PeriodBucket) -> String {
        if bucket.id == buckets.last?.id {
            return bucket.isPartial ? "\(period.currentLabel) so far" : period.currentLabel
        }
        return Self.caption(for: bucket.start, period: period, calendar: calendar)
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            if let average = summary.windowAverage {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if style == .line {
                lineMarks
            } else {
                barMarks
            }
            goalMarks
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: (buckets.first?.start ?? .now)...(buckets.last?.end ?? .now))
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisGridLine()
                // Trailing-anchored: the newest label sits at the plot's
                // right edge and would truncate if centered.
                AxisValueLabel(anchor: .topTrailing) {
                    // Ticks sit at bucket midpoints; label with the start
                    // ("week of Oct 5"), not the midpoint's Thursday.
                    if let date = value.as(Date.self) {
                        let start = buckets.last { $0.start <= date }?.start ?? date
                        Text(Self.axisLabel(for: start, period: period, calendar: calendar))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let value = value.as(Double.self) {
                        Text(valueLabel(value))
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in
            // Zero distance so a tap selects too; no .onEnded so the
            // selection stays readable after the finger lifts.
            DragGesture(minimumDistance: 0)
                .onChanged { proxy.selectXValue(at: $0.location.x) }
        }
        .frame(height: height)
    }

    /// Buckets with data, each plotted at its midpoint.
    private var plotted: [Plotted] {
        buckets.compactMap { bucket in
            bucket.value.map { Plotted(bucket: bucket, point: ChartPoint(start: Self.midpoint(of: bucket), value: $0)) }
        }
    }

    private struct Plotted: Identifiable {
        let bucket: PeriodBucket
        let point: ChartPoint
        var id: Date { bucket.id }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        let plotted = plotted
        let segments = SlopeColoredLineChart.segments(from: plotted.map(\.point))
        let endsPartial = plotted.last?.bucket.isPartial == true
        ForEach(segments) { segment in
            let isPartial = endsPartial && segment.id == segments.count - 1
            let color = segment.isRising ? risingColor : fallingColor
            ForEach([segment.start, segment.end], id: \.start) { point in
                LineMark(
                    x: .value("Date", point.start),
                    y: .value("Value", point.value),
                    series: .value("Segment", segment.id)
                )
                .foregroundStyle(color.opacity(isPartial ? 0.4 : 1))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: isPartial ? [4, 3] : []))
            }
        }
        ForEach(plotted) { entry in
            let isSelected = entry.bucket.id == selectedBucket?.id
            PointMark(
                x: .value("Date", entry.point.start),
                y: .value("Value", entry.point.value)
            )
            .symbolSize(isSelected ? 80 : 24)
            .foregroundStyle(pointColor(for: entry.bucket).opacity(entry.bucket.isPartial ? 0.4 : 1))
            .annotation(position: .top, alignment: .center, spacing: 4) {
                annotation(for: entry.bucket, isSelected: isSelected)
            }
        }
    }

    @ChartContentBuilder
    private var barMarks: some ChartContent {
        ForEach(plotted) { entry in
            let isSelected = entry.bucket.id == selectedBucket?.id
            let inset = entry.bucket.end.timeIntervalSince(entry.bucket.start) * 0.15
            // RectangleMark: BarMark has no form taking both an x range
            // (exact Monday-to-Monday edges) and a y range. Bars grow from
            // zero, so a negative total hangs down from it.
            RectangleMark(
                xStart: .value("Start", entry.bucket.start.addingTimeInterval(inset)),
                xEnd: .value("End", entry.bucket.end.addingTimeInterval(-inset)),
                yStart: .value("Zero", 0),
                yEnd: .value("Value", entry.point.value)
            )
            .foregroundStyle((isSelected ? Color.primary : fillColor(for: entry.bucket)).opacity(entry.bucket.isPartial ? 0.35 : 1))
            .annotation(position: .top, alignment: .center, spacing: 2) {
                annotation(for: entry.bucket, isSelected: isSelected)
            }
        }
    }

    /// One dashed segment per bucket at that bucket's goal, so a `.sum`
    /// goal steps with month length and a partial week shows its full target.
    @ChartContentBuilder
    private var goalMarks: some ChartContent {
        if let goal {
            ForEach(buckets) { bucket in
                RuleMark(
                    xStart: .value("Start", bucket.start),
                    xEnd: .value("End", bucket.end),
                    y: .value("Goal", goal.target(for: bucket, aggregation: aggregation, calendar: calendar))
                )
                .foregroundStyle(hitColor.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
            }
        }
    }

    private func outcome(of bucket: PeriodBucket) -> PeriodGoal.Outcome? {
        goal?.outcome(for: bucket, aggregation: aggregation, calendar: calendar)
    }

    private func fillColor(for bucket: PeriodBucket) -> Color {
        switch outcome(of: bucket) {
        case .hit:  return hitColor
        case .miss: return missColor
        case nil:   return barColor
        }
    }

    private func pointColor(for bucket: PeriodBucket) -> Color {
        switch outcome(of: bucket) {
        case .hit:  return hitColor
        case .miss: return missColor
        case nil:   return .primary
        }
    }

    @ViewBuilder
    private func annotation(for bucket: PeriodBucket, isSelected: Bool) -> some View {
        if isSelected, let value = bucket.value {
            VStack(spacing: 0) {
                Text(valueLabel(value))
                    .font(.caption2.monospacedDigit().bold())
                if let detail = bucketDetail?(bucket) {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 140)
                }
            }
        } else if bucket.isPartial {
            Text("so far")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let points = plotted.map(\.point)
        let targets = goalTargets
        switch style {
        case .line:
            let goalPoints = targets.map { ChartPoint(start: .distantPast, value: $0) }
            return PeriodGoalBarChart.paddedDomain(points: points + goalPoints, goal: summary.windowAverage)
        case .bar:
            return Self.barDomain(values: points.map(\.value) + targets)
        }
    }

    /// Every bucket's goal, so the goal line is never clipped.
    private var goalTargets: [Double] {
        guard let goal else { return [] }
        return buckets.map { goal.target(for: $0, aggregation: aggregation, calendar: calendar) }
    }

    private var axisDates: [Date] {
        Self.axisBuckets(buckets, period: period).map(Self.midpoint(of:))
    }

    // MARK: Pure helpers

    /// `bucket` stretched to a whole period, for the header's goal label —
    /// the newest bucket is the current week/month, whose goal is the full
    /// period's.
    static func fullBucket(_ bucket: PeriodBucket, period: ChartPeriod, calendar: Calendar) -> PeriodBucket {
        let end = calendar.date(byAdding: period.component, value: 1, to: bucket.start) ?? bucket.end
        return PeriodBucket(start: bucket.start, end: end, value: bucket.value, isPartial: false)
    }

    static func midpoint(of bucket: PeriodBucket) -> Date {
        bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2)
    }

    /// The bucket with data whose midpoint is closest to `date` — what the
    /// drag-to-read selection resolves to.
    static func bucket(nearest date: Date, in buckets: [PeriodBucket]) -> PeriodBucket? {
        buckets
            .filter { $0.value != nil }
            .min { abs(midpoint(of: $0).timeIntervalSince(date)) < abs(midpoint(of: $1).timeIntervalSince(date)) }
    }

    /// Zero-based domain with 15% headroom so the top annotation isn't clipped.
    static func barDomain(values: [Double]) -> ClosedRange<Double> {
        let lo = Swift.min(0, values.min() ?? 0)
        let hi = Swift.max(values.max() ?? 0, 0)
        let span = Swift.max(hi - lo, 1)
        return lo...(lo + span * 1.15)
    }

    /// Every 7th day / 3rd week / 3rd month, counted back from the newest so
    /// the current period is always labelled.
    static func axisBuckets(_ buckets: [PeriodBucket], period: ChartPeriod) -> [PeriodBucket] {
        let stride = period == .day ? 7 : 3
        return buckets.reversed().enumerated()
            .filter { $0.offset % stride == 0 }
            .map(\.element)
            .reversed()
    }

    static func axisLabel(for date: Date, period: ChartPeriod, calendar: Calendar) -> String {
        var style = Date.FormatStyle(timeZone: calendar.timeZone)
        style.calendar = calendar
        switch period {
        case .day, .week: return date.formatted(style.month(.abbreviated).day())
        case .month:      return date.formatted(style.month(.abbreviated))
        }
    }

    static func caption(for start: Date, period: ChartPeriod, calendar: Calendar) -> String {
        var style = Date.FormatStyle(timeZone: calendar.timeZone)
        style.calendar = calendar
        switch period {
        case .day:   return start.formatted(style.weekday(.abbreviated).month(.abbreviated).day())
        case .week:  return "Week of \(start.formatted(style.month(.abbreviated).day()))"
        case .month: return start.formatted(style.month(.wide).year())
        }
    }
}

#if DEBUG
#Preview("PeriodChartView") {
    Form {
        Section {
            PeriodChartView(title: "Weight", samples: SwChartsSamples.dailyWeight,
                            period: .week, aggregation: .average,
                            risingColor: .orange, fallingColor: .green,
                            now: SwChartsSamples.now)
        }
        Section {
            PeriodChartView(title: "Calories", samples: SwChartsSamples.dailyCalories,
                            period: .week, aggregation: .sum, style: .bar,
                            valueLabel: { $0.formatted(.number.notation(.compactName)) },
                            now: SwChartsSamples.now)
        }
        Section {
            PeriodChartView(title: "Calories vs goal", samples: SwChartsSamples.dailyCalories,
                            period: .week, aggregation: .sum, style: .bar,
                            valueLabel: { $0.formatted(.number.notation(.compactName)) },
                            goal: PeriodGoal(2300, direction: .atMost),
                            now: SwChartsSamples.now)
        }
    }
}
#endif
