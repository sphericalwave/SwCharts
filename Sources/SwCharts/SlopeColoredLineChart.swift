import SwiftUI
import Charts

/// A line chart over dated points whose segments are colored by trend — one
/// color where the line rises, another where it falls — so a run of good or bad
/// nights (or weeks, or sessions) reads at a glance without a legend.
///
/// The y-axis is caller-supplied on purpose: `yDomain` and `yAxisLabel` change
/// from instance to instance. A clock chart wants a domain a few minutes wider
/// than the recorded range and labels formatted as times; a percentage chart
/// wants a clamped 0…100-ish domain and `"%"` labels. Pass a domain padded
/// however the metric wants — values that cluster in a narrow band stay
/// distinct instead of flattening against a `0…max` axis.
///
/// Which direction is "good" is the caller's call too: pass `risingColor` and
/// `fallingColor` to suit the metric (more sleep is good; more weight may not
/// be).
///
/// Point markers are drawn by default. Pass `showsPoints: false` for a dense
/// window — past a few dozen points the markers overlap into a band that hides
/// the line they are meant to annotate.
///
/// Markers take the chart's default foreground unless `pointColor` is set —
/// pass one when that default blends into the line (e.g. `.primary` for
/// white-on-dark dots).
///
/// Pass `current` to mark one point — say, the entry being edited — where it
/// lands against the history: it joins the line and gets a larger marker.
/// `projection` draws a dashed what-if continuation from there (or from the
/// last point), outside the rising/falling coloring.
///
/// `interpolation: .catmullRom` draws the line — projection included — as one
/// smooth `CatmullRomSpline` curve. Each segment still takes its own rising or
/// falling color and the projection stays dashed; neighbouring segments meet
/// with matching tangents, and no segment overshoots its endpoints.
///
/// Renders plain content — wrap it in your own `Section` or card.
public struct SlopeColoredLineChart: View {

    private let points: [ChartPoint]
    private let yDomain: ClosedRange<Double>
    private let yAxisLabel: (Double) -> String
    private let risingColor: Color
    private let fallingColor: Color
    private let showsPoints: Bool
    private let pointColor: Color?
    private let height: CGFloat
    private let current: ChartPoint?
    private let currentColor: Color
    private let projection: [ChartPoint]
    private let interpolation: LineInterpolation

    public init(
        points: [ChartPoint],
        yDomain: ClosedRange<Double>,
        yAxisLabel: @escaping (Double) -> String,
        risingColor: Color = .blue,
        fallingColor: Color = .red,
        showsPoints: Bool = true,
        pointColor: Color? = nil,
        height: CGFloat = 140,
        current: ChartPoint? = nil,
        currentColor: Color = .accentColor,
        projection: [ChartPoint] = [],
        interpolation: LineInterpolation = .linear
    ) {
        self.points = points
        self.yDomain = yDomain
        self.yAxisLabel = yAxisLabel
        self.risingColor = risingColor
        self.fallingColor = fallingColor
        self.showsPoints = showsPoints
        self.pointColor = pointColor
        self.height = height
        self.current = current
        self.currentColor = currentColor
        self.projection = projection
        self.interpolation = interpolation
    }

    /// The solid line: the history, then `current` when there is one.
    static func linePoints(_ points: [ChartPoint], current: ChartPoint?) -> [ChartPoint] {
        points + [current].compactMap { $0 }
    }

    /// The dashed what-if line, anchored on the solid line's last point so it
    /// reads as a continuation. Empty when there's nothing to project.
    static func projectionPoints(_ projection: [ChartPoint], from line: [ChartPoint]) -> [ChartPoint] {
        guard !projection.isEmpty else { return [] }
        return [line.last].compactMap { $0 } + projection
    }

    /// One leg of the line: the pair of points it spans, and which way it went.
    /// A flat segment counts as rising, so a plateau doesn't read as a decline.
    struct Segment: Identifiable, Equatable {
        let id: Int
        let start: ChartPoint
        let end: ChartPoint

        var isRising: Bool { end.value >= start.value }
    }

    /// Consecutive pairs of `points`, in order. Pure so it's unit-testable.
    /// Fewer than two points means nothing to connect — no segments.
    static func segments(from points: [ChartPoint]) -> [Segment] {
        guard points.count > 1 else { return [] }
        return zip(points, points.dropFirst()).enumerated().map { index, pair in
            Segment(id: index, start: pair.0, end: pair.1)
        }
    }

    private func color(for segment: Segment) -> Color {
        segment.isRising ? risingColor : fallingColor
    }

    /// One sampled stretch of the smooth curve, and whether it's part of the
    /// projection rather than the solid line.
    struct Curve: Identifiable {
        let id: Int
        let samples: [ChartPoint]
        let isRising: Bool
        let isProjection: Bool
    }

    /// The solid line and its projection as one `CatmullRomSpline`, split back
    /// into per-segment samples. Points are moved to the middle of their day,
    /// where the `unit: .day` dots are drawn, so the curve passes through them.
    static func curves(line: [ChartPoint], projection: [ChartPoint], calendar: Calendar = .current) -> [Curve] {
        let projected = projectionPoints(projection, from: line).dropFirst()
        let all = (line + projected).map { $0.centered(in: .day, calendar: calendar) }
        let solidCount = max(line.count - 1, 0)
        return CatmullRomSpline.segments(through: all).enumerated().map { index, samples in
            Curve(id: index,
                  samples: samples,
                  isRising: (samples.last?.value ?? 0) >= (samples.first?.value ?? 0),
                  isProjection: index >= solidCount)
        }
    }

    public var body: some View {
        let line = Self.linePoints(points, current: current)
        return Chart {
            if interpolation == .catmullRom {
                smoothSegments(line: line)
            } else {
                linearSegments(line: line)
            }
            // Indexed rather than keyed by date: repeated dates are the
            // caller's business, and a duplicate id would drop a point.
            // Dense series hide their own line behind the markers, so a caller
            // plotting a long window can turn them off.
            if showsPoints {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    PointMark(
                        x: .value("Date", point.start, unit: .day),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(pointColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                }
            }
            if interpolation == .catmullRom {
                smoothProjectionPoints(line: line)
            } else {
                linearProjection(line: line)
            }
            if let current {
                PointMark(
                    x: .value("Date", current.start, unit: .day),
                    y: .value("Value", current.value)
                )
                .foregroundStyle(currentColor)
                .symbolSize(90)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let value = value.as(Double.self) {
                        Text(yAxisLabel(value))
                    }
                }
            }
        }
        .frame(height: height)
    }

    @ChartContentBuilder
    private func linearSegments(line: [ChartPoint]) -> some ChartContent {
        // Each segment is its own series so it can carry its own color;
        // a single series would take one style for the whole line.
        ForEach(Self.segments(from: line)) { segment in
            LineMark(
                x: .value("Date", segment.start.start, unit: .day),
                y: .value("Value", segment.start.value),
                series: .value("Segment", segment.id)
            )
            .foregroundStyle(color(for: segment))
            LineMark(
                x: .value("Date", segment.end.start, unit: .day),
                y: .value("Value", segment.end.value),
                series: .value("Segment", segment.id)
            )
            .foregroundStyle(color(for: segment))
        }
    }

    @ChartContentBuilder
    private func linearProjection(line: [ChartPoint]) -> some ChartContent {
        ForEach(Array(Self.projectionPoints(projection, from: line).enumerated()), id: \.offset) { _, point in
            LineMark(
                x: .value("Date", point.start, unit: .day),
                y: .value("Value", point.value),
                series: .value("Projection", "projection")
            )
            .foregroundStyle(.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .symbol(.circle)
            .symbolSize(16)
        }
    }

    /// The smooth curve, one series per segment so each keeps its own style.
    /// The samples are plain dates: `unit: .day` would snap them back to
    /// whole days.
    @ChartContentBuilder
    private func smoothSegments(line: [ChartPoint]) -> some ChartContent {
        ForEach(Self.curves(line: line, projection: projection)) { curve in
            ForEach(Array(curve.samples.enumerated()), id: \.offset) { _, sample in
                LineMark(
                    x: .value("Date", sample.start),
                    y: .value("Value", sample.value),
                    series: .value("Segment", "segment-\(curve.id)")
                )
                .foregroundStyle(curve.isProjection
                                 ? AnyShapeStyle(.secondary)
                                 : AnyShapeStyle(curve.isRising ? risingColor : fallingColor))
                .lineStyle(curve.isProjection ? StrokeStyle(lineWidth: 1.5, dash: [4, 3]) : StrokeStyle(lineWidth: 2))
            }
        }
    }

    /// The projection's markers, drawn apart from its curve — a `.symbol` on
    /// the curve would mark every sample.
    @ChartContentBuilder
    private func smoothProjectionPoints(line: [ChartPoint]) -> some ChartContent {
        ForEach(Array(Self.projectionPoints(projection, from: line).dropFirst().enumerated()), id: \.offset) { _, point in
            PointMark(
                x: .value("Date", point.start, unit: .day),
                y: .value("Value", point.value)
            )
            .foregroundStyle(.secondary)
            .symbolSize(16)
        }
    }
}

extension ChartPoint {
    /// This point moved to the middle of its `component` (its day, by
    /// default) — where Swift Charts draws a mark plotted with that `unit:`.
    public func centered(in component: Calendar.Component = .day, calendar: Calendar = .current) -> ChartPoint {
        guard let interval = calendar.dateInterval(of: component, for: start) else { return self }
        return ChartPoint(start: interval.start.addingTimeInterval(interval.duration / 2), value: value)
    }
}

#if DEBUG
#Preview("SlopeColoredLineChart") {
    SlopeColoredLineChart(
        points: SwChartsSamples.weekly,
        yDomain: 178...183,
        yAxisLabel: { String(format: "%.1f", $0) }
    )
    .padding()
}

#Preview("SlopeColoredLineChart — current + projection") {
    let last = SwChartsSamples.weekly.last!
    let week: TimeInterval = 7 * 86_400
    SlopeColoredLineChart(
        points: Array(SwChartsSamples.weekly.dropLast()),
        yDomain: 178...186,
        yAxisLabel: { String(format: "%.1f", $0) },
        current: last,
        projection: (1...3).map {
            ChartPoint(start: last.start.addingTimeInterval(Double($0) * week),
                       value: last.value * pow(1.01, Double($0)))
        }
    )
    .padding()
}

#Preview("SlopeColoredLineChart — Catmull-Rom") {
    let last = SwChartsSamples.weekly.last!
    SlopeColoredLineChart(
        points: Array(SwChartsSamples.weekly.dropLast()),
        yDomain: 178...183,
        yAxisLabel: { String(format: "%.1f", $0) },
        projection: [last],
        interpolation: .catmullRom
    )
    .padding()
}
#endif
