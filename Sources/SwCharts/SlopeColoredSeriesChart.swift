import SwiftUI
import Charts

/// One point of an ordered series: a plain numeric x (a round number, seconds
/// elapsed, a set index) and the value to plot there.
public struct SeriesPoint: Equatable, Sendable {
    public let x: Double
    public let value: Double

    public init(x: Double, value: Double) {
        self.x = x
        self.value = value
    }
}

/// `SlopeColoredLineChart` for a series that isn't dated — x is a plain
/// `Double` rather than a calendar-day bucket, so it can plot per-round or
/// per-second data that would all collapse into one day otherwise. Segments
/// are colored by trend the same way: one color where the line rises, another
/// where it falls, so a run of good or bad rounds reads at a glance.
///
/// Both axes are caller-supplied on purpose. `yDomain` and `yAxisLabel` follow
/// the metric (pad a narrow band of values so they stay distinct; format
/// seconds as `m:ss`), and `xAxisLabel` names each point ("R1", "R2", …). A
/// tick is drawn at every point's x, so keep the series short enough for the
/// labels to fit.
///
/// Which direction is "good" is the caller's call too: pass `risingColor` and
/// `fallingColor` to suit the metric.
///
/// Renders plain content — wrap it in your own `Section` or card.
public struct SlopeColoredSeriesChart: View {

    private let points: [SeriesPoint]
    private let yDomain: ClosedRange<Double>
    private let xAxisLabel: (Double) -> String
    private let yAxisLabel: (Double) -> String
    private let risingColor: Color
    private let fallingColor: Color
    private let height: CGFloat

    public init(
        points: [SeriesPoint],
        yDomain: ClosedRange<Double>,
        xAxisLabel: @escaping (Double) -> String,
        yAxisLabel: @escaping (Double) -> String,
        risingColor: Color = .blue,
        fallingColor: Color = .red,
        height: CGFloat = 140
    ) {
        self.points = points
        self.yDomain = yDomain
        self.xAxisLabel = xAxisLabel
        self.yAxisLabel = yAxisLabel
        self.risingColor = risingColor
        self.fallingColor = fallingColor
        self.height = height
    }

    /// One leg of the line: the pair of points it spans, and which way it went.
    /// A flat segment counts as rising, so a plateau doesn't read as a decline.
    struct Segment: Identifiable, Equatable {
        let id: Int
        let start: SeriesPoint
        let end: SeriesPoint

        var isRising: Bool { end.value >= start.value }
    }

    /// Consecutive pairs of `points`, in order. Pure so it's unit-testable.
    /// Fewer than two points means nothing to connect — no segments.
    static func segments(from points: [SeriesPoint]) -> [Segment] {
        guard points.count > 1 else { return [] }
        return zip(points, points.dropFirst()).enumerated().map { index, pair in
            Segment(id: index, start: pair.0, end: pair.1)
        }
    }

    private func color(for segment: Segment) -> Color {
        segment.isRising ? risingColor : fallingColor
    }

    public var body: some View {
        Chart {
            // Each segment is its own series so it can carry its own color;
            // a single series would take one style for the whole line.
            ForEach(Self.segments(from: points)) { segment in
                LineMark(
                    x: .value("X", segment.start.x),
                    y: .value("Value", segment.start.value),
                    series: .value("Segment", segment.id)
                )
                .foregroundStyle(color(for: segment))
                LineMark(
                    x: .value("X", segment.end.x),
                    y: .value("Value", segment.end.value),
                    series: .value("Segment", segment.id)
                )
                .foregroundStyle(color(for: segment))
            }
            // Indexed rather than keyed by x: repeated x values are the
            // caller's business, and a duplicate id would drop a point.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value("X", point.x),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(.primary)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: points.map(\.x)) { value in
                AxisValueLabel {
                    if let value = value.as(Double.self) {
                        Text(xAxisLabel(value))
                    }
                }
            }
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
}

#if DEBUG
#Preview("SlopeColoredSeriesChart") {
    SlopeColoredSeriesChart(
        points: [72, 85, 81, 96, 104].enumerated().map { SeriesPoint(x: Double($0 + 1), value: $1) },
        yDomain: 0...125,
        xAxisLabel: { "R\(Int($0))" },
        yAxisLabel: { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) },
        risingColor: .green,
        fallingColor: .orange
    )
    .padding()
}
#endif
