import SwiftUI
import Charts

/// A `Section`-ready normal curve fitted to (μ, σ) of some sample.
/// With no `markerValue`, it's an at-a-glance view of the distribution:
/// `RuleMark` at μ labeled "avg N · σ N". With `markerValue` set, that
/// mean marker is replaced by one at the given value, labeled with its
/// z-score relative to (μ, σ) — for highlighting where a single sample
/// sits within the wider distribution. Renders nothing if `stddev <= 0`
/// or `count < 2` (no shape to show).
public struct NormalDistributionChart: View {
    private let mean: Double
    private let stddev: Double
    private let count: Int
    private let title: String
    private let isLoading: Bool
    private let markerValue: Double?
    private let markerLabel: String
    private let floorAtZero: Bool

    public init(
        mean: Double,
        stddev: Double,
        count: Int,
        title: String = "Distribution",
        isLoading: Bool = false,
        markerValue: Double? = nil,
        markerLabel: String = "this",
        floorAtZero: Bool = false
    ) {
        self.mean = mean
        self.stddev = stddev
        self.count = count
        self.title = title
        self.isLoading = isLoading
        self.markerValue = markerValue
        self.markerLabel = markerLabel
        self.floorAtZero = floorAtZero
    }

    public var body: some View {
        if isLoading {
            Section(title) {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
        } else if stddev > 0, count >= 2 {
            let curve = NormalCurve.points(mean: mean, stddev: stddev, stretchTo: markerValue, floorAtZero: floorAtZero)
            let ticks = NormalCurve.ticks(mean: mean, stddev: stddev, stretchTo: markerValue, floorAtZero: floorAtZero)
            Section(title) {
                Chart {
                    ForEach(curve, id: \.x) { pt in
                        AreaMark(
                            x: .value("Value", pt.x),
                            y: .value("Density", pt.y)
                        )
                        .foregroundStyle(.tint.opacity(0.25))
                    }
                    if let markerValue {
                        let z = (markerValue - mean) / stddev
                        RuleMark(x: .value(markerLabel, markerValue))
                            .foregroundStyle(.tint)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .annotation(position: .top, alignment: .center) {
                                Text("\(Int(markerValue.rounded())) \(markerLabel) · \(Self.zScoreLabel(z))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tint)
                            }
                    } else {
                        RuleMark(x: .value("avg", mean))
                            .foregroundStyle(.tint)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .annotation(position: .top, alignment: .center) {
                                Text("avg \(Int(mean.rounded())) · σ \(Int(stddev.rounded()))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tint)
                            }
                    }
                }
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: ticks) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v.rounded()))")
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
            }
        }
    }

    private static func zScoreLabel(_ z: Double) -> String {
        if abs(z) < 0.05 { return "~0σ" }
        let sign = z >= 0 ? "+" : "−"
        return String(format: "%@%.1fσ", sign, abs(z))
    }
}

#if DEBUG
#Preview("NormalDistributionChart") {
    Form {
        NormalDistributionChart(mean: 72, stddev: 8, count: 240)
    }
}
#endif
