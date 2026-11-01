import Foundation

/// How a line chart joins its points.
public enum LineInterpolation: Sendable {
    /// Straight segments, point to point.
    case linear
    /// One smooth curve through every point (`CatmullRomSpline`), still
    /// drawn segment by segment so each leg can keep its own style.
    case catmullRom
}

/// A Catmull-Rom curve through a series, sampled one segment at a time so each
/// segment can be drawn as its own chart series (its own color, its own dash)
/// while neighbouring segments still meet with matching tangents — no kinks.
///
/// Swift Charts' `.interpolationMethod(.catmullRom)` can't do this: it splines
/// within one series only, so splitting a line into per-segment series to
/// color them turns every segment back into a straight line.
///
/// The curve is a function of x — each segment is a cubic Hermite piece in x,
/// with Catmull-Rom tangents (the three-point slope, weighted for uneven x
/// spacing). Parameterizing by x rather than by distance in the plane keeps it
/// from ever bending back in time, and it doesn't depend on the plot's pixel
/// aspect ratio, which pure math can't know.
///
/// **Clamping.** Tangents are limited the Fritsch–Carlson way: zero at a local
/// peak or valley, and at most 3× the neighbouring segment slopes elsewhere.
/// So every segment stays within the range of its own two endpoints — a jump
/// from 0 to 3,000 rises without dipping below 0 first, and a peak isn't
/// drawn higher than the point that makes it. Where no overshoot was coming,
/// the curve is plain Catmull-Rom.
public enum CatmullRomSpline {

    /// The default sample count per segment: smooth at chart sizes, cheap
    /// enough for a few dozen segments.
    public static let defaultSamplesPerSegment = 16

    /// One array of samples per segment between consecutive `points`, in
    /// order. Each array starts exactly on its segment's first point and ends
    /// exactly on its last, so the next segment picks up where it left off.
    /// Fewer than two points means nothing to connect — no segments.
    ///
    /// `points` must be in increasing x; a repeated x gets a straight segment.
    public static func segments(
        through points: [SeriesPoint],
        samplesPerSegment: Int = defaultSamplesPerSegment
    ) -> [[SeriesPoint]] {
        guard points.count > 1 else { return [] }
        let tangents = tangents(for: points)
        let steps = max(samplesPerSegment, 1)
        return (0..<(points.count - 1)).map { index in
            let p0 = points[index], p1 = points[index + 1]
            let h = p1.x - p0.x
            guard h > 0 else { return [p0, p1] }
            return (0...steps).map { step in
                // Hit the endpoints exactly, not via the basis sums.
                if step == 0 { return p0 }
                if step == steps { return p1 }
                let t = Double(step) / Double(steps)
                let t2 = t * t, t3 = t2 * t
                let h00 = 2 * t3 - 3 * t2 + 1
                let h10 = t3 - 2 * t2 + t
                let h01 = -2 * t3 + 3 * t2
                let h11 = t3 - t2
                let value = h00 * p0.value + h10 * h * tangents[index]
                    + h01 * p1.value + h11 * h * tangents[index + 1]
                return SeriesPoint(x: p0.x + t * h, value: value)
            }
        }
    }

    /// `segments(through:)` for dated points, with x in seconds.
    public static func segments(
        through points: [ChartPoint],
        samplesPerSegment: Int = defaultSamplesPerSegment
    ) -> [[ChartPoint]] {
        segments(
            through: points.map { SeriesPoint(x: $0.start.timeIntervalSinceReferenceDate, value: $0.value) },
            samplesPerSegment: samplesPerSegment
        ).map { segment in
            segment.map { ChartPoint(start: Date(timeIntervalSinceReferenceDate: $0.x), value: $0.value) }
        }
    }

    /// dy/dx at each point: Catmull-Rom's three-point slope (one-sided at the
    /// ends), then limited so no segment overshoots its endpoints. A point's
    /// tangent is shared by the segments either side of it, which is what
    /// makes the joins smooth.
    static func tangents(for points: [SeriesPoint]) -> [Double] {
        let n = points.count
        guard n > 1 else { return Array(repeating: 0, count: n) }
        let secants: [Double] = (0..<(n - 1)).map { i in
            let h = points[i + 1].x - points[i].x
            return h > 0 ? (points[i + 1].value - points[i].value) / h : 0
        }
        var tangents = [Double](repeating: 0, count: n)
        tangents[0] = secants[0]
        tangents[n - 1] = secants[n - 2]
        for i in 1..<max(n - 1, 1) {
            let left = secants[i - 1], right = secants[i]
            // A peak, a valley or a flat side: level off here.
            guard left * right > 0 else { continue }
            let hl = points[i].x - points[i - 1].x
            let hr = points[i + 1].x - points[i].x
            tangents[i] = (left * hr + right * hl) / (hl + hr)
        }
        // Fritsch–Carlson: a segment with tangents within 3× its own slope
        // (and the same sign) stays monotone between its endpoints.
        for i in 0..<(n - 1) {
            let secant = secants[i]
            if secant == 0 {
                tangents[i] = 0
                tangents[i + 1] = 0
                continue
            }
            let limit = 3 * abs(secant)
            for j in [i, i + 1] {
                if tangents[j] * secant < 0 { tangents[j] = 0 }
                tangents[j] = max(-limit, min(limit, tangents[j]))
            }
        }
        return tangents
    }
}
