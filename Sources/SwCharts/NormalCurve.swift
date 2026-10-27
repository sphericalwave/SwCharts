import Foundation

/// Gaussian PDF sampling for `NormalDistributionChart`, split out as pure
/// functions so it's unit-testable without SwiftUI.
enum NormalCurve {
    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    /// `samples + 1` points spanning ±3σ around `mean`. `stretchTo` widens
    /// the domain to keep an out-of-range marker on-canvas; `floorAtZero`
    /// clamps the lower bound for quantities that can't go negative.
    static func points(mean: Double, stddev: Double, samples: Int = 60,
                        stretchTo: Double? = nil, floorAtZero: Bool = false) -> [Point] {
        guard stddev > 0 else { return [] }
        let (lo, hi) = domain(mean: mean, stddev: stddev, stretchTo: stretchTo, floorAtZero: floorAtZero)
        let step = (hi - lo) / Double(samples)
        return (0...samples).map { i in
            let x = lo + Double(i) * step
            let d = (x - mean) / stddev
            let y = (1.0 / (stddev * (2.0 * .pi).squareRoot())) * exp(-0.5 * d * d)
            return Point(x: x, y: y)
        }
    }

    /// σ-multiple tick marks (-2σ…+2σ) that fall within the (possibly
    /// stretched/floored) domain around `mean`.
    static func ticks(mean: Double, stddev: Double,
                       stretchTo: Double? = nil, floorAtZero: Bool = false) -> [Double] {
        guard stddev > 0 else { return [] }
        let (lo, hi) = domain(mean: mean, stddev: stddev, stretchTo: stretchTo, floorAtZero: floorAtZero)
        return [-2, -1, 0, 1, 2]
            .map { mean + $0 * stddev }
            .filter { $0 >= lo && $0 <= hi }
    }

    private static func domain(mean: Double, stddev: Double,
                                stretchTo: Double?, floorAtZero: Bool) -> (Double, Double) {
        var lo = mean - 3 * stddev
        var hi = mean + 3 * stddev
        if let v = stretchTo {
            lo = min(lo, v - 0.5 * stddev)
            hi = max(hi, v + 0.5 * stddev)
        }
        if floorAtZero { lo = max(lo, 0) }
        return (lo, hi)
    }
}
