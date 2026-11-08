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
/// - press-and-drag to read: hold a finger on the chart for a moment, then
///   slide it, and the header shows the bucket under it. Lifting the finger
///   clears it and the header goes back to the latest period. A swipe that
///   moves before the hold registers is left to the container (a paged
///   `TabView`, a `ScrollView`), so it selects nothing;
/// - optionally a `bucketDetail` line naming what a bucket's value came
///   from (the lift behind a weekly max), in the header and on the selected
///   point;
/// - optionally a `PeriodGoal`: a dashed goal line across each bucket (scaled
///   per period for `.sum` metrics) and each bar/point tinted hit or miss;
/// - optionally `wholeNumbers` y ticks, for counts (sessions, sets);
/// - press-and-drag reading can be turned off with `selectable: false`;
/// - optionally, for `.line`, `interpolation: .catmullRom`: one smooth
///   `CatmullRomSpline` curve that keeps each segment's rising/falling color
///   and the dashed, faded "so far" leg;
/// - optionally a `bucketCount` window other than the period's default
///   (e.g. 14 days), and `trimLeadingEmpty` to start the window at the first
///   bucket with data instead of showing empty leading buckets;
/// - optionally a `reference` line: a fixed, labelled dashed level (e.g.
///   "isotonic 9 g/L") with no hit/miss tint — unlike a `goal`;
/// - optionally a `windowLabel` naming a non-standard window ("all time"),
///   for a `bucketCount` the period's own description would misstate.
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
    private let wholeNumbers: Bool
    private let selectable: Bool
    private let interpolation: LineInterpolation
    private let reference: Reference?
    private let windowLabel: String?

    /// A fixed level drawn as a labelled dashed line. Purely visual: it
    /// doesn't tint buckets, count hits or change the header.
    public struct Reference: Sendable {
        public let value: Double
        public let label: String?

        public init(_ value: Double, label: String? = nil) {
            self.value = value
            self.label = label
        }
    }

    @State private var selectedDate: Date?
    /// True while a press-and-drag scrub is in progress. Gesture state
    /// resets on lift and on cancel (a pager or scroll view taking the
    /// touch), and that reset clears `selectedDate`.
    @GestureState private var isScrubbing = false

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
        wholeNumbers: Bool = false,
        selectable: Bool = true,
        interpolation: LineInterpolation = .linear,
        bucketCount: Int? = nil,
        trimLeadingEmpty: Bool = false,
        reference: Reference? = nil,
        windowLabel: String? = nil,
        bucketer: PeriodBucketer = PeriodBucketer(),
        now: Date = .now
    ) {
        let all = bucketer.buckets(for: samples, period: period, aggregation: aggregation,
                                   now: now, bucketCount: bucketCount)
        let buckets = trimLeadingEmpty ? Self.trimmingLeadingEmpty(all) : all
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
        self.wholeNumbers = wholeNumbers
        self.selectable = selectable
        self.interpolation = interpolation
        self.reference = reference
        self.windowLabel = windowLabel
    }

    private var selectedBucket: PeriodBucket? {
        selectedDate.flatMap { Self.bucket(nearest: $0, in: buckets) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if summary.latest == nil {
                Text(windowLabel == nil ? "No data in the \(period.windowDescription)." : "No data yet.")
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
                Text("\(period.adjective) \(aggregation.label) · \(windowLabel ?? period.windowDescription)")
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

    @ViewBuilder
    private var chart: some View {
        if selectable {
            plot
                .chartXSelection(value: $selectedDate)
                .chartGesture { proxy in
                    // A short hold before scrubbing: a swipe that moves
                    // first fails the long press, so the touch goes to the
                    // enclosing pager/scroll view and nothing is selected.
                    LongPressGesture(minimumDuration: Self.scrubHoldDuration,
                                     maximumDistance: Self.scrubHoldSlop)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .updating($isScrubbing) { value, state, _ in
                            state = Self.scrubActive(value)
                        }
                        .onChanged { value in
                            if let x = Self.scrubX(value) { proxy.selectXValue(at: x) }
                        }
                }
                .onChange(of: isScrubbing) {
                    if !isScrubbing { selectedDate = nil }
                }
                .frame(height: height)
        } else {
            plot
                .frame(height: height)
        }
    }

    private var plot: some View {
        Chart {
            if let average = summary.windowAverage {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if style == .line {
                if interpolation == .catmullRom {
                    smoothLineMarks
                } else {
                    lineMarks
                }
                pointMarks
            } else {
                barMarks
            }
            goalMarks
            referenceMarks
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
                        Text(Self.axisLabel(for: start, period: period, bucketCount: buckets.count, calendar: calendar))
                    }
                }
            }
        }
        .chartYAxis {
            if wholeNumbers {
                AxisMarks(values: Self.wholeTicks(in: yDomain)) { value in
                    yAxisMark(value)
                }
            } else {
                AxisMarks { value in
                    yAxisMark(value)
                }
            }
        }
    }

    @AxisMarkBuilder
    private func yAxisMark(_ value: AxisValue) -> some AxisMark {
        AxisGridLine()
        AxisValueLabel {
            if let value = value.as(Double.self) {
                Text(valueLabel(value))
            }
        }
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
    }

    /// `lineMarks` as one smooth curve, sampled per segment so each segment
    /// keeps its own color and the "so far" leg its dash.
    @ChartContentBuilder
    private var smoothLineMarks: some ChartContent {
        let plotted = plotted
        let curves = CatmullRomSpline.segments(through: plotted.map(\.point))
        let endsPartial = plotted.last?.bucket.isPartial == true
        ForEach(Array(curves.enumerated()), id: \.offset) { index, samples in
            let isPartial = endsPartial && index == curves.count - 1
            let isRising = (samples.last?.value ?? 0) >= (samples.first?.value ?? 0)
            let color = isRising ? risingColor : fallingColor
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                LineMark(
                    x: .value("Date", sample.start),
                    y: .value("Value", sample.value),
                    series: .value("Segment", index)
                )
                .foregroundStyle(color.opacity(isPartial ? 0.4 : 1))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: isPartial ? [4, 3] : []))
            }
        }
    }

    @ChartContentBuilder
    private var pointMarks: some ChartContent {
        ForEach(plotted) { entry in
            let isSelected = entry.bucket.id == selectedBucket?.id
            PointMark(
                x: .value("Date", entry.point.start),
                y: .value("Value", entry.point.value)
            )
            .symbolSize(isSelected ? 80 : 24)
            .foregroundStyle(pointColor(for: entry.bucket).opacity(entry.bucket.isPartial ? 0.4 : 1))
            .annotation(position: .top, alignment: .center, spacing: 4, overflowResolution: Self.annotationOverflow) {
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
            .annotation(position: .top, alignment: .center, spacing: 2, overflowResolution: Self.annotationOverflow) {
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

    @ChartContentBuilder
    private var referenceMarks: some ChartContent {
        if let reference {
            RuleMark(y: .value("Reference", reference.value))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    if let label = reference.label {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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

    /// Keep a selected value's label inside the chart's width — centered on
    /// the first or last bucket it would run off the edge and clip.
    private static let annotationOverflow = AnnotationOverflowResolution(x: .fit(to: .chart), y: .automatic)

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

    /// Every bucket's goal plus the reference level, so neither line is
    /// clipped.
    private var goalTargets: [Double] {
        let goals = goal.map { goal in
            buckets.map { goal.target(for: $0, aggregation: aggregation, calendar: calendar) }
        } ?? []
        return goals + [reference?.value].compactMap { $0 }
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

    /// `buckets` from the first one with data onward — the window starts at
    /// the first data day. With no data at all, unchanged (the view shows
    /// its "No data" message).
    static func trimmingLeadingEmpty(_ buckets: [PeriodBucket]) -> [PeriodBucket] {
        guard let first = buckets.firstIndex(where: { $0.value != nil }) else { return buckets }
        return Array(buckets[first...])
    }

    static func midpoint(of bucket: PeriodBucket) -> Date {
        bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2)
    }

    /// How long a finger must rest on the chart before a drag scrubs. Short
    /// enough to feel immediate, long enough that a page swipe moves first.
    static let scrubHoldDuration: Double = 0.15
    /// How far the finger may move during the hold; past this the long press
    /// fails and the swipe belongs to the container.
    static let scrubHoldSlop: CGFloat = 10

    typealias ScrubValue = SequenceGesture<LongPressGesture, DragGesture>.Value

    /// Scrubbing once the hold has completed, until the finger lifts.
    static func scrubActive(_ value: ScrubValue) -> Bool {
        if case .second(true, _) = value { return true }
        return false
    }

    /// The x to select: the drag's location once the hold has completed and
    /// the finger has moved; `nil` during the hold.
    static func scrubX(_ value: ScrubValue) -> CGFloat? {
        if case .second(true, let drag?) = value { return drag.location.x }
        return nil
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

    /// Whole-number y ticks inside `domain`, for counts: at most five, a
    /// whole step apart — 0, 1, 2 rather than 0, 0.5, 1, 1.5, 2.
    static func wholeTicks(in domain: ClosedRange<Double>) -> [Double] {
        let lo = domain.lowerBound.rounded(.up), hi = domain.upperBound.rounded(.down)
        guard lo <= hi else { return [] }
        let step = Swift.max(1, ((hi - lo) / 4).rounded(.up))
        return Array(stride(from: lo, through: hi, by: step))
    }

    /// Every 7th day / 3rd week / 3rd month, counted back from the newest so
    /// the current period is always labelled. A month window longer than the
    /// standard year widens the step so the labels still fit: 6 months up to
    /// two years, then whole years, about six labels at most.
    static func axisBuckets(_ buckets: [PeriodBucket], period: ChartPeriod) -> [PeriodBucket] {
        let stride: Int
        switch (period, buckets.count) {
        case (.day, _):                 stride = 7
        case (.month, 13...24):         stride = 6
        case (.month, 25...):           stride = 12 * ((buckets.count + 71) / 72)
        default:                        stride = 3
        }
        return buckets.reversed().enumerated()
            .filter { $0.offset % stride == 0 }
            .map(\.element)
            .reversed()
    }

    static func axisLabel(for date: Date, period: ChartPeriod, bucketCount: Int = 12, calendar: Calendar) -> String {
        var style = Date.FormatStyle(timeZone: calendar.timeZone)
        style.calendar = calendar
        switch period {
        case .day, .week: return date.formatted(style.month(.abbreviated).day())
        case .month:
            if bucketCount > 24 { return date.formatted(style.year()) }
            if bucketCount > 12 { return date.formatted(style.month(.abbreviated).year(.twoDigits)) }
            return date.formatted(style.month(.abbreviated))
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
