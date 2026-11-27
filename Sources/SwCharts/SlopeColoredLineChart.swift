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
/// `projectionEndMarker` puts an emoji (say "🚀") on the projection's last
/// point, turned to fly along the dashed line's final leg. The glyph is taken
/// to point up and to the right, as 🚀 does.
///
/// `projectionProgress` (0…1, default 1) draws only that much of the
/// projection, from the solid line's end, with the marker riding its tip
/// along the line — animate it to fly the marker to the projection's end.
/// The legs share it evenly. The x-axis stays sized for the whole projection,
/// so nothing rescales as it grows. Smoothest with `.linear` interpolation.
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
    private let projectionEndMarker: String?
    private let projectionProgress: Double

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
        interpolation: LineInterpolation = .linear,
        projectionEndMarker: String? = nil,
        projectionProgress: Double = 1
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
        self.projectionEndMarker = projectionEndMarker
        self.projectionProgress = min(max(projectionProgress, 0), 1)
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

    /// The dashed line drawn `progress` of the way along (legs share it
    /// evenly), with plot positions: each point moved to the middle of its
    /// day, where `unit: .day` marks are drawn, and the tip partway along its
    /// leg. `leg` is the whole leg the tip is on, for the marker's heading.
    /// Nil when there's nothing to project.
    static func projectionPath(_ projection: [ChartPoint], from line: [ChartPoint], progress: Double,
                               calendar: Calendar = .current) -> (points: [ChartPoint], leg: (from: ChartPoint, to: ChartPoint))? {
        let path = projectionPoints(projection, from: line).map { $0.centered(calendar: calendar) }
        guard path.count > 1 else { return nil }
        let along = min(max(progress, 0), 1) * Double(path.count - 1)
        let index = min(Int(along), path.count - 2)
        let fraction = along - Double(index)
        let from = path[index], to = path[index + 1]
        let tip = ChartPoint(start: from.start.addingTimeInterval(to.start.timeIntervalSince(from.start) * fraction),
                             value: from.value + (to.value - from.value) * fraction)
        return (Array(path[...index]) + [tip], (from, to))
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
        .chartOverlay { proxy in
            projectionEndMarkerOverlay(line: line, proxy: proxy)
        }
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

    /// Rotation that turns a glyph pointing up-right (−45° on screen, y down)
    /// to point from `from` to `to`.
    static func markerRotation(from: CGPoint, to: CGPoint) -> Angle {
        guard from != to else { return .zero }
        return .radians(atan2(to.y - from.y, to.x - from.x) + .pi / 4)
    }

    /// `projectionEndMarker` at the drawn projection's tip (its end, when
    /// whole), headed along the leg it's on. Positions come from the chart, so
    /// it follows the projection as it moves or grows.
    @ViewBuilder
    private func projectionEndMarkerOverlay(line: [ChartPoint], proxy: ChartProxy) -> some View {
        if let projectionEndMarker,
           let path = Self.projectionPath(projection, from: line, progress: projectionProgress),
           let tipPoint = path.points.last {
            GeometryReader { geometry in
                // Path points are already where `unit: .day` marks are drawn.
                if let plotFrame = proxy.plotFrame,
                   let from = proxy.position(for: (x: path.leg.from.start, y: path.leg.from.value)),
                   let to = proxy.position(for: (x: path.leg.to.start, y: path.leg.to.value)),
                   let tip = proxy.position(for: (x: tipPoint.start, y: tipPoint.value)) {
                    let origin = geometry[plotFrame].origin
                    Text(projectionEndMarker)
                        .font(.system(size: 22))
                        .rotationEffect(Self.markerRotation(from: from, to: to))
                        .position(x: origin.x + tip.x, y: origin.y + tip.y)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
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

    /// The dashed line, as far as `projectionProgress` reaches. Plain dates:
    /// the points are already mid-day, and `unit: .day` would snap a growing
    /// tip to whole days.
    @ChartContentBuilder
    private func linearProjection(line: [ChartPoint]) -> some ChartContent {
        let path = Self.projectionPath(projection, from: line, progress: projectionProgress)?.points ?? []
        ForEach(Array(path.enumerated()), id: \.offset) { _, point in
            LineMark(
                x: .value("Date", point.start),
                y: .value("Value", point.value),
                series: .value("Projection", "projection")
            )
            .foregroundStyle(.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .symbol(.circle)
            .symbolSize(16)
        }
        projectionExtent(line: line)
    }

    /// While the projection is partly drawn, an invisible mark at its end
    /// keeps the x-axis sized for all of it.
    @ChartContentBuilder
    private func projectionExtent(line: [ChartPoint]) -> some ChartContent {
        if projectionProgress < 1, let end = Self.projectionPoints(projection, from: line).last {
            PointMark(
                x: .value("Date", end.start, unit: .day),
                y: .value("Value", end.value)
            )
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    /// The smooth curve, one series per segment so each keeps its own style.
    /// The samples are plain dates: `unit: .day` would snap them back to
    /// whole days.
    @ChartContentBuilder
    private func smoothSegments(line: [ChartPoint]) -> some ChartContent {
        ForEach(Self.curves(line: line, projection: drawnProjection(line: line))) { curve in
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
        ForEach(Array(Self.projectionPoints(drawnProjection(line: line), from: line).dropFirst().enumerated()), id: \.offset) { _, point in
            PointMark(
                x: .value("Date", point.start, unit: .day),
                y: .value("Value", point.value)
            )
            .foregroundStyle(.secondary)
            .symbolSize(16)
        }
        projectionExtent(line: line)
    }

    /// The projection points `projectionProgress` reaches, tip last (whole at 1).
    private func drawnProjection(line: [ChartPoint]) -> [ChartPoint] {
        guard projectionProgress < 1 else { return projection }
        return Array((Self.projectionPath(projection, from: line, progress: projectionProgress)?.points ?? []).dropFirst())
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
        },
        projectionEndMarker: "🚀"
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
